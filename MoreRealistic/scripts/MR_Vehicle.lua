
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
        MRConveyorLoaderVehicle.mrLoadMrValues(self, xmlFile)

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
        self.mrTransmissionAccPedal = 0

        --20260306 - allow different transmission settings in pto mode
        if self.mrTransmissionIsHydrostatic then
            self.mrTransmissionPtoModeMaxEngineRotWanted = getXMLFloat(xmlFile, "vehicle.mrTransmission#ptoModeMaxRpmWanted")
            if self.mrTransmissionPtoModeMaxEngineRotWanted==nil then
                self.mrTransmissionPtoModeMaxEngineRotWanted = self.mrTransmissionMaxEngineRotWanted
            else
                self.mrTransmissionPtoModeMaxEngineRotWanted = self.mrTransmissionPtoModeMaxEngineRotWanted * math.pi / 30  --rpm to rad/s
            end
            self.mrTransmissionPtoModeMinEngineRotWanted = getXMLFloat(xmlFile, "vehicle.mrTransmission#ptoModeMinRpmWanted")
            if self.mrTransmissionPtoModeMinEngineRotWanted~=nil then
                self.mrTransmissionPtoModeIsHydrostaticAutomotive = true
                self.mrTransmissionPtoModeMinEngineRotWanted = self.mrTransmissionPtoModeMinEngineRotWanted * math.pi / 30 --rpm to rad/s
                self.mrTransmissionAutomotiveTargetRot = 0
            end
            self.mrTransmissionLastMaxEngineRotWanted = 0
        end

        --20260325 - mrImplement
        self.mrImplementProcessAreaWhileNotMoving = getXMLBool(xmlFile, "vehicle.mrImplement#processAreaWhileNotMoving") or false --allow this implement to process its workareas even if not moving (example : powerharrow)

        self.mrInlineAxleNumber = getXMLFloat(xmlFile, "vehicle.MR#inlineAxleNumber")
        self.mrGetGeneralPressureForRrFx = Vehicle.mrGetGeneralPressureForRrFx(self, self.mrInlineAxleNumber)

        self.mrAutoDirChangeWantedDirection = 0 --only useful when DIRECTION_CHANGE_MODE_MANUAL is off
        self.mrAutoDirChangeWaitingForRelease = false
        self.mrLastTurnedOnState = false
        self.mrWheelShapesCreated = false
        self.mrLastUpdateWheelsPhysicsTime = 0
        self.mrTemporizeAccelerationTimer = 0

        local categories = self.xmlFile:getValue("vehicle.storeData.category")
        self.mrStoreCategory = categories~=nil and categories[1] or "none"

        --we want to know if this is a "combine header trailer" implement
        if self.mrStoreCategory=="cutterTrailers" or self.mrStoreCategory=="forageHarvesterCutterTrailers" then
            self.mrIsHeaderTrailer = true
        end

        --very important for trailers : big difference in weight between empty and loaded => IRL, the suspension are not linear. This is always a system to get less spring when empty and more spring when loaded (example : multiple overlapping leaf springs. but not the same length which means the trailer is mainly using the longest spring when empty, and all the spring leaf when overloaded)
        --tips to fine tune a trailer ingame = fully fill the trailer with wheat, set the reference mass to the fully filled trailer mass, adjust the spring in the xml file. And then, look at what you get when empty without touching anything, it should be better than without the mrSuspension (in base game = trailers suspension are "hard as nail" when empty)
        --very important for a trailer with more than one axle. Especially useful for tracks (Example : augerwagon). Otherwise, you always end with one or more "wheelshape" not touching the ground at all.
        self.mrSuspensionActive = false
        self.mrSuspensionReferenceMass = getXMLFloat(xmlFile, "vehicle.mrSuspension#referenceMass") --kilos

        --should not be used when "wheelAxle" is present/in use for this vehicle
        if self.mrSuspensionReferenceMass~=nil and self.mrSuspensionReferenceMass>0 and self.spec_wheels~=nil and not self.spec_wheels.hasAxles then
            self.mrSuspensionActive = true
            self.mrSuspensionReferenceMass = 0.001 * self.mrSuspensionReferenceMass --kilos to tonnes
            self.mrSuspensionPowCurveFx = getXMLFloat(xmlFile, "vehicle.mrSuspension#powCurveFx") or 0.5 --default = 0.5 (0.5 = sqrt => 4x more mass means 2x more spring)
            self.mrSuspensionMinChangeForUpdate = 0.05*self.mrSuspensionReferenceMass --only update suspension if there is more than 5% difference in mass
            self.mrSuspensionLastMass = 0
        end

        delete(xmlFile)

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

---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Compute a general factor to apply to rolling resistance calculation function of the number of axle inline (wheels are following each other)
-- idea = a 20T total weight 2 axle trailer would not sink as much as a 10T total weight 1 axle trailer

-- indeed, the load per wheel is the same in both case.
-- But for the 2 axles trailer = the first axle wheels would "sink" as much as the single axle trailer's wheels. But then, the second axle's wheels would not sink as much given that it is running on the same "track" (ground is already packed)

-- so even if the ground pressure per wheel is the same in both case, the 2 axles trailer should not get 2 times the rolling resistance of the single axle trailer

-- if the second axle = 50% of the first axle
-- => avg sinking for the 2 axles = (1+0.5)/2=3/4 (0.75) avg factor

-- for a 3 axles trailer => 3rd axle = 1/3 of the first one
-- => avg sinking for 3 axles = (1+0.5+0.333)/3 = 0.6111111

-- But : there is also the tractor's wheels that "pack" the ground before the trailer one...

-- and so, we should also take into account the ground packing of the tractor before the trailer's wheels

-- in such a case, the difference between a 1,2 or 3 axle trailer would be :
-- 1 axle = 1/3 (because already packing from tractor front and rear wheels)
-- 2 axles = (1/3 + 1/4)/2 = 0.29167 => 0.875 compared to single axle
-- 3 axles = (1/3 + 1/4 + 1/5)/3 = 0.261111 => 0.783 compared to single axle
-- 4 axles = (1/3 + 1/4 + 1/5 + 1/6)/4 = 0.7125 compared to single axle

-- this is not a direct rolling resistance fx => this is a sinking fx
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- this is mainly for trailers or implements with more than one axle (following axle = wheel in the same track on each side) and with big load per wheel
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
Vehicle.mrGetGeneralPressureForRrFx = function(self, inlineAxleNumber)
    local fx = 1
    if inlineAxleNumber~=nil and inlineAxleNumber>1 then
        fx = 1/3
        for i=2, inlineAxleNumber do
            fx = fx + 1/(2+i)
        end
        fx = fx*3/inlineAxleNumber --divide by 1/3 == multiply by 3
    end
    return fx
end



Vehicle.mrUpdateTick = function(self, superFunc, dt)

    superFunc(self, dt)

    if self.isServer then
        if self.mrSuspensionActive then
            --check mass compared to mrSuspensionReferenceMass
            --more than 5% difference = update spring value
            --if self.lastSpeedReal~=0 then --quick check because and "idle" vehicle that is not updated by the physics engine => lastSpeedReal == 0
            if self.serverMass~=self.mrSuspensionLastMass then
                if math.abs(self.serverMass-self.mrSuspensionLastMass)>self.mrSuspensionMinChangeForUpdate then
                    local factorSpring = math.pow(self.serverMass/self.mrSuspensionReferenceMass, self.mrSuspensionPowCurveFx)
                    local factorDamper = math.sqrt(factorSpring)
                    for i=1, #self.spec_wheels.wheels do
                        --same way as "wheelAxle" from base game (which means we should not use both for the same vehicle)
                        self.spec_wheels.wheels[i].physics:setSuspensionMultipliers(factorSpring, factorDamper)
                    end
                    self.mrSuspensionLastMass = self.serverMass
                end
            end
        end
    end

end
Vehicle.updateTick = Utils.overwrittenFunction(Vehicle.updateTick, Vehicle.mrUpdateTick)


Vehicle.mrUpdate = function(self, superFunc, dt)

    superFunc(self, dt)

    if self.isServer then

        if self.mrRecoveryModeActive then
            if self.mrRecoveryModeTimer==nil or self.mrRecoveryModeTimer==0 then
                self.mrRecoveryModeTimer = dt
            else
                self.mrRecoveryModeTimer = self.mrRecoveryModeTimer + dt
            end

            if self.mrRecoveryModeTimer>10000 then --10s to try recovering
                --stop recovry process
                self.mrRecoveryModeTimer=0
                self.mrRecoveryModeActive = false
            else
                local fx = math.pow(self.mrRecoveryModeTimer/10000, 0.5)
                addForce(self.components[1].node, 0, fx*7*self.serverMass, 0, 0, 5, 0, true)
                local wx, wy, wz = localToWorld(self.components[1].node, 0, 5, 0)
                DebugGizmo.renderAtPosition(wx, wy, wz, 0, 1, 0, 0, 0, 1, "RecoveryTractionPoint")
            end
        end

    end

end
Vehicle.update = Utils.overwrittenFunction(Vehicle.update, Vehicle.mrUpdate)


Vehicle.getName = function(self)
    local storeItem = g_storeManager:getItemByXMLFilename(self.configFileName)
    if storeItem == nil then
        return "Unknown"
    end

    if storeItem.configurations ~= nil then
        for configName, _ in pairs(storeItem.configurations) do
            local configId = self.configurations[configName]
            local config = storeItem.configurations[configName][configId]
            if config~=nil and config.vehicleName ~= nil and config.vehicleName ~= "" then --check config is not nil
                return config.vehicleName
            end
        end
    end

    return storeItem.name
end
