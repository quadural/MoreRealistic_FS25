
Vehicle.mrRegisterComponentXMLPaths = function(schema, superFunc, basePath)

    superFunc(schema, basePath)
    schema:register(XMLValueType.BOOL, basePath .. ".component(?)#mrDisableTerrainDisplacementCollision", "allow us to prevent component collision box to collide with 'CollisionFlag.TERRAIN_DISPLACEMENT'")

end
Vehicle.registerComponentXMLPaths = Utils.overwrittenFunction(Vehicle.registerComponentXMLPaths, Vehicle.mrRegisterComponentXMLPaths)

---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- check if we want to keep the genuine environment while loading this vehicle
-- useful for DLC vehicle we want to override since the "parentFile" in the xml config doesn't seem to work when trying to reference a parent file inside a DLC package
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
Vehicle.mrSetFilename = function(self, superFunc, filename)

    self.configFileName = filename
    self.configFileNameClean = Utils.getFilenameInfo(filename, true)

    local genuineConfigFilenameWanted = RealisticUtils.defaultVehiclesKeepEnvironmentTable[filename]
    if genuineConfigFilenameWanted~=nil then
        self.customEnvironment, self.baseDirectory = Utils.getModNameAndBaseDirectory(genuineConfigFilenameWanted)
    else
        self.customEnvironment, self.baseDirectory = Utils.getModNameAndBaseDirectory(filename)
    end
end
Vehicle.setFilename = Utils.overwrittenFunction(Vehicle.setFilename, Vehicle.mrSetFilename)

---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Add "MR" tag before name of vehicle (shop, when entering a vehicle or vehicle list)
-- "MR" tag is already added to storeItem within StoreManager.mrLoadItem function
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
Vehicle.mrGetFullName = function(self, superFunc)
    local name = self:getName()
    local storeItem = g_storeManager:getItemByXMLFilename(self.configFileName)

    --remove "MR" tag if already present
    if string.sub(name, 1, 3) == "MR " then
        name = string.sub(name, 4)
    end

    if storeItem ~= nil then
        local brand = g_brandManager:getBrandByIndex(self:getBrand())
        if brand ~= nil and brand.name ~= "NONE" then
            name = brand.title .. " " .. name
        end
    end

    if self.mrIsMrVehicle then
        return "MR ".. name
    end

    return name
end
Vehicle.getFullName = Utils.overwrittenFunction(Vehicle.getFullName, Vehicle.mrGetFullName)




Vehicle.mrLoad = function(self, superFunc, vehicleLoadingData)

    local result = superFunc(self, vehicleLoadingData)
    if result==nil then -- nil means everything is fine

        --load if vehicle is MR
        local xmlFile = loadXMLFile("Vehicle", self.xmlFile.filename)
        self.mrIsMrVehicle = getXMLBool(xmlFile, "vehicle.MR") or false

        self.mrCX = getXMLFloat(xmlFile, "vehicle.MR#dragCx") or 0.8 --default CX = 0.8 (tractor, trailer, tools)
        self.mrSCX = getXMLFloat(xmlFile, "vehicle.MR#SCx") --if nil, will be auto computed from size width and height

        PowerConsumer.mrLoadMrValues(self, xmlFile)
        Combine.mrLoadMrValues(self, xmlFile)

        self.mrForcePtoRpm = false

        self.mrTransmissionPowerRatio = getXMLFloat(xmlFile, "vehicle.mrTransmission#powerRatio") or 1
        self.mrTransmissionIsHydrostatic = getXMLBool(xmlFile, "vehicle.mrTransmission#isHydrostatic") or false
        self.mrTransmissionMaxEngineRotWanted = getXMLFloat(xmlFile, "vehicle.mrTransmission#maxRpmWanted") or 2200
        self.mrTransmissionMaxEngineRotWanted = self.mrTransmissionMaxEngineRotWanted * math.pi / 30 --rpm to rad/s
        self.mrTransmissionMinEngineRotWanted = getXMLFloat(xmlFile, "vehicle.mrTransmission#minRpmWanted")
        self.mrTransmissionIsHydrostaticAutomotive = false
        if self.mrTransmissionIsHydrostatic and self.mrTransmissionMinEngineRotWanted~=nil then
            self.mrTransmissionIsHydrostaticAutomotive = true
            self.mrTransmissionMinEngineRotWanted = self.mrTransmissionMinEngineRotWanted * math.pi / 30 --rpm to rad/s
            self.mrTransmissionAutomotiveTargetRot = 0
        end
        self.mrTransmissionCvtTargetRot = 0

        delete(xmlFile)

        self.mrAutoDirChangeWantedDirection = 0 --only useful when DIRECTION_CHANGE_MODE_MANUAL is off
        self.mrAutoDirChangeWaitingForRelease = false
        self.mrLastTurnedOnState = false
        self.mrWheelShapesCreated = false
        self.mrLastUpdateWheelsPhysicsTime = 0
        self.mrTemporizeAccelerationTimer = 0

    end

    return result
end
Vehicle.load = Utils.overwrittenFunction(Vehicle.load, Vehicle.mrLoad)

Vehicle.mrLoadComponentFromXML = function(self, superFunc, component, xmlFile, key, rootPosition, i)
    local result = superFunc(self, component, xmlFile, key, rootPosition, i)
    if result then
        local x0, y0, z0 = getCenterOfMass(component.node)
        component.mrDefaultCOMx = x0
        component.mrDefaultCOMy = y0
        component.mrDefaultCOMz = z0
        component.mrDefaultMass = getMass(component.node)
        component.mrDefaultMassBAK = component.mrDefaultMass

        local mrDisableTerrainDisplacementCollision = xmlFile:getValue(key.."#mrDisableTerrainDisplacementCollision")
        if mrDisableTerrainDisplacementCollision~=nil then
            setCollisionFilter(component.node, CollisionFlag.TERRAIN_DISPLACEMENT, 0)
            --setCollisionFilter(self.components[1].node, CollisionFlag.TERRAIN_DELTA, 0)
            --setCollisionFilter(self.components[1].node, CollisionFlag.TERRAIN, 0)
        end
    end
    return result
end
Vehicle.loadComponentFromXML = Utils.overwrittenFunction(Vehicle.loadComponentFromXML, Vehicle.mrLoadComponentFromXML)

Vehicle.mrOnFinishedLoading = function(self, superFunc)
    superFunc(self)
    --compute SCX for air resistance
    if self.mrSCX==nil then
        self.mrSCX = self.size.width * self.size.height * 0.6 * self.mrCX --0.6 because width is greater than real width => only for vehicle placement after purchase ? (in our case, tractor frontal surface = about 0.75 * real width and height)
    end
end
Vehicle.onFinishedLoading = Utils.overwrittenFunction(Vehicle.onFinishedLoading, Vehicle.mrOnFinishedLoading)



Vehicle.mrUpdateVehicleSpeed = function(self, superFunc, dt)
    superFunc(self, dt)
    if self.isServer and self.finishedFirstUpdate and self.components[1].isDynamic then
        --only apply drag force on root vehicle
        if self:getRootVehicle()==self then
            if self.lastSpeedReal>0.0028 then --no air resistance under 10kph = too weak compared to other forces
                --we want the max SCX from all attached "vehicles"
                local scx = self.mrSCX
                local childVehicles = self:getChildVehicles()
                if childVehicles~=nil and #childVehicles>1 then
                    for i=1, #childVehicles do
                        scx = math.max(scx, childVehicles[i].mrSCX) --self is part of "childVehicles", but not a problem here
                    end
                end
                local dragForce = -610 * scx * self.lastSpeedReal^2--0.5*1.22*v^2*scx
                local vx, vy, vz = getLinearVelocity(self.components[1].node)
                local spd = MathUtil.vector3Length(vx, vy, vz)
                if spd>0.002 then
                    addForce(self.components[1].node, dragForce*vx/spd, dragForce*vy/spd, dragForce*vz/spd,0,0.4*self.size.height,0,true)
                end
            end
        end
    end
end
Vehicle.updateVehicleSpeed = Utils.overwrittenFunction(Vehicle.updateVehicleSpeed, Vehicle.mrUpdateVehicleSpeed)


---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- MR = remove mass limit for vehicles. This is totally unrealistic. (there is no planet with this feature in our galaxy)
-- If some players wants to "cheat", this is more elegant to apply a factor to all "massPerLiter" => example : "baby" mode = every fillType is 50% lighter
-- Manage AddMassCOM = AdditionnalMassCenterOfMass
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
Vehicle.mrUpdateMass = function(self, superFunc)

    self.serverMass = 0

    for k, component in ipairs(self.components) do
        if component.defaultMass == nil then
            if component.isDynamic then
                component.defaultMass = getMass(component.node)
            else
                component.defaultMass = 1
            end
            component.mass = component.defaultMass
        end

        local mass = self:getAdditionalComponentMass(component)
        if mass == math.huge then
            Logging.devError("%s: Additional component '%d' mass is inf!", self.configFileName, k)
        end
        if component.mrAnimatedVehicleWantedComponentMass~=nil then
            --replace genuine mass of the component by the "animated vehicle wanted mass"
            component.mass = component.mrDefaultMass - component.mrDefaultMassBAK + component.mrAnimatedVehicleWantedComponentMass + mass
        else
            component.mass = component.mrDefaultMass + mass
        end

        if component.mass == math.huge then
            Logging.devError("%s: Setting component '%d' mass to inf!", self.configFileName, k)
        elseif component.mass <=0.001 then
            Logging.devError("%s: Setting component '%d' mass to loawer than 1kg!", self.configFileName, k)
        end

        self.serverMass = self.serverMass + component.mass

        if component.mrCenterOfMassIsDirty then
            component.mrCenterOfMassIsDirty = false
            if component.mrAnimatedVehicleWantedCOM~=nil then
                setCenterOfMass(component.node, component.mrAnimatedVehicleWantedCOM.x, component.mrAnimatedVehicleWantedCOM.y, component.mrAnimatedVehicleWantedCOM.z)
            else
                setCenterOfMass(component.node, component.mrDefaultCOMx, component.mrDefaultCOMy, component.mrDefaultCOMz)
            end
        end

    end

--     local realTotalMass = 0
--     for _, component in ipairs(self.components) do
--         realTotalMass = realTotalMass + self:getComponentMass(component)
--     end

    --self.precalculatedMass = realTotalMass - self.serverMass

    for _, component in ipairs(self.components) do
        --MR : dangerous, if maxComponentMass==precalculatedMass then game is crashing
        --MR : not useful to compute this value for each component
        --MR : not realistic at all = removed
        --local maxFactor = self.serverMass / (self.maxComponentMass - self.precalculatedMass)

--         if maxFactor > 1 then
--             component.mass = component.mass / maxFactor
--         end

        -- only update physically mass if difference to last mass is greater 20kg
        if self.isServer and component.isDynamic and math.abs(component.lastMass-component.mass) > 0.02 then
            setMass(component.node, component.mass)
            component.lastMass = component.mass

            --20250501 - manage varying center of mass
            --see "FillUnit.mrGetAdditionalComponentMass"
            if component.mrAdditionalMassWithCOM~=nil and component.mrAdditionalMassWithCOM>0.02 then --no need to vary the center of mass of the component if there are less than 20kg of additional mass
                local newX, newY, newZ
                local baseMass = component.mrDefaultMass
                local addMass = component.mrAdditionalMassWithCOM
                newX = (baseMass*component.mrDefaultCOMx+addMass*component.mrAdditionalMassWithCOMx)/(baseMass+addMass)
                newY = (baseMass*component.mrDefaultCOMy+addMass*component.mrAdditionalMassWithCOMy)/(baseMass+addMass)
                newZ = (baseMass*component.mrDefaultCOMz+addMass*component.mrAdditionalMassWithCOMz)/(baseMass+addMass)
                setCenterOfMass(component.node, newX, newY, newZ)
                component.mrAdditionalMassWithCOMmodified = true
            elseif component.mrAdditionalMassWithCOMmodified then
                --reset to default center of mass
                setCenterOfMass(component.node, component.mrDefaultCOMx, component.mrDefaultCOMy, component.mrDefaultCOMz)
                component.mrAdditionalMassWithCOMmodified = false
            end
        end
    end

    --self.serverMass = math.min(self.serverMass, self.maxComponentMass - self.precalculatedMass)
end
Vehicle.updateMass = Utils.overwrittenFunction(Vehicle.updateMass, Vehicle.mrUpdateMass)


--protection against divide by 0 if component1 is perfectly flat on world
Vehicle.getVehicleWorldXRot = function(self)
    local _, y, _ = localDirectionToWorld(self.components[1].node, 0, 0, 1)
    local slopeAngle = 0
    if y~=0 then
        slopeAngle = math.pi * 0.5 - math.atan(1/y)
        if slopeAngle > math.pi * 0.5 then
            slopeAngle = slopeAngle - math.pi
        end
    end
    return slopeAngle
end


Vehicle.mrGetIdleTurningActive = function(self)
    if self.spec_drivable~=nil and self.spec_drivable.idleTurningActive then
        return true
    end
    return false
end

---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Manage CombineSpeedLimit function of material rate
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
Vehicle.mrGetRawSpeedLimit = function(self, superFunc)
    local spdLimit = superFunc(self)
    if self.mrIsMrCombine then
        spdLimit = math.min(spdLimit, self.mrCombineSpeedLimit)
    end
    return spdLimit
end
Vehicle.getRawSpeedLimit = Utils.overwrittenFunction(Vehicle.getRawSpeedLimit, Vehicle.mrGetRawSpeedLimit)