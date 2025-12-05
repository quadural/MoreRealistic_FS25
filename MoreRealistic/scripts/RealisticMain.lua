local mrEngineModName = "MoreRealistic"
local mrEngineDirectory = g_modNameToDirectory[mrEngineModName]

--check the "moreRealistic" folder is present
if mrEngineDirectory==nil then
    Logging.error("[MoreRealistic] : ERROR, the moreRealistic mod folder must remains with the exact name = 'MoreRealistic'")
    return
end

RealisticMain = {}

RealisticMain.COMBINE_CAPACITY_FX = 1.25 --apply a 20% factor since this is a game to avoid getting too low max harvesting speed

--VehicleDebug.setState(VehicleDebug.DEBUG_PHYSICS)

local version = g_modManager:getModByName(g_currentModName).version
print("**********************************************************************")
Logging.info('[MoreRealistic] Loading version %s', version)

source(Utils.getFilename("scripts/RealisticUtils.lua", g_currentModDirectory))
source(Utils.getFilename("scripts/MR_AIImplement.lua", g_currentModDirectory))
source(Utils.getFilename("scripts/MR_AIVehicleUtil.lua", g_currentModDirectory))
source(Utils.getFilename("scripts/MR_AnimatedVehicle.lua", g_currentModDirectory))
source(Utils.getFilename("scripts/MR_Attachable.lua", g_currentModDirectory))
source(Utils.getFilename("scripts/MR_AttacherJoints.lua", g_currentModDirectory))
source(Utils.getFilename("scripts/MR_Combine.lua", g_currentModDirectory))
source(Utils.getFilename("scripts/MR_ConveyorLoaderVehicle.lua", g_currentModDirectory))
source(Utils.getFilename("scripts/MR_Cultivator.lua", g_currentModDirectory))
source(Utils.getFilename("scripts/MR_Drivable.lua", g_currentModDirectory))
source(Utils.getFilename("scripts/MR_FillTypeManager.lua", g_currentModDirectory))
source(Utils.getFilename("scripts/MR_FillUnit.lua", g_currentModDirectory))
source(Utils.getFilename("scripts/MR_FruitPreparer.lua", g_currentModDirectory))
source(Utils.getFilename("scripts/MR_FruitTypeManager.lua", g_currentModDirectory))
source(Utils.getFilename("scripts/MR_GroundReference.lua", g_currentModDirectory))
source(Utils.getFilename("scripts/MR_Lights.lua", g_currentModDirectory))
source(Utils.getFilename("scripts/MR_Motorized.lua", g_currentModDirectory))
source(Utils.getFilename("scripts/MR_ObjectChangeUtil.lua", g_currentModDirectory))
source(Utils.getFilename("scripts/MR_Plow.lua", g_currentModDirectory))
source(Utils.getFilename("scripts/MR_PowerConsumer.lua", g_currentModDirectory))
source(Utils.getFilename("scripts/MR_SoundManager.lua", g_currentModDirectory))
source(Utils.getFilename("scripts/MR_SpeedRotatingParts.lua", g_currentModDirectory))
source(Utils.getFilename("scripts/MR_Sprayer.lua", g_currentModDirectory))
source(Utils.getFilename("scripts/MR_StoreManager.lua", g_currentModDirectory))
source(Utils.getFilename("scripts/MR_Vehicle.lua", g_currentModDirectory))
source(Utils.getFilename("scripts/MR_VehicleConfigurationDataAdditionalMass.lua", g_currentModDirectory))
source(Utils.getFilename("scripts/MR_VehicleDebug.lua", g_currentModDirectory))
source(Utils.getFilename("scripts/MR_VehicleMotor.lua", g_currentModDirectory))
source(Utils.getFilename("scripts/MR_VehicleSystem.lua", g_currentModDirectory))
source(Utils.getFilename("scripts/MR_Weather.lua", g_currentModDirectory))
source(Utils.getFilename("scripts/MR_Wheel.lua", g_currentModDirectory))
source(Utils.getFilename("scripts/MR_WheelDebug.lua", g_currentModDirectory))
source(Utils.getFilename("scripts/MR_WheelPhysics.lua", g_currentModDirectory))
source(Utils.getFilename("scripts/MR_WheelVisualPart.lua", g_currentModDirectory))
source(Utils.getFilename("scripts/MR_Wheels.lua", g_currentModDirectory))
source(Utils.getFilename("scripts/MR_WheelsUtil.lua", g_currentModDirectory))
source(Utils.getFilename("scripts/MR_WoodCrusher.lua", g_currentModDirectory))
source(Utils.getFilename("scripts/FIX_PF.lua", g_currentModDirectory))

-- load "moreRealistic" figures for tire friction vs surface and rolling resistance
MoreRealistic.RealisticUtils.loadRealTyresFrictionAndRr(g_currentModDirectory .. "data/TyresFrictionAndRrTable.xml")

-- load modified data for default vehicles
MoreRealistic.RealisticUtils.loadDefaultVehiclesModifiedData(g_currentModDirectory .. "data/overriding", "overridingDatabase.xml")

MoreRealistic.RealisticUtils.mrBaseDir = g_currentModDirectory


print(" -- loading finished -- ")
print("**********************************************************************")


function RealisticMain:loadMap(name)
    RealisticUtils.loadTerrainIdToName()
    g_currentMission.environment.weather.getGroundWetness = Utils.overwrittenFunction(g_currentMission.environment.weather.getGroundWetness, Weather.mrGetGroundWetness)
end


--allow to use the following functions :
--draw()
--update(dt)
--loadMap(name)
--deleteMap()
--mouseEvent(posX, posY,isDown, isUp, mouseKey)
--keyEvent(unicode, sym, modifier, isDown)
addModEventListener(RealisticMain)
