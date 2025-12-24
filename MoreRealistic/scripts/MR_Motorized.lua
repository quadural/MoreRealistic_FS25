Motorized.mrRegisterMotorXMLPaths = function(schema, superFunc, baseKey)
    superFunc(schema, baseKey)
    schema:register(XMLValueType.FLOAT, baseKey .. ".motor#mrGovernorRpmRange", "Governor rpm range", 140)
    schema:register(XMLValueType.FLOAT, baseKey .. ".motor#mrInertiaFx", "Engine inertia factor value to apply to auto-compute value", 1)
    schema:register(XMLValueType.FLOAT, baseKey .. ".motor#mrEngineBrakingFx", "Engine braking factor", 1)
    schema:register(XMLValueType.BOOL, baseKey .. ".transmission.directionChange#mrKeepCurrentGear", "keep the same gear while changing direction", false)
end
Motorized.registerMotorXMLPaths = Utils.overwrittenFunction(Motorized.registerMotorXMLPaths, Motorized.mrRegisterMotorXMLPaths)

Motorized.mrLoadMotor = function(self, superFunc, xmlFile, motorId)

    local key
    local fallbackConfigKey = "vehicle.motorized.motorConfigurations.motorConfiguration(0)"
    -- Sets motorId to default 1 if motor cannot be found.
    key, motorId = ConfigurationUtil.getXMLConfigurationKey(xmlFile, motorId, "vehicle.motorized.motorConfigurations.motorConfiguration", "vehicle.motorized", "motor")
    self.mrGovernorRange = ConfigurationUtil.getConfigurationValue(xmlFile, key, ".motor", "#mrGovernorRpmRange", 150, fallbackConfigKey)
    local motorInertiaFx = ConfigurationUtil.getConfigurationValue(xmlFile, key, ".motor", "#mrInertiaFx", 1, fallbackConfigKey)
    local motorEngineBrakingFx = ConfigurationUtil.getConfigurationValue(xmlFile, key, ".motor", "#mrEngineBrakingFx", nil, fallbackConfigKey)

    self.mrEngineIsBraking = false
    self.mrLastEngineIsBraking = false
    self.mrEngineBrakingPowerToApply = 0
    self.mrLastFuelUsageS = 0
    superFunc(self, xmlFile, motorId)

    local transmissionKey = key .. ".transmission"
    if not xmlFile:hasProperty(transmissionKey) then
        transmissionKey = fallbackConfigKey .. ".transmission"
    end
    self.spec_motorized.motor.mrDirectionKeepCurrentGear = xmlFile:getValue(transmissionKey .. ".directionChange#mrKeepCurrentGear", false)

    --try to load inertia from xml or compute its value (we don't especially want the base game inertia value)
    if self.spec_motorized.motor.rotInertia == (self.spec_motorized.motor.peakMotorTorque / 600) then
        --take into account max power rpm and max torque to estimate engine MOI
        --what we want => larger engine (displacement) = more MOI
        self.spec_motorized.motor.rotInertia = motorInertiaFx * (self.spec_motorized.motor.peakMotorTorque/300)*2000/(self.spec_motorized.motor.peakMotorPowerRotSpeed*9.5493)
    end

    if motorEngineBrakingFx==nil then
        self.spec_motorized.motor.mrEngineBrakingPowerFx = 0.7
        if self.mrTransmissionIsHydrostatic then
            self.spec_motorized.motor.mrEngineBrakingPowerFx = 0.9
        end
    else
        self.spec_motorized.motor.mrEngineBrakingPowerFx = motorEngineBrakingFx
    end

    self.spec_motorized.mrLastMinGearRatioSet = 0
    self.spec_motorized.mrLastMaxGearRatioSet = 0
    self.spec_motorized.motor.mrLastGearRatioChangeTime = 0

    --20250605 - we don't want a "autoGearChangeTime" == 0, this is not "realistic"
    if self.spec_motorized.motor.autoGearChangeTime==0 then
        self.spec_motorized.motor:setAutoGearChangeTime(700) --700ms
    end

end
Motorized.loadMotor = Utils.overwrittenFunction(Motorized.loadMotor, Motorized.mrLoadMotor)

--20241124 fuel usage is not correct
--example : engine max rpm 2200, engine min rpm 850, current rpm 1500, current load = 100%
--          with Giants engine settings (torque curve), there is no significant difference in power (@1500rpm we got about 96% of the power we got @2200rpm)
--          result = 0.506 => which means : if we are working at 2200rpm (full power) and then at 1500 rpm (full power), we got about the same work rate in the field, but we consume 2 times less fuel @1500 than @2200rpm
--          this is far from being real
--          data from DLG show us (different for each engine/transmission) about 7-9% difference in such case
Motorized.mrUpdateConsumers = function(self, superFunc, dt, accInput)

    local spec = self.spec_motorized

--     local idleFactor = 0.5
--     local rpmPercentage = (spec.motor.lastMotorRpm - spec.motor.minRpm) / (spec.motor.maxRpm - spec.motor.minRpm)
--     local rpmFactor = idleFactor + rpmPercentage * (1-idleFactor)
--     local loadFactor = math.max(spec.smoothedLoadPercentage * rpmPercentage, 0)
--     local motorFactor = 0.5 * ((0.2*rpmFactor) + (1.8*loadFactor) )

    --MR : for some reason, vanilla game xml fuelUsage is about 2 times IRL max fuel usage.
    --motorFactor = 0.5 and then add a factor function of last KW produced and also rpm
    local efficiencyFx = 1 --keep 1 between 0.75 max power rpm and max motor rpm
    if spec.motor.motorRotSpeed<0.75*spec.motor.peakMotorPowerRotSpeed then
        efficiencyFx = 1 + 0.00159*(0.75*spec.motor.peakMotorPowerRotSpeed-spec.motor.motorRotSpeed)--10% more fuel consumption if 600 less rpm
    elseif spec.motor.motorRotSpeed>spec.motor.peakMotorPowerRotSpeed then
        efficiencyFx = 1 + 0.004775*(spec.motor.motorRotSpeed-spec.motor.peakMotorPowerRotSpeed)--15% more fuel consumption if 300 more rpm
    end

    --current power / max power
    local loadFactor = spec.motor.motorAppliedTorque*spec.motor.lastMotorRpm/9.55/spec.motor.peakMotorPower
    local rpmFactor = spec.motor.motorRotSpeed/spec.motor.peakMotorPowerRotSpeed

    local motorFactor = math.min((0.1*rpmFactor+0.9*loadFactor) * efficiencyFx, 1.25) --(1.25 = protection against "funny" value)

    local missionInfo = g_currentMission.missionInfo

    local usageFactor
    if missionInfo.fuelUsage==1 then
        usageFactor=0.5 --2 times less than IRL
    elseif missionInfo.fuelUsage==2 then
        usageFactor = 1 --get IRL usage when "medium" is selected since MR xml = irl fuel usage figures
    else
        usageFactor = 2.5 --2.5 times more than IRL
    end
    if not self.mrIsMrVehicle then
        usageFactor = 0.5 * usageFactor --base game xml = 2 times IRL value, and so, we have to divide by 2 to get something realistic
    end

    local damage = self:getVehicleDamage()
    if damage > 0 then
        usageFactor = usageFactor * (1 + damage * Motorized.DAMAGED_USAGE_INCREASE)
    end

    -- update permanent consumers
    for _,consumer in pairs(spec.consumers) do
        if consumer.permanentConsumption and consumer.usage > 0 then
            local used = usageFactor * motorFactor * consumer.usage * dt

            if consumer.fillType == FillType.DIESEL or consumer.fillType == FillType.ELECTRICCHARGE or consumer.fillType == FillType.METHANE then
                spec.lastFuelUsage = used / dt * 3600000 -- per hour
            elseif consumer.fillType == FillType.DEF then
                spec.lastDefUsage = used / dt * 3600000 -- per hour
            end

            if used ~= 0 then
                consumer.fillLevelToChange = consumer.fillLevelToChange + used
                if math.abs(consumer.fillLevelToChange) > 1 then
                    used = consumer.fillLevelToChange
                    consumer.fillLevelToChange = 0

                    local fillType = self:getFillUnitLastValidFillType(consumer.fillUnitIndex)

                    g_farmManager:updateFarmStats(self:getOwnerFarmId(), "fuelUsage", used)

                    if self:getIsAIActive() then
                        if fillType == FillType.DIESEL or fillType == FillType.DEF then
                            if missionInfo.helperBuyFuel then
                                if fillType == FillType.DIESEL then
                                    local price = used * g_currentMission.economyManager:getCostPerLiter(fillType) * 1.5
                                    g_farmManager:updateFarmStats(self:getOwnerFarmId(), "expenses", price)

                                    g_currentMission:addMoney(-price, self:getOwnerFarmId(), MoneyType.PURCHASE_FUEL, true)
                                end

                                used = 0
                            end
                        end
                    end

                    if fillType == consumer.fillType then
                        self:addFillUnitFillLevel(self:getOwnerFarmId(), consumer.fillUnitIndex, -used, fillType, ToolType.UNDEFINED)
                    end
                end

            end
        end
    end

    -- update air consuming
    if spec.consumersByFillTypeName["AIR"] ~= nil then
        local consumer = spec.consumersByFillTypeName["AIR"]
        local fillType = self:getFillUnitLastValidFillType(consumer.fillUnitIndex)
        if fillType == consumer.fillType then
            local usage = 0

            -- consume air on brake
            --MR : do not rely on moving direction
--             local direction = self.movingDirection * self:getReverserDirection()
--             local forwardBrake = direction > 0 and accInput < 0
--             local backwardBrake = direction < 0 and accInput > 0
--             local brakeIsPressed = self:getLastSpeed() > 1.0 and (forwardBrake or backwardBrake)
            local brakeIsPressed = self.spec_wheels and self.spec_wheels.brakePedal>0 or false
            --END MR
            if brakeIsPressed and self.movingDirection~=0 then
                local delta = math.abs(accInput) * dt * self:getAirConsumerUsage() / 1000
                self:addFillUnitFillLevel(self:getOwnerFarmId(), consumer.fillUnitIndex, -delta, consumer.fillType, ToolType.UNDEFINED)

                usage = delta / dt * 1000 -- per sec
            end

            --refill air fill unit if it is below given level
            local fillLevelPercentage = self:getFillUnitFillLevelPercentage(consumer.fillUnitIndex)
            if fillLevelPercentage < consumer.refillCapacityPercentage then
                consumer.doRefill = true
            elseif fillLevelPercentage == 1 then
                consumer.doRefill = false
            end

            if consumer.doRefill then
                local delta = consumer.refillLitersPerSecond / 1000 * dt
                self:addFillUnitFillLevel(self:getOwnerFarmId(), consumer.fillUnitIndex, delta, consumer.fillType, ToolType.UNDEFINED)

                usage = -delta / dt * 1000 -- per sec
            end

            spec.lastAirUsage = usage
        end
    end

end
Motorized.updateConsumers = Utils.overwrittenFunction(Motorized.updateConsumers, Motorized.mrUpdateConsumers)


Motorized.mrControlVehicle = function(self, superFunc, acceleratorPedal, maxSpeed, maxAcceleration, minMotorRotSpeed, maxMotorRotSpeed, maxMotorRotAcceleration, minGearRatio, maxGearRatio, maxClutchTorque, neededPtoTorque)

    if getIsSleeping(self.spec_motorized.motorizedNode) then
        --awake if player inside vehicle and rpm <> minRpm
        --if math.abs(self.spec_motorized.motor.differentialRotSpeed)>0.03 or self.spec_motorized.motor.lastRealMotorRpm>(self.spec_motorized.motor.minRpm+1) then --0.108kph
        if math.abs(self.spec_motorized.motor.differentialRotSpeed)>0.03 or self.spec_motorized.motor.mrLastMotorObjectRotSpeed>(1+self.spec_motorized.motor.minRpm*math.pi/30) then --0.108kph
            local isEntered = self.getIsEntered ~= nil and self:getIsEntered()
            local isControlled = self.getIsControlled ~= nil and self:getIsControlled()
            if isEntered or isControlled then
                I3DUtil.wakeUpObject(self.spec_motorized.motorizedNode)
            end
        end
    end

    if self.spec_motorized.mrLastMinGearRatioSet~=minGearRatio then
        self.spec_motorized.motor.mrLastGearRatioChangeTime = g_time
    end

    self.spec_motorized.mrLastMinGearRatioSet = minGearRatio
    self.spec_motorized.mrLastMaxGearRatioSet = maxGearRatio

    superFunc(self, acceleratorPedal, maxSpeed, maxAcceleration, minMotorRotSpeed, maxMotorRotSpeed, maxMotorRotAcceleration, minGearRatio, maxGearRatio, maxClutchTorque, neededPtoTorque)

end
Motorized.controlVehicle = Utils.overwrittenFunction(Motorized.controlVehicle, Motorized.mrControlVehicle)


Motorized.mrUpdateMotorProperties=function(self)

    local spec = self.spec_motorized
    local motor = spec.motor
    local torques, rotationSpeeds = motor:getTorqueAndSpeedValues()

    -- zero throttle = idle torque to run the engine
    --example : 850rpm idle and 0.001 damping value => 0.09Kn "consumed"
    --example : 1000rpm idle and 0.001 damping value => 0.10Kn "consumed"
    --example : 2000rpm idle and 0.001 damping value => 0.21Kn "consumed"
    --=> consumed torque = rpm * damping value /10

    --default value without scaling =
    --VehicleMotor.DEFAULT_DAMPING_RATE_FULL_THROTTLE = 0.000250
    --VehicleMotor.DEFAULT_DAMPING_RATE_ZERO_THROTTLE_CLUTCH_EN = 0.0015
    --VehicleMotor.DEFAULT_DAMPING_RATE_ZERO_THROTTLE_CLUTCH_DIS = 0.0015
    --
    --DEFAULT_DAMPING_RATE_ZERO_THROTTLE_CLUTCH_DIS => influence idle fuel consumption and sound => fixed value
    --DEFAULT_DAMPING_RATE_ZERO_THROTTLE_CLUTCH_EN => influence engine braking power => should vary according to current rpm ?

    --damping is consuming power, and so, we only want to set the right value when "decelerating" to simulate engine braking power
    local fx = 0.24
    if spec.mrEngineIsBraking then
        fx = 10*fx
    end

    local dampingRateZeroThrottleClutchDisengaged = fx*motor.peakMotorTorque/1000
    local dampingRateZeroThrottleClutchEngaged = dampingRateZeroThrottleClutchDisengaged--clutch engaged means "disengaged" = no link between engine and transmission
    local dampingRateFullThrottle = 0.000001 -- simplified formula => KW "lost" with damping = damping value * rpm^2 / 95.5

    --MR : limit engine power according to "self.mrTransmissionPowerRatio"
    if self.mrIsMrVehicle and self.mrTransmissionPowerRatio<1 and self.mrLastTurnedOnState==false then
        for i=1, #torques do
            torques[i] = self.mrTransmissionPowerRatio*torques[i]
        end
    end

    setMotorProperties(spec.motorizedNode, motor.mrMinRot-10, motor.mrMaxRot, motor:getRotInertia(), dampingRateFullThrottle, dampingRateZeroThrottleClutchEngaged, dampingRateZeroThrottleClutchDisengaged, rotationSpeeds, torques)

 end
Motorized.updateMotorProperties = Utils.overwrittenFunction(Motorized.updateMotorProperties, Motorized.mrUpdateMotorProperties)


Motorized.mrUpdateWheelsDriven = function(self)

    if self.isServer and self.spec_wheels ~= nil and #self.spec_wheels.wheels ~= 0 then

        --reset all mrDriven value to 0
        self.spec_wheels.mrNbDrivenWheels = 0
        for _, wheel in pairs(self.spec_wheels.wheels) do
            wheel.physics.mrIsDriven = false
        end

        --parse all differentials to get driven wheels
        if next(self.spec_motorized.differentials) ~= nil then
            for _, diff in pairs(self.spec_motorized.differentials) do
                if diff.diffIndex1IsWheel then
                    self.spec_wheels.wheels[diff.diffIndex1].physics.mrIsDriven = true
                end
                if diff.diffIndex2IsWheel then
                    self.spec_wheels.wheels[diff.diffIndex2].physics.mrIsDriven = true
                end
            end
        end

        --count driven wheels
        for _, wheel in pairs(self.spec_wheels.wheels) do
            if wheel.physics.mrIsDriven then
                self.spec_wheels.mrNbDrivenWheels = self.spec_wheels.mrNbDrivenWheels + 1
            end
        end

    end

end




Motorized.mrLoadDifferentials = function(self, superFunc, xmlFile, configDifferentialIndex)
    superFunc(self, xmlFile, configDifferentialIndex)
    Motorized.mrUpdateWheelsDriven(self)
end
Motorized.loadDifferentials = Utils.overwrittenFunction(Motorized.loadDifferentials, Motorized.mrLoadDifferentials)



---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
--MR : better engine sound ?
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
Motorized.mrOnUpdate = function(self, superFunc, dt, isActiveForInput, isActiveForInputIgnoreSelection, isSelected)

    superFunc(self, dt, isActiveForInput, isActiveForInputIgnoreSelection, isSelected)

    local motorState = self:getMotorState()
    local spec = self.spec_motorized

    if self.isClient then
        if motorState == MotorState.STARTING or motorState == MotorState.ON then
            -- update sounds
            local rpm, minRpm, maxRpm = spec.motor:getLastModulatedMotorRpm(), spec.motor.minRpm, spec.motor.maxRpm
            local rpmPercentage = math.clamp((rpm - minRpm) / (maxRpm - minRpm), 0, 1)

            --MR apply min load percentage function of rpm
            local minLoadPercentage = -1
            if rpm>maxRpm then
                minLoadPercentage = 0.5*rpm/maxRpm
            elseif rpm>minRpm then
                minLoadPercentage = -1 + 1.5*(rpm-minRpm)/(maxRpm-minRpm)
            end

            --20250723 - limit loadPercentage when fuel governor is limiting the power
            local loadPercentage = spec.smoothedLoadPercentage
            loadPercentage = math.max(loadPercentage, minLoadPercentage)

            --if the rpmPercentage is proportionnal to actual rpm = weird : if the sounds is right at 2200rpm, when the engine drop to 1500rpm, it sounds like it is under 1000rpm
            rpmPercentage = rpmPercentage^0.25

            g_soundManager:setSamplesLoopSynthesisParameters(spec.motorSamples, rpmPercentage, loadPercentage)
        end
    end

    if self.isServer and spec.motorizedNode~=nil then

        --case : auto start motor disabled and a woodcrusher is working without driver
        if motorState == MotorState.ON and not self:getIsAIActive() and self.getIsControlled ~= nil and not self:getIsControlled() then
            local neededPtoTorque, _ = PowerConsumer.getTotalConsumedPtoTorque(self)
            if neededPtoTorque>0 then
                neededPtoTorque = neededPtoTorque / spec.motor:getPtoMotorRpmRatio()
                local minRotForPTO, _ = spec.motor:getRequiredMotorRpmRange()
                minRotForPTO = minRotForPTO * math.pi/30
                if not self.mrForcePtoRpm then
                    minRotForPTO = 0.8*minRotForPTO
                end
                self.mrForcePtoRpm = false
                minRotForPTO = math.max(spec.motor.mrMinRot, 125, minRotForPTO) --125 = 1200rpm
                self:controlVehicle(0, 0, 0, minRotForPTO, math.huge, 0.0, 0.0, 0.0, 0.0, neededPtoTorque)
            end
        end


        --update motorizedNode get values
        spec.motor.mrLastMotorObjectRotSpeed, _, spec.motor.mrLastMotorObjectGearRatio = getMotorRotationSpeed(spec.motorizedNode)

        if spec.motor.mrLastMotorObjectRotSpeed<(spec.motor.mrMinRot+0.5)
        or (spec.motor.lastMotorExternalTorque>0 and self.lastSpeedReal*3600<0.2) then --not good when in neutral => we don't want engine braking if "real" engine rpm is at idle
            spec.mrEngineIsBraking = false
        end

        local needUpdate = spec.mrLastEngineIsBraking~=spec.mrEngineIsBraking or spec.motor.mrIsChangingDirection
        if self.mrTransmissionPowerRatio<1 then
            local turnedOn = self.getIsTurnedOn ~= nil and self:getIsTurnedOn()
            if turnedOn~=self.mrLastTurnedOnState then
                needUpdate = true
                self.mrLastTurnedOnState = turnedOn
            end
        end
        if needUpdate then
            spec.mrLastEngineIsBraking = spec.mrEngineIsBraking
            self:updateMotorProperties()
            I3DUtil.wakeUpObject(spec.motorizedNode)
        end
    end

end
Motorized.onUpdate = Utils.overwrittenFunction(Motorized.onUpdate, Motorized.mrOnUpdate)

-- see Dashboard.mrRegisterDashboardValueType
Motorized.mrGetDashboardSpeedDir = function(self)
    --Example : starting massey ferguson 8570 combine : we don't want the hydrostatic lever to go from full forward to full reverse when changing direction (manual change direction enabled)
    if self.spec_drivable and self.spec_drivable.idleTurningAllowed and self.spec_drivable.idleTurningActive then
        return 0
    else
        if math.abs(self.lastSignedSpeed)<0.00005 then --avoid jiggles at very low speed while "not" moving (0.00005 = 0.18kph)
            return 0
        else
            return self.lastSignedSpeed*3600 --differentialRotSpeed ?
        end
    end
end


--getMotorLoadPercentage = used by sound manager for modifier type = "MOTOR_LOAD"
--getMotorRpmPercentage = used by sound manager for modifier type = "MOTOR_RPM"
--vehicle:getGearInfoToDisplay => call motorized:getGearInfoToDisplay => call motor:getGearInfoToDisplay

