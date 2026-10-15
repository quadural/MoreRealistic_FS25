-- Standalone regression test: Lua 5.1, no GIANTS runtime required.
local noop = function() end
Utils = {
    overwrittenFunction = function(_, replacement) return replacement end,
    appendedFunction = function(_, replacement) return replacement end,
    prependedFunction = function(_, replacement) return replacement end,
}
WheelPhysics = setmetatable({}, {__index = function() return noop end})
WheelsUtil = { GROUND_FIELD = 1, GROUND_SOFT_TERRAIN = 2 }

dofile("MoreRealistic/scripts/MR_WheelPhysics.lua")

local function close(actual, expected)
    return math.abs(actual - expected) < 0.000001
end

local function checkGround(groundType)
    local width, radius, load = 0.6, 0.9, 100
    local groundSubType, axleFactor = 0, 1
    local pressure = WheelPhysics.mrGetPressureFx(width, radius, load)
    for _, driven in ipairs({false, true}) do
        local dry = WheelPhysics.mrGetSoftTerrainDryFx(pressure, groundType, groundSubType, driven)
        local wet = WheelPhysics.mrGetSoftTerrainWetFx(pressure, groundType, groundSubType, driven)
        local dryAtEndpoint = WheelPhysics.mrGetRrFx(width, radius, load, groundType, groundSubType, 0, axleFactor, driven)
        local wetAtEndpoint = WheelPhysics.mrGetRrFx(width, radius, load, groundType, groundSubType, 1, axleFactor, driven)
        assert(close(dryAtEndpoint, dry), "dry endpoint ignores driven wheel state")
        assert(close(wetAtEndpoint, wet), "wet endpoint ignores driven wheel state")
        local half = WheelPhysics.mrGetRrFx(width, radius, load, groundType, groundSubType, 0.5, axleFactor, driven)
        local fraction = math.sqrt(0.5)
        assert(close(half, (1 - fraction) * dry + fraction * wet), "interpolation differs")
    end
end

checkGround(WheelsUtil.GROUND_FIELD)
checkGround(WheelsUtil.GROUND_SOFT_TERRAIN)
print("PASS: driven and non-driven rolling resistance at dry/wet boundaries")
