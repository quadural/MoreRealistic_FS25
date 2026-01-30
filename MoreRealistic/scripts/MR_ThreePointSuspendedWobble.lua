-- MR_ThreePointSuspendedWobble.lua
-- Adds subtle inertia-based wobble to 3-point hitch implements
-- ONLY when suspended (raised, not working / not on ground).
-- Effect is driven by:
--  - longitudinal acceleration (pitch)
--  - lateral acceleration from turning (roll)
--  - small yaw from tractor yaw rate
--  - slight influence from tractor slope

MR_ThreePointSuspendedWobble = {}

------------------------------------------------
-- CONFIG
------------------------------------------------
local CFG = {
    -- Maximum offsets (DEGREES)
    maxRollDeg  = 1.4,
    maxPitchDeg = 1.1,
    maxYawDeg   = 0.3,

    -- Joint softness
    spring  = 22000,
    damping = 3000,

    -- Pitch from acceleration/braking (m/s^2 -> deg)
    accelToPitchDeg = 0.060,   -- 0.04..0.10

    -- Roll from lateral acceleration v * yawRate (m/s^2 -> deg)
    latToRollDeg = 0.35,       -- 0.25..0.60
    latAccClamp  = 5.0,        -- m/s^2 (~0.5g)

    -- Small yaw from yawRate (rad/s -> deg)
    yawRateToYawDeg = 0.05,    -- 0.03..0.08

    -- Mass influence: (tons / 2t) clamped
    massMin = 0.7,
    massMax = 2.5,

    -- Tractor slope influence (rad -> deg)
    slopeToRollDeg  = 0.20,
    slopeToPitchDeg = 0.20,

    -- Different smoothing per axis
    smoothPitch = 0.14,
    smoothRoll  = 0.10,
    smoothYaw   = 0.13
}

------------------------------------------------
-- UTILS
------------------------------------------------
local function degToRad(d) return d * math.pi / 180 end

local function clampLocal(x, a, b)
    if x < a then return a end
    if x > b then return b end
    return x
end

local function clamp(x, a, b)
    if MathUtil ~= nil and MathUtil.clamp ~= nil then
        return MathUtil.clamp(x, a, b)
    end
    return clampLocal(x, a, b)
end

------------------------------------------------
-- Detect 3-point hitch
------------------------------------------------
local function isThreePoint(attacherJoint)
    if attacherJoint == nil then return false end

    if AttacherJoints ~= nil and AttacherJoints.JOINTTYPE_THREEPOINT ~= nil then
        if attacherJoint.jointType == AttacherJoints.JOINTTYPE_THREEPOINT then
            return true
        end
    end

    -- Fallback heuristic (for custom mods)
    local n = (attacherJoint.name ~= nil and tostring(attacherJoint.name) or ""):lower()
    local jn = (attacherJoint.jointNodeName ~= nil and tostring(attacherJoint.jointNodeName) or ""):lower()
    local s = n .. " " .. jn
    return (s:find("three") ~= nil) or (s:find("3point") ~= nil) or (s:find("threepoint") ~= nil)
end

------------------------------------------------
-- Check if implement is suspended
------------------------------------------------
local function isSuspended(implementObject)
    if implementObject == nil then return false end

    if implementObject.getIsLowered ~= nil then
        if implementObject:getIsLowered() == true then
            return false
        end
    end

    if implementObject.getIsInWorkPosition ~= nil then
        if implementObject:getIsInWorkPosition() == true then
            return false
        end
    end

    local wheels = implementObject.spec_wheels
    if wheels ~= nil and wheels.wheels ~= nil then
        for _, w in ipairs(wheels.wheels) do
            if w.hasGroundContact == true then
                return false
            end
        end
    end

    return true
end

------------------------------------------------
-- STORAGE
------------------------------------------------
local function getStore(vehicle)
    vehicle._mrTPW = vehicle._mrTPW or {
        joints = {},

        lastSpeed = 0,
        prevYaw = nil,

        pitch = 0,
        roll  = 0,
        yaw   = 0
    }
    return vehicle._mrTPW
end

------------------------------------------------
-- APPLY JOINT LIMITS
------------------------------------------------
local function applyJoint(jointId, rollRad, pitchRad, yawRad)
    if jointId == nil or jointId == 0 then return end

    local rMax = degToRad(CFG.maxRollDeg)
    local pMax = degToRad(CFG.maxPitchDeg)
    local yMax = degToRad(CFG.maxYawDeg)

    -- Axis: 0=roll, 1=pitch, 2=yaw
    setJointRotationLimit(jointId, 0, -rMax + rollRad,  rMax + rollRad)
    setJointRotationLimit(jointId, 1, -pMax + pitchRad, pMax + pitchRad)
    setJointRotationLimit(jointId, 2, -yMax + yawRad,   yMax + yawRad)

    setJointRotationLimitSpring(jointId, CFG.spring, CFG.spring, CFG.spring)
    setJointRotationLimitDamping(jointId, CFG.damping, CFG.damping, CFG.damping)
end

------------------------------------------------
-- ATTACH / DETACH
------------------------------------------------
function MR_ThreePointSuspendedWobble:onAttachImplement(implement)
    if implement == nil then return end
    local aj = implement.attacherJoint
    if not isThreePoint(aj) then return end

    local store = getStore(self)
    local jointId = aj.jointId or aj.jointIndex or aj.joint
    if jointId == nil then return end

    table.insert(store.joints, {
        jointId = jointId,
        object  = implement.object
    })
end

function MR_ThreePointSuspendedWobble:onDetachImplement(implement)
    if implement == nil then return end
    local aj = implement.attacherJoint
    if aj == nil then return end

    local jointId = aj.jointId or aj.jointIndex or aj.joint
    if jointId == nil then return end

    local store = getStore(self)
    for i = #store.joints, 1, -1 do
        if store.joints[i].jointId == jointId then
            table.remove(store.joints, i)
        end
    end
end

------------------------------------------------
-- UPDATE
------------------------------------------------
function MR_ThreePointSuspendedWobble:onUpdate(dt)
    local store = getStore(self)
    if store == nil or store.joints == nil or #store.joints == 0 then return end
    if dt == nil or dt <= 0 then return end

    local dtS = dt * 0.001

    -- Tractor speed (m/s)
    local speed = 0
    if self.getLastSpeed ~= nil then
        speed = self:getLastSpeed() or 0
    end

    -- Longitudinal acceleration (m/s^2)
    local accel = (speed - (store.lastSpeed or 0)) / math.max(dtS, 0.001)
    store.lastSpeed = speed

    -- Dominant implement mass (tons)
    local implementMassT = 1.0
    for _, j in ipairs(store.joints) do
        if j.object ~= nil and j.object.getTotalMass ~= nil then
            local mKg = j.object:getTotalMass()
            if mKg ~= nil and mKg > 0 then
                implementMassT = math.max(implementMassT, mKg / 1000.0)
            end
        end
    end
    local massFactor = clamp(implementMassT / 2.0, CFG.massMin, CFG.massMax)

    -- Yaw rate (rad/s)
    local rx, ry, rz = getWorldRotation(self.rootNode)
    if store.prevYaw == nil then store.prevYaw = ry end
    local yawRate = (ry - store.prevYaw) / math.max(dtS, 0.001)
    store.prevYaw = ry

    -- Lateral acceleration approximation (m/s^2)
    local lateralAcc = speed * yawRate
    lateralAcc = clamp(lateralAcc, -CFG.latAccClamp, CFG.latAccClamp)

    -- Tractor slope influence
    local slopeRollDeg  = rx * CFG.slopeToRollDeg
    local slopePitchDeg = rz * CFG.slopeToPitchDeg

    -- Targets (DEGREES)
    local targetPitch = (accel * CFG.accelToPitchDeg * massFactor) + slopePitchDeg
    local targetRoll  = (lateralAcc * CFG.latToRollDeg * massFactor) + slopeRollDeg
    local targetYaw   = (yawRate * 57.2958 * CFG.yawRateToYawDeg * massFactor)

    -- Smoothing
    store.pitch = (store.pitch or 0) + (targetPitch - (store.pitch or 0)) * CFG.smoothPitch
    store.roll  = (store.roll  or 0) + (targetRoll  - (store.roll  or 0)) * CFG.smoothRoll
    store.yaw   = (store.yaw   or 0) + (targetYaw   - (store.yaw   or 0)) * CFG.smoothYaw

    -- Clamp final values
    local finalP = clamp(store.pitch, -CFG.maxPitchDeg, CFG.maxPitchDeg)
    local finalR = clamp(store.roll,  -CFG.maxRollDeg,  CFG.maxRollDeg)
    local finalY = clamp(store.yaw,   -CFG.maxYawDeg,   CFG.maxYawDeg)

    for _, j in ipairs(store.joints) do
        if isSuspended(j.object) then
            applyJoint(j.jointId, degToRad(finalR), degToRad(finalP), degToRad(finalY))
        else
            -- Implement working/on ground -> rigid hitch
            applyJoint(j.jointId, 0, 0, 0)
        end
    end
end

------------------------------------------------
-- INSTALL
------------------------------------------------
function MR_ThreePointSuspendedWobble.install()
    if AttacherJoints ~= nil then
        if AttacherJoints.onAttachImplement ~= nil then
            Utils.appendedFunction(AttacherJoints, "onAttachImplement", MR_ThreePointSuspendedWobble.onAttachImplement)
        end
        if AttacherJoints.onDetachImplement ~= nil then
            Utils.appendedFunction(AttacherJoints, "onDetachImplement", MR_ThreePointSuspendedWobble.onDetachImplement)
        end
    end

    if Vehicle ~= nil and Vehicle.update ~= nil then
        Utils.appendedFunction(Vehicle, "update", MR_ThreePointSuspendedWobble.onUpdate)
    end
end

addModEventListener({
    loadMap = function()
        MR_ThreePointSuspendedWobble.install()
    end
})
