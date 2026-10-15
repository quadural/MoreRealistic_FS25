-- Reproduction of rolling resistance going stale when friction is constant.
-- Pure Lua 5.1 stubs; test only the modified helper's behavior.
local noop=function() end
Utils={
    overwrittenFunction=function(_,new) return new end,
    prependedFunction=function(_,new) return new end,
    appendedFunction=function(_,new) return new end,
}
WheelPhysics=setmetatable({}, {__index=function() return noop end})
WheelsUtil={
    GROUND_FIELD=4,GROUND_SOFT_TERRAIN=3,
    mrGetGroundType=function() return 3,0 end,
    getTireFriction=function() return 0.75 end,
    mrGetTireRollingResistance=function(_,_,wetness) return 0.03+wetness*0.03 end,
}
FieldGroundType={NONE=0}
WheelContactType={GROUND=1,GROUND_HEIGHT=2}
dofile("MoreRealistic/scripts/MR_WheelPhysics.lua")
local wheel={
    vehicle={getLastSpeed=function() return 10 end},
    mrLastWheelSpeedS=0,
    mrFrictionNeedUpdate=true,
    densityType=1,
    hasSnowContact=false,
    contact=1,
    groundDepth=0.2,
    lastTerrainAttribute=1,
    tireType=1,
    tireGroundFrictionCoeff=0.75,
    mrTireGroundRollingResistanceCoeff=0.03,
}
local function check(value,expectation)
    WheelPhysics.mrUpdateFriction(wheel,noop,16,value)
    assert(math.abs(wheel.mrTireGroundRollingResistanceCoeff-expectation)<1e-6,
        "rolling resistance coefficient stale for wetness "..value)
end
check(0,0.03)
check(1,0.06)
check(0.25,0.045) -- sqrt(0.25)=0.5
check(0,0.03)
print("PASS: RR coefficient follows wetness even when grip is unchanged")
