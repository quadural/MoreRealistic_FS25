VehicleMotor.mrNew = function (vehicle, superFunc, minRpm, maxRpm, maxForwardSpeed, maxBackwardSpeed, torqueCurve, brakeForce, forwardGears, backwardGears, minForwardGearRatio, maxForwardGearRatio, minBackwardGearRatio, maxBackwardGearRatio, ptoMotorRpmRatio, minSpeed)

    --MR : add governor range to the engine torque curve

    --fix HF16 problem (maxRpm different than last torque curve rpm)
    local lastTime = torqueCurve.keyframes[#torqueCurve.keyframes].time
    local lastTorque = torqueCurve:get(lastTime)

    --20250428 -- add check for small engines : ex=Piaggio Ape50
    local firstTorque = torqueCurve:get(torqueCurve.keyframes[1].time)
    local minTorque = 0.05*firstTorque

    --20250723 -- only for mr vehicles
    if vehicle.mrIsMrVehicle then
        if lastTorque>minTorque then
            maxRpm = lastTime+vehicle.mrGovernorRange
            --20250610 - add another point just before the last one
            torqueCurve:addKeyframe({0.8*lastTorque, time = lastTime+0.4*vehicle.mrGovernorRange})
            torqueCurve:addKeyframe({minTorque, time = maxRpm})
        end
    else
        --small governor range
        if lastTorque>minTorque then
            maxRpm = lastTime+100
            torqueCurve:addKeyframe({lastTorque*0.5, time = maxRpm})
        end
    end

    local newMotor = superFunc(vehicle, minRpm, maxRpm, maxForwardSpeed, maxBackwardSpeed, torqueCurve, brakeForce, forwardGears, backwardGears, minForwardGearRatio, maxForwardGearRatio, minBackwardGearRatio, maxBackwardGearRatio, ptoMotorRpmRatio, minSpeed)


    newMotor.mrLastMinMotorRot = 0
    newMotor.mrLastMotorObjectRotSpeed = 0
    newMotor.mrLastMotorObjectGearRatio = 0
    newMotor.mrIsChangingDirection = false
    newMotor.mrLastDirection = newMotor.currentDirection
    newMotor.mrMinRot = newMotor.minRpm * math.pi / 30
    newMotor.mrMaxRot = newMotor.maxRpm * math.pi / 30
    newMotor.lowBrakeForceLocked = true
    newMotor.mrClutchingMaxRot = (newMotor.mrMinRot+newMotor.mrMaxRot)/2.6

    --filling powerBand rpm limits (at least 94% max power)
    newMotor.mrPowerBandMaxRpm = 0
    newMotor.mrPowerBandMinRpm = 0
    newMotor.mrPeakPowerRpm = newMotor.peakMotorPowerRotSpeed*30/math.pi

    local rpm = minRpm
    while rpm<maxRpm do
        local power = torqueCurve:get(rpm)*rpm*math.pi/30
        if newMotor.mrPowerBandMinRpm==0 and power>=0.94*newMotor.peakMotorPower then
            newMotor.mrPowerBandMinRpm = rpm
        elseif newMotor.mrPowerBandMinRpm~=0 and power<0.94*newMotor.peakMotorPower then
            newMotor.mrPowerBandMaxRpm = rpm-25
            break
        end
        rpm = rpm + 25
    end

    --20250607 - if powerband is too narrow => check with 90%
    if (newMotor.mrPowerBandMaxRpm-newMotor.mrPowerBandMinRpm)<250 then
        newMotor.mrPowerBandMaxRpm = 0
        newMotor.mrPowerBandMinRpm = 0
        rpm = minRpm
        while rpm<maxRpm do
            local power = torqueCurve:get(rpm)*rpm*math.pi/30
            if newMotor.mrPowerBandMinRpm==0 and power>=0.9*newMotor.peakMotorPower then
                newMotor.mrPowerBandMinRpm = rpm
            elseif newMotor.mrPowerBandMinRpm~=0 and power<0.9*newMotor.peakMotorPower then
                newMotor.mrPowerBandMaxRpm = rpm-25
                break
            end
            rpm = rpm + 25
        end
    end



    newMotor.mrBestStartGearSelected = 0
    newMotor.mrTransmissionLastShiftGlobalRatio = 0
    newMotor.mrTransmissionLastShiftDirection = 0
    newMotor.mrTransmissionLastShiftDirectionTimer = 0
    newMotor.mrTransmissionLastShiftDirectionTime = 1500 --try new gear/group combo for at least 1.5s before shifting in the opposite direction (up or down)

    newMotor.mrTransmissionZeroAccShiftingTimer = 0
    newMotor.mrTransmissionZeroAccShiftingTime = 300 -- allow less brutal down shifting while "engine braking"

    newMotor.mrPreventAutoGearShiftTimer = 0
    newMotor.mrPreventAutoGearShiftTime = 2000

    newMotor.mrTransmissionLugTime = 0
    newMotor.mrTransmissionLugMaxTime = 600

    newMotor.mrClutchSlippingTime = 4000 --max clutch slipping time

    newMotor.mrManualGearShifterActivated = false
    newMotor.mrManualGroupShifterActivated = false

    if vehicle.mrIsMrCombine then
        if vehicle.mrCombineSpotRate==0 then
            vehicle.mrCombineSpotRate = newMotor.peakMotorPower / 6
        end
    end

    return newMotor

end
VehicleMotor.new = Utils.overwrittenFunction(VehicleMotor.new, VehicleMotor.mrNew)


---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
--problem1 = when driving in manual mode for the transmission, the game is "unplayable" with the starting Challenger MT655. First reverse gear is very slow, and everytime you reverse, you have to shift up 6-7 times to get a normal reverse speed
--problem2 = when playing with manual clutch : we can use the key/button to change direction without using the clutch => not wanted
--problem3 = when driving in manual mode for the transmission, when the game load, the selected gear = neutral and the currentDirection = 1 => if we press the change direction button, the game select the reverse direction first
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
VehicleMotor.mrChangeDirection = function(self, superFunc, direction, force)

    local targetDirection
    if direction == nil then
        if self.gear == 0 and self.targetGear == 0 and (self.backwardGears ~= nil or self.forwardGears ~= nil) then --fix for problem3
            force = true
            targetDirection = 1
        else
            targetDirection = -self.currentDirection
        end
    else
        targetDirection = direction
    end

    if self.backwardGears == nil and self.forwardGears == nil then
        self.currentDirection = targetDirection
        SpecializationUtil.raiseEvent(self.vehicle, "onGearDirectionChanged", self.currentDirection)
        return
    end

    local changeAllowed = (self.directionChangeUseGroup and not self.gearGroupChangedIsLocked)
                       or (self.directionChangeUseGear and not self.gearChangedIsLocked)
                       or (not self.directionChangeUseGear and not self.directionChangeUseGroup)
    if changeAllowed then
        if targetDirection ~= self.currentDirection or force then

            if self.gear~=nil and self.gear~=0 then
                if self.mrDirectionKeepCurrentGear then
                    --MR : keep the same gear when changing direction
                    self.directionChangeGearIndex = self.gear
                    self.directionLastGear = self.gear
                elseif self.currentDirection < 0 then
                    --MR : keep the last selected reverse gear
                    self.directionChangeGearIndex = self.gear
                end
            end

            --MR : check if really allowed
            if self.directionChangeTime>0 then --0 = power shuttle (no clutch needed)
                if self.directionChangeUseGroup and not self:getIsGearGroupChangeAllowed() then
                    SpecializationUtil.raiseEvent(self.vehicle, "onClutchCreaking", true, true)
                    return
                elseif self.directionChangeUseGear and not self:getIsGearChangeAllowed() then
                    SpecializationUtil.raiseEvent(self.vehicle, "onClutchCreaking", true, false)
                    return
                end
            end

            self.currentDirection = targetDirection

            if self.directionChangeTime > 0 then
                self.directionChangeTimer = self.directionChangeTime
                self.gear = 0
                self.minGearRatio = 0
                self.maxGearRatio = 0
            end

            local oldGearGroupIndex = self.activeGearGroupIndex
            if self.currentDirection < 0 then
                if self.directionChangeUseGear then
                    self.directionLastGear = self.targetGear
                    if not self:getUseAutomaticGearShifting() or not self.lastManualGearShifterActive then
                        self.targetGear = self.directionChangeGearIndex
                    end

                    self.currentGears = self.backwardGears or self.forwardGears
                elseif self.directionChangeUseGroup then
                    self.directionLastGroup = self.activeGearGroupIndex
                    self.activeGearGroupIndex = self.directionChangeGroupIndex
                end
            else
                if self.directionChangeUseGear then
                    if not self:getUseAutomaticGearShifting() or not self.lastManualGearShifterActive then
                        if self.directionLastGear > 0 then
                            self.targetGear = not self:getUseAutomaticGearShifting() and self.directionLastGear or self.defaultForwardGear
                        else
                            self.targetGear = self.defaultForwardGear
                        end
                    end

                    self.currentGears = self.forwardGears
                elseif self.directionChangeUseGroup then
                    if self.directionLastGroup > 0 then
                        self.activeGearGroupIndex = self.directionLastGroup
                    else
                        self.activeGearGroupIndex = self.defaultGearGroup
                    end
                end
            end

            SpecializationUtil.raiseEvent(self.vehicle, "onGearDirectionChanged", self.currentDirection)

            local directionMultiplier = self.directionChangeUseGear and self.currentDirection or 1
            SpecializationUtil.raiseEvent(self.vehicle, "onGearChanged", self.gear * directionMultiplier, self.targetGear * directionMultiplier, self.directionChangeTime, self.previousGear)

            if self.activeGearGroupIndex ~= oldGearGroupIndex then
                SpecializationUtil.raiseEvent(self.vehicle, "onGearGroupChanged", self.activeGearGroupIndex, self.directionChangeTime)
            end

            if self.directionChangeTime == 0 then
                self:applyTargetGear()
            end
        end
    end


end
VehicleMotor.changeDirection = Utils.overwrittenFunction(VehicleMotor.changeDirection, VehicleMotor.mrChangeDirection)


---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
--problem = when driving in manual mode for the transmission, when driving in reverse, if we "shift up", the game decrease the speed (shift a gear down).
--This is not natural and not convenient, especially when driving a tractor with a powershuttle
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
VehicleMotor.mrShiftGear = function(self, superFunc, up)
    if not self.gearChangedIsLocked then
        if self:getIsGearChangeAllowed() then
            local newGear
            if self.targetGear==0 then --in neutral
                newGear = 1
                if up then
                    self:changeDirection(1)
                else
                    self:changeDirection(-1)
                end
            else
                if up then
                    newGear = self.targetGear + 1
                    if self.currentDirection > 0 or self.backwardGears == nil then
                        if newGear > #self.forwardGears then
                            newGear = #self.forwardGears
                        end
                    elseif self.currentDirection < 0 or self.backwardGears ~= nil then
                        if newGear > #self.backwardGears then
                            newGear = #self.backwardGears
                        end
                    end
                else
                    newGear = self.targetGear - 1
                end
            end

            if newGear ~= self.targetGear then
                self:setGear(newGear)
                self.lastManualShifterActive = false
                self.mrManualGearShifterActivated = true
            end
        else
            SpecializationUtil.raiseEvent(self.vehicle, "onClutchCreaking", true, false)
        end
    end
end
VehicleMotor.shiftGear = Utils.overwrittenFunction(VehicleMotor.shiftGear, VehicleMotor.mrShiftGear)


VehicleMotor.mrGetMinMaxGearRatio = function(self, superFunc)
    local minRatio = self.minGearRatio
    local maxRatio = self.maxGearRatio
    return minRatio, maxRatio
end
VehicleMotor.getMinMaxGearRatio = Utils.overwrittenFunction(VehicleMotor.getMinMaxGearRatio, VehicleMotor.mrGetMinMaxGearRatio)






---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
--few adjustment for sound, remove useless code with MR, fix small visual bug
--motor engine sound rpm = look at the call to "setLastRpm" function below
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
VehicleMotor.mrUpdate = function(self, superFunc, dt)
    local vehicle = self.vehicle
    if next(vehicle.spec_motorized.differentials) ~= nil and vehicle.spec_motorized.motorizedNode ~= nil then
        local lastMotorRotSpeed = self.motorRotSpeed
        local lastDiffRotSpeed = self.differentialRotSpeed
        self.motorRotSpeed, self.differentialRotSpeed, self.gearRatio = getMotorRotationSpeed(vehicle.spec_motorized.motorizedNode)

        --MR
        if self.gearShiftMode ~= VehicleMotor.SHIFT_MODE_MANUAL_CLUTCH and not self.mrTransmissionIsHydrostatic then
            -- dynamically adjust the max gear ratio while starting in a gear and have not reached the min. differential speed
            -- this simulates clutch slipping and allows a smooth acceleration
            if (self.backwardGears or self.forwardGears) and self.gearRatio ~= 0 and self.maxGearRatio ~= 0 then
                if self.lastAcceleratorPedal ~= 0 then
                    local slippingWantedRot = MathUtil.lerp(self.mrMinRot, self.mrClutchingMaxRot, math.abs(self.lastAcceleratorPedal))
                    local minDifferentialSpeed = slippingWantedRot / math.abs(self.maxGearRatio) * math.pi / 30
                    if math.abs(self.differentialRotSpeed) < minDifferentialSpeed * 0.75 then
                        self.clutchSlippingTimer = self.mrClutchSlippingTime
                        self.clutchSlippingGearRatio = self.gearRatio
                    else
                        self.clutchSlippingTimer = math.max(self.clutchSlippingTimer - dt, 0)
                    end
                else
                    self.clutchSlippingTimer = 0
                end
            end
        end

        --[[
        if not self:getUseAutomaticGearShifting() then
            local accelerationPedal = self.lastAcceleratorPedal * self.currentDirection

            -- calculate additional rpm if clutch is engaged and user is pressing the accelerator pedal
            local clutchValue = 0
            if (self.minGearRatio == 0 and self.maxGearRatio == 0) or self.manualClutchValue > 0.1 then
                clutchValue = 1
            end
            local direction = clutchValue * accelerationPedal
            if direction == 0 then
                direction = -1
            end

            --MR local accelerationSpeed = direction > 0 and (self.motorRotationAccelerationLimit * 0.02) or self.dampingRateZeroThrottleClutchEngaged * 30 * math.pi
            local accelerationSpeed = direction > 0 and (self.motorRotationAccelerationLimit * 0.002) or self.dampingRateZeroThrottleClutchEngaged * 30 * math.pi
            local minRotSpeed = self.minRpm * math.pi / 30
            local maxRotSpeed = self.maxRpm * math.pi / 30
            self.motorRotSpeedClutchEngaged = math.min(math.max(self.motorRotSpeedClutchEngaged + direction * accelerationSpeed * dt, minRotSpeed), minRotSpeed + (maxRotSpeed - minRotSpeed) * accelerationPedal)
            self.motorRotSpeed = math.max(self.motorRotSpeed, self.motorRotSpeedClutchEngaged)
        end
        --]]

        if g_physicsDtNonInterpolated > 0.0 and not getIsSleeping(vehicle.rootNode) then
            self.lastMotorAvailableTorque, self.lastMotorAppliedTorque, self.lastMotorExternalTorque = getMotorTorque(vehicle.spec_motorized.motorizedNode)
        end

        self.motorAvailableTorque, self.motorAppliedTorque, self.motorExternalTorque = self.lastMotorAvailableTorque, self.lastMotorAppliedTorque, self.lastMotorExternalTorque

        -- apply virtual pto torque factor
        self.motorAppliedTorque = self.motorAppliedTorque - self.motorExternalTorque
        self.motorExternalTorque = math.min(self.motorExternalTorque * self.externalTorqueVirtualMultiplicator, self.motorAvailableTorque - self.motorAppliedTorque)
        self.motorAppliedTorque = self.motorAppliedTorque + self.motorExternalTorque

        local motorRotAcceleration, differentialRotAcceleration = 0, 0
        if g_physicsDtNonInterpolated > 0 then
            motorRotAcceleration = (self.motorRotSpeed - lastMotorRotSpeed) / (g_physicsDtNonInterpolated * 0.001)
            differentialRotAcceleration = (self.differentialRotSpeed - lastDiffRotSpeed) / (g_physicsDtNonInterpolated * 0.001)
        end

        self.motorRotAcceleration = motorRotAcceleration
        self.motorRotAccelerationSmoothed = 0.8 * self.motorRotAccelerationSmoothed + 0.2 * motorRotAcceleration

        self.differentialRotAcceleration = differentialRotAcceleration
        self.differentialRotAccelerationSmoothed = 0.95 * self.differentialRotAccelerationSmoothed + 0.05 * differentialRotAcceleration

        self.requiredMotorPower = math.huge
    else
        local _, gearRatio = self:getMinMaxGearRatio()
        self.differentialRotSpeed = WheelsUtil.computeDifferentialRotSpeedNonMotor(vehicle)
        self.motorRotSpeed = math.max(math.abs(self.differentialRotSpeed * gearRatio), 0)
        self.gearRatio = gearRatio
    end

    -- the clamped motor rpm always is higher-equal than the required rpm by the pto
    --local ptoRpm = math.min(PowerConsumer.getMaxPtoRpm(self.vehicle)*self.ptoMotorRpmRatio, self.maxRpm)
    -- smoothing for raise/fall of ptoRpm
    if self.lastPtoRpm == nil then
        self.lastPtoRpm = self.minRpm
    end
    local ptoRpm = PowerConsumer.getMaxPtoRpm(self.vehicle)*self.ptoMotorRpmRatio
    if ptoRpm > self.lastPtoRpm then
        self.lastPtoRpm = math.min(ptoRpm, self.lastPtoRpm + self.maxRpm*dt/2000)
    elseif ptoRpm < self.lastPtoRpm then
        self.lastPtoRpm = math.max(self.minRpm, self.lastPtoRpm - self.maxRpm*dt/1000)
    end

    -- client will recieve this value from the server
    if self.vehicle.isServer then
        --MR local clampedMotorRpm = math.max(self.motorRotSpeed*30/math.pi, math.min(self.lastPtoRpm, self.maxRpm), self.minRpm)
        local clampedMotorRpm = self:getNonClampedMotorRpm() --we don't want a "clamped motor rpm" (this is not realistic)
        self:setLastRpm(clampedMotorRpm)

        self.equalizedMotorRpm = clampedMotorRpm

        local rawLoadPercentage = self:getMotorAppliedTorque() / math.max(self:getMotorAvailableTorque(), 0.0001)
        self.rawLoadPercentageBuffer = self.rawLoadPercentageBuffer + rawLoadPercentage
        self.rawLoadPercentageBufferIndex = self.rawLoadPercentageBufferIndex + 1
        if self.rawLoadPercentageBufferIndex >= 2 then
            self.rawLoadPercentage = self.rawLoadPercentageBuffer / 2
            self.rawLoadPercentageBuffer = 0
            self.rawLoadPercentageBufferIndex = 0
        end

        if self.rawLoadPercentage < 0.01 and self.lastAcceleratorPedal < 0.2
        and not ((self.backwardGears or self.forwardGears) and self.gear == 0 and self.targetGear ~= 0) then
            -- while rolling but not currently changing gears
            self.rawLoadPercentage = -1
        else
            -- normal driving load is at 0 while motor is at idle load to keep it running and at 1 while it's at max load
            local idleLoadPct = 0.05 -- TODO change to real idle percentage
            self.rawLoadPercentage = (self.rawLoadPercentage - idleLoadPct) / (1 - idleLoadPct)
        end

        local accelerationPercentage = math.min((self.vehicle.lastSpeedAcceleration * 1000 * 1000 * self.vehicle.movingDirection) / self.accelerationLimit, 1)
        if accelerationPercentage < 0.95 and self.lastAcceleratorPedal > 0.2 then
            self.accelerationLimitLoadScale = 1
            self.accelerationLimitLoadScaleTimer = self.accelerationLimitLoadScaleDelay
        else
            if self.accelerationLimitLoadScaleTimer > 0 then
                self.accelerationLimitLoadScaleTimer = self.accelerationLimitLoadScaleTimer - dt

                local alpha = math.max(self.accelerationLimitLoadScaleTimer / self.accelerationLimitLoadScaleDelay, 0)
                self.accelerationLimitLoadScale = math.sin((1 - alpha) * 3.14) * 0.85
            end
        end

        if accelerationPercentage > 0 then
            self.rawLoadPercentage = math.max(self.rawLoadPercentage, accelerationPercentage * self.accelerationLimitLoadScale)
        end

        -- while we are not accelerating the constantAccelerationCharge is at 1, so the max. raw load from the engine is used. If we are accelerating we use only 80% of the load
        --MR : not realistic ? when accelerating, we can also load the engien to 100%
--         self.constantAccelerationCharge = 1 - math.min((math.abs(self.vehicle.lastSpeedAcceleration) * 1000 * 1000) / self.accelerationLimit, 1)
--         if self.rawLoadPercentage > 0 then
--             self.rawLoadPercentage = self.rawLoadPercentage * MAX_ACCELERATION_LOAD + self.rawLoadPercentage * (1 - MAX_ACCELERATION_LOAD) * self.constantAccelerationCharge
--         end

        --this is not MR at all
--         if self.backwardGears or self.forwardGears then
--             if self:getUseAutomaticGearShifting() then
--                 -- if we are in automatic mode and we are stuck in one gear for a while we try to reduce the shifting time
--                 -- like this are are not loosing too much speed while shifting and more gears are an option
--                 -- especially helpfull if we picked the wrong gear in field work
--                 if self.constantRpmCharge > 0.99 then
--                     if self.maxRpm - clampedMotorRpm < 50 then
--                         self.gearChangeTimeAutoReductionTimer = math.min(self.gearChangeTimeAutoReductionTimer  + dt, self.gearChangeTimeAutoReductionTime)
--                         self.gearChangeTime = self.gearChangeTimeOrig * (1 - self.gearChangeTimeAutoReductionTimer / self.gearChangeTimeAutoReductionTime)
--                     else
--                         self.gearChangeTimeAutoReductionTimer = 0
--                         self.gearChangeTime = self.gearChangeTimeOrig
--                     end
--                 else
--                     self.gearChangeTimeAutoReductionTimer = 0
--                     self.gearChangeTime = self.gearChangeTimeOrig
--                 end
--             end
--         end
    end

    self:updateSmoothLoadPercentage(dt, self.rawLoadPercentage)

    self.idleGearChangeTimer = math.max(self.idleGearChangeTimer - dt, 0)

    if self.forwardGears or self.backwardGears then
        self:updateStartGearValues(dt)

        local clutchPedal = self:getClutchPedal()
        self.lastSmoothedClutchPedal = self.lastSmoothedClutchPedal * 0.9 + clutchPedal * 0.1
    end

    self.lastModulationTimer = self.lastModulationTimer + dt * -0.0009 --MODULATION_SPEED
    self.lastModulationPercentage = math.sin(self.lastModulationTimer) * math.sin((self.lastModulationTimer + 2) * 0.3) * 0.8 + math.cos(self.lastModulationTimer * 5) * 0.2

    --MR fix visual bug = left foot keeps going from pedal clutch to idle
    if self.lastSmoothedClutchPedal<0.01 then
        self.lastSmoothedClutchPedal = 0
    end

end
VehicleMotor.update = Utils.overwrittenFunction(VehicleMotor.update, VehicleMotor.mrUpdate)

---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
--we don't want the engine rpm to fluctuate for nothing. This doesn't feel realistic and it is not needed with MR engine
--getLastModulatedMotorRpm is the function called to display rpm needle in cab
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
VehicleMotor.mrGetLastModulatedMotorRpm = function(self, superFunc)
    --superFunc(self)
    return self.lastMotorRpm
end
VehicleMotor.getLastModulatedMotorRpm = Utils.overwrittenFunction(VehicleMotor.getLastModulatedMotorRpm, VehicleMotor.mrGetLastModulatedMotorRpm)

---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- manage "mrTransmissionIsHydrostatic" => we want to see D or R when vehicle is at still and directionChangeMode==DIRECTION_CHANGE_MODE_MANUAL
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
VehicleMotor.mrGetDrivingDirection = function(self, superFunc)

    --if self.vehicle.mrIsMrVehicle and self.vehicle.mrTransmissionIsHydrostatic then
    --for all "gearless transmission ?
    if self.minGearRatio~=self.maxGearRatio then
        if self.vehicle:getLastSpeed() > 0.3 then
            return self.vehicle.movingDirection * self.transmissionDirection
        elseif self.directionChangeMode == VehicleMotor.DIRECTION_CHANGE_MODE_MANUAL then
            return self.currentDirection * self.transmissionDirection
        end
        return 0
    end

    return superFunc(self)

end
VehicleMotor.getDrivingDirection = Utils.overwrittenFunction(VehicleMotor.getDrivingDirection, VehicleMotor.mrGetDrivingDirection)



---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Manage CombineSpeedLimit function of material rate
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
VehicleMotor.mrGetSpeedLimit = function(self, superFunc)
    local spdLimit = superFunc(self)
    if self.vehicle.mrIsMrCombine then
        spdLimit = math.min(spdLimit, self.vehicle.mrCombineSpeedLimit)
    end
    return spdLimit
end
VehicleMotor.getSpeedLimit = Utils.overwrittenFunction(VehicleMotor.getSpeedLimit, VehicleMotor.mrGetSpeedLimit)


---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- VehicleMotor:getStartInGearFactor => can be called a lot of time = it needs to be very "fast" computing wise
--we don't take into account the slope factor or pull factor or implement draftforce
--we only care about available power and mass on driven wheels
--for starting gear, we want the "smaller" (highest gear) allowing the tractor to slip without moving
--once moving, the "updateGear" function will take care of finding the best gear for the job
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
VehicleMotor.mrGetStartInGearFactor = function(self, superFunc, ratio)

    --no need to compute anything if driven wheels are not touching the ground
    if self.vehicle.spec_wheels.mrTotalWeightOnDrivenWheels<0.1 then
        return math.huge
    end

    --we don't want a start gear that runs at more than 2m.s-1 @1000rpm (7.2kph)
    local maxRatio = 52
    local absRatio = math.abs(ratio)
    if absRatio<maxRatio then
        return math.huge
    end

    -- if we cannot run the gear with at least 25% rpm with the current speed limit we skip it
    if self:getRequiredRpmAtSpeedLimit(ratio) < (self.minRpm + (self.maxRpm - self.minRpm) * 0.25) then
        return math.huge
    end

    local rimPull = absRatio*self.startGearValues.availablePower/self.peakMotorPowerRotSpeed
    local slipFx = rimPull / (self.vehicle.spec_wheels.mrTotalWeightOnDrivenWheels)

    --we only want gear ratios that allow the tractor to slip without moving
    if slipFx<1 then
        return self.startGearThreshold+1/absRatio --we return a value greater than self.startGearThreshold and the larger the ratio, the smaller the value so that, if no correct gear ratio is found for starting, we would take the gear with the highest ratio possible (usually, the first gear)
    end

    --the higher the gear (small ratio), the higher factor we return (but we want to be enough small to be under startGearThreshold)
    return 1/absRatio

end
VehicleMotor.getStartInGearFactor = Utils.overwrittenFunction(VehicleMotor.getStartInGearFactor, VehicleMotor.mrGetStartInGearFactor)





---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- simplified version for MR with sub-function to enhance readability
-- 20250427 - not so "simple" once every case is managed
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
VehicleMotor.mrUpdateGear = function(self, acceleratorPedal, brakePedal, dt)

    if not self.vehicle.mrWheelShapesCreated then
        return
    end

    local justChangedDirection = false
    if self.currentDirection~=self.mrLastDirection then
        justChangedDirection = true
        self.mrLastDirection = self.currentDirection
    end

    local applyStartGearNeeded = false --if true, we don't wait to call "self:applyTargetGear()"
    self.lastAcceleratorPedal = acceleratorPedal

    local waitingForTimer = false
    local needShifting = false
    if self.gearChangeTimer >= 0 then --there is a timer for gear change running
        self.gearChangeTimer = self.gearChangeTimer - dt --updating the timer (decrease remaining time)
        waitingForTimer = true
        if self.gearChangeTimer<0 then
            needShifting = true
        end
    end
    if self.groupChangeTimer >= 0 then --there is a timer for group change running
        self.groupChangeTimer = self.groupChangeTimer - dt --updating the timer (decrease remaining time)
        waitingForTimer = true
        if self.groupChangeTimer<0 then
            needShifting = true
        end
    end
    if self.directionChangeTimer >= 0 then --there is a timer for dirction change running
        self.directionChangeTimer = self.directionChangeTimer - dt --updating the timer (decrease remaining time)
        waitingForTimer = true
        if self.directionChangeTimer<0 then
            needShifting = true
        end
    end

    if needShifting and self.gearChangeTimer < 0 and self.groupChangeTimer < 0 and self.directionChangeTimer < 0 then --check if this is gear change time
        if self.targetGear ~= 0 then
            self:applyTargetGear()
            --reset all timers = stop them since we already apply new gear / group
            self.gearChangeTimer = -1
            self.groupChangeTimer = -1
            self.directionChangeTimer = -1
        end
    end

    if justChangedDirection and self:getUseAutomaticGearShifting() then
        --reset all timers, we want the autogear to select the right starting gear for the new direction
        --self.gearChangeTimer = -1
        --self.groupChangeTimer = -1
        --self.directionChangeTimer = -1
        self.mrPreventAutoGearShiftTimer = 0
        self.mrTransmissionLastShiftDirectionTimer = 0
        self.autoGearChangeTimer = 0
        self.previousGear = 0
        self.mrBestStartGearSelected = 0
        waitingForTimer = false
    end

    if not waitingForTimer then
        local gearSign = 0
        if acceleratorPedal > 0 then
            if self.minForwardGearRatio ~= nil then
                self.minGearRatio = self.minForwardGearRatio
                self.maxGearRatio = self.maxForwardGearRatio
            else
                gearSign = 1
            end
        elseif acceleratorPedal < 0 then
            if self.minBackwardGearRatio ~= nil then
                self.minGearRatio = -self.minBackwardGearRatio
                self.maxGearRatio = -self.maxBackwardGearRatio
            else
                gearSign = -1
            end
        else
            if self.maxGearRatio > 0 then
                if self.minForwardGearRatio == nil then
                    gearSign = 1
                end
            elseif self.maxGearRatio < 0 then
                if self.minBackwardGearRatio == nil then
                    gearSign = -1
                end
            end
        end

        local newGear = self.gear

        if self.backwardGears or self.forwardGears then
            self.autoGearChangeTimer = math.max(0, self.autoGearChangeTimer - dt)
            if self:getUseAutomaticGearShifting() and self:getManualClutchPedal() <= 0.5 then

                self.mrTransmissionLastShiftDirectionTimer = math.max(0, self.mrTransmissionLastShiftDirectionTimer - dt)

                if self.mrTransmissionLastShiftDirectionTimer==0 then
                    self.mrTransmissionLastShiftDirection = 0
                end

                --20250606 - prevent autoshifting for 2.5s if player select a gear himself
                if self.mrManualGearShifterActivated then
                    self.mrManualGearShifterActivated = false
                    self.mrPreventAutoGearShiftTimer = 2500
                end

                --20250616 - prevent autoshifting for 2s if player select a group himself
                if self.mrManualGroupShifterActivated then
                    self.mrManualGroupShifterActivated = false
                    self.mrPreventAutoGearShiftTimer = math.max(2000, self.mrPreventAutoGearShiftTimer)
                end

                self.mrPreventAutoGearShiftTimer = math.max(0, self.mrPreventAutoGearShiftTimer - dt)

                -- the users action to accelerate will always allow shifting
                -- this is just to avoid shifting while vehicle is not moving, but shifting conditions change (attaching tool, lowering/lifting tool etc.)
                -- 20250420 - we don't rely on "getIsAutomaticShiftingAllowed" anymore => not correct :"jointDesc.isMoving" is always true for "JOINTTYPE_TRAILER" for example
                --if (self.vehicle:getIsAutomaticShiftingAllowed() or acceleratorPedal ~= 0) and self.mrPreventAutoGearShiftTimer==0 then
                if self.mrPreventAutoGearShiftTimer<=0 or justChangedDirection then

                    --if math.abs(self.vehicle.lastSpeed) < 0.0003 or Vehicle.mrGetIdleTurningActive(self.vehicle) or justChangedDirection then --0.0003 = 1.08kph
                    --20250529 - use differentialRotSpeed instead of vehicle.lastSpeed => if slipping a lot, prevent starting in 3, shifting in 4, but losing all speed (while wheels are still slipping a lot) and shift back in 3 etc etc etc
                    if math.abs(self.differentialRotSpeed) < 0.0003 or Vehicle.mrGetIdleTurningActive(self.vehicle) or justChangedDirection then --0.0003 = 1.08kph

                        --reset lug time
                        self.mrTransmissionLugTime = 0

                        if acceleratorPedal==0 or justChangedDirection or self.mrBestStartGearSelected==0 then
                            newGear = VehicleMotor.mrManageUpdateStartGear(self, gearSign, justChangedDirection)
                            applyStartGearNeeded = true
                        elseif self.mrBestStartGearSelected~=0 then --acceleratorPedal~=0
                            newGear = VehicleMotor.mrManageUpdateStartGear(self, gearSign)
                            if self.gear>0 and newGear>self.gear then
                                newGear = self.gear --we keep bestStartGear except if new gear is lower
                            end
                        elseif self.gear~=0 then --self.mrBestStartGearSelected==0
                            --typical case =
                            --1. start working in 3th gear
                            --2. the speed raises to 3kph => bestStartGearSelected is reset to 0
                            --3. the auto shift tries to shift up to 4th gear (no powershift)
                            --4. the speed returns below 1kph while shifting	
                            --in such a case, we don't want to call "getBestStartGear" and shift back to 3th
                            newGear = VehicleMotor.mrManageUpdateStartGear(self, gearSign)
                            if newGear==self.previousGear then
                                --do not change gear if getBestStartGear return the same gear as previousGear
                                newGear = self.gear
                                --timer to allow some time for the current gear to get more rpm
                                self.mrPreventAutoGearShiftTimer = self.mrPreventAutoGearShiftTime
                            end
                        end

                    else
                        if math.abs(self.vehicle.lastSpeed) > 0.0003 then --0.0003 = 1.08kph // avoid shifting up gears while not moving (against a wall/tree for example)
                            self.mrBestStartGearSelected=0
                        end
                        if self.gear ~= 0 then
                            if self.autoGearChangeTimer == 0 then
                                local curGroupRatio = math.abs(self:getGearRatioMultiplier())
                                --local allowSpecial = (g_time - self.mrLastGearRatioChangeTime)>1500 --at least 1500ms since last gear change
                                if self:getUseAutomaticGroupShifting() and self.gearGroups ~= nil then
                                    --if groups = powershift, we check groups before gears
                                    if self.groupType == VehicleMotor.TRANSMISSION_TYPE.POWERSHIFT then
                                        --checkGroup first
                                        local changeGroupHappened = VehicleMotor.mrManageUpdateGroup(self)
                                        if changeGroupHappened then
                                            --prevent shifting group like mad
                                            self.autoGearChangeTimer = self.autoGearChangeTime
                                        end
                                        newGear = VehicleMotor.mrFindGearChangeTargetGearPrediction(self, self.gear, self.currentGears, curGroupRatio, acceleratorPedal, dt)
                                    else
                                        newGear = VehicleMotor.mrFindGearChangeTargetGearPrediction(self, self.gear, self.currentGears, curGroupRatio, acceleratorPedal, dt)
                                        --checkGroup after gear
                                        local _, wantedGear = VehicleMotor.mrManageUpdateGroup(self, self.gear, newGear, self.currentGears)
                                        if wantedGear~=nil then
                                            newGear = wantedGear
                                        end
                                    end
                                else
                                    newGear = VehicleMotor.mrFindGearChangeTargetGearPrediction(self, self.gear, self.currentGears, curGroupRatio, acceleratorPedal, dt)
                                end
                            end
                        end
                    end

                end
            end
        end
        if newGear ~= self.gear then

            if newGear<self.gear and math.abs(self.vehicle.lastSpeed) < 0.0003 then --0.0003 = 1.08kph
                self.mrBestStartGearSelected = newGear
            end

            self.targetGear = newGear
            self.previousGear = self.gear
            self.gear = 0
            self.minGearRatio = 0
            self.maxGearRatio = 0
            self.autoGearChangeTimer = self.autoGearChangeTime
            self.gearChangeTimer = self.gearChangeTime
            self.lastGearChangeTime = g_time

            local directionMultiplier = self.directionChangeUseGear and self.currentDirection or 1
            SpecializationUtil.raiseEvent(self.vehicle, "onGearChanged", self.gear * directionMultiplier, self.targetGear * directionMultiplier, self.gearChangeTimer, self.previousGear)

            if applyStartGearNeeded then
                if justChangedDirection and self.directionChangeTime>0 then
                    self.gearChangeTimer = -1
                    self.groupChangeTimer = -1
                    self.directionChangeTimer = self.directionChangeTime
                else
                    self:applyTargetGear()
                    --reset all timers = stop them since we already apply new gear / group
                    self.gearChangeTimer = -1
                    self.groupChangeTimer = -1
                    self.directionChangeTimer = -1
                end
            end

        end

        if applyStartGearNeeded and (acceleratorPedal == 0 or justChangedDirection) then
            self.mrTransmissionLastShiftDirection = 1 --do not allow auto shift down right after a starting gear is selected
            self.mrTransmissionLastShiftDirectionTimer = self.mrTransmissionLastShiftDirectionTime
            self.autoGearChangeTimer = 800 -- use the start gear for 800ms before trying to get a better gear
            self.mrBestStartGearSelected = newGear
        end

    end

    if self.gearShiftMode == VehicleMotor.SHIFT_MODE_MANUAL_CLUTCH then
        if self.backwardGears or self.forwardGears then

            local ratio = 0
            if self.currentGears[self.gear] ~= nil then
                local tarRatio = self.currentGears[self.gear].ratio * self:getGearRatioMultiplier()
                local differentialRotSpeed = math.max(math.abs(self.differentialRotSpeed), 0.0001)
                local curRatio = math.min(self.motorRotSpeed / differentialRotSpeed, 2*math.abs(tarRatio))
                --curRatio = math.min(self.motorRotSpeed / math.max(self.differentialRotSpeed, 0.00001), 5000)
                ratio = MathUtil.lerp(math.abs(tarRatio), math.abs(curRatio), math.min(self.manualClutchValue^0.5, 0.9) / 0.9 * 0.5) * math.sign(tarRatio)
            end


            self.minGearRatio, self.maxGearRatio = ratio, ratio

            if self.manualClutchValue == 0 and self.maxGearRatio ~= 0 then
                --local factor = (1 + self.differentialRotSpeed * self.maxGearRatio) / (0.1 + self.mrLastMotorObjectRotSpeed)
                local factor = 1
                if self.mrLastMotorObjectRotSpeed < (self.mrMinRot-1) then
                    factor = self.differentialRotSpeed * self.maxGearRatio / self.mrMinRot --clutch rpm against min rpm
                end
                if factor < 0.85 then
                    self.stallTimer = self.stallTimer + dt
                    if self.stallTimer > 300 then
                        self.vehicle:stopMotor()
                        self.lowBrakeForceLocked = true
                    end
                else
                    self.stallTimer = 0
                end
            else
                self.stallTimer = 0
            end
        end
    end

end

---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
--new function to separate code from updateGear
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
VehicleMotor.mrManageUpdateGroup = function(self, curGear, newGear, gears)

    local oldNewGearRatio = 1
    local checkGroupAndGear = false
    if gears~=nil and newGear~=nil and curGear~=nil and #gears>1 then --20250912 - non need to check gears if there is only one gear
        oldNewGearRatio = gears[newGear].ratio/gears[curGear].ratio
        checkGroupAndGear = true
    end

    --20250615 check if we are going too fast => shift group down if possible in such a case to get more engine stopping power
    if self.activeGearGroupIndex>1 and math.sign(self.gearGroups[self.activeGearGroupIndex].ratio) == math.sign(self.gearGroups[self.activeGearGroupIndex - 1].ratio) then
        local spdLimit = self:getSpeedLimit()
        if math.abs(self.vehicle.lastSpeed)*3600>math.max(1+spdLimit, 1.1*spdLimit) then --speedLimit in kph
            local engineRpm = self.motorRotSpeed*30/math.pi
            local newEngineRpm = engineRpm*oldNewGearRatio*self.gearGroups[self.activeGearGroupIndex - 1].ratio/self.gearGroups[self.activeGearGroupIndex].ratio
            local maxRpmNotGoverned = self.maxRpm-self.vehicle.mrGovernorRange
            if newEngineRpm<1.05*maxRpmNotGoverned then
                self:setGearGroup(self.activeGearGroupIndex - 1)
                return true
            end
        end
    end

    --only check if we get more power by shifting up a group or not
    if self.activeGearGroupIndex < #self.gearGroups then
        if math.sign(self.gearGroups[self.activeGearGroupIndex].ratio) == math.sign(self.gearGroups[self.activeGearGroupIndex + 1].ratio) then
            local engineRpm = self.motorRotSpeed*30/math.pi
            if engineRpm>0.5*(self.mrPowerBandMinRpm+self.mrPowerBandMaxRpm) then
                --check newPower against current power
                local newEngineRpm = engineRpm*oldNewGearRatio*self.gearGroups[self.activeGearGroupIndex + 1].ratio/self.gearGroups[self.activeGearGroupIndex].ratio
                local currentPowerFx = self.torqueCurve:get(engineRpm)*engineRpm
                local newPowerFx = self.torqueCurve:get(newEngineRpm)*newEngineRpm
                if newPowerFx>1.1*currentPowerFx then
                    self:setGearGroup(self.activeGearGroupIndex + 1)
                    return true
                end
            end
        end

    end

    --only check if we get more power by shifting down a group or not
    if self.mrTransmissionLastShiftDirection<=0 and self.activeGearGroupIndex > 1 then
        if math.sign(self.gearGroups[self.activeGearGroupIndex].ratio) == math.sign(self.gearGroups[self.activeGearGroupIndex - 1].ratio) then
            local engineRpm = self.motorRotSpeed*30/math.pi
            if engineRpm<self.mrPowerBandMinRpm then
                --check newPower against current power
                local newEngineRpm = engineRpm*oldNewGearRatio*self.gearGroups[self.activeGearGroupIndex - 1].ratio/self.gearGroups[self.activeGearGroupIndex].ratio
                local currentPowerFx = self.torqueCurve:get(engineRpm)*engineRpm
                local newPowerFx = self.torqueCurve:get(newEngineRpm)*newEngineRpm
                if newPowerFx>currentPowerFx then
                    self:setGearGroup(self.activeGearGroupIndex - 1)
                    return true
                end
            end
        end
    end

    --20250903 - check if we should shift group up and shift gear all way down
    if checkGroupAndGear and curGear==newGear and newGear==#gears then --no gear shift and we are in the last gear
        if self.activeGearGroupIndex < #self.gearGroups then --there is at least one group up remaining
            if math.sign(self.gearGroups[self.activeGearGroupIndex].ratio) == math.sign(self.gearGroups[self.activeGearGroupIndex + 1].ratio) then
                local engineRpm = self.motorRotSpeed*30/math.pi
                if engineRpm>self.mrPowerBandMaxRpm then
                    --check newPower against current power
                    --check with gear 2 first (some transmissions = overlap. Example : 1H is slower than 8L)
                    local newEngineRpm = engineRpm*(gears[2].ratio/gears[curGear].ratio)*self.gearGroups[self.activeGearGroupIndex + 1].ratio/self.gearGroups[self.activeGearGroupIndex].ratio
                    local currentPowerFx = self.torqueCurve:get(engineRpm)*engineRpm
                    local newPowerFx = self.torqueCurve:get(newEngineRpm)*newEngineRpm
                    if newPowerFx>currentPowerFx then
                        self:setGearGroup(self.activeGearGroupIndex + 1)
                        return true, 2
                    else
                        --check with first gear
                        newEngineRpm = engineRpm*(gears[1].ratio/gears[curGear].ratio)*self.gearGroups[self.activeGearGroupIndex + 1].ratio/self.gearGroups[self.activeGearGroupIndex].ratio
                        currentPowerFx = self.torqueCurve:get(engineRpm)*engineRpm
                        newPowerFx = self.torqueCurve:get(newEngineRpm)*newEngineRpm
                        if newPowerFx>currentPowerFx then
                            self:setGearGroup(self.activeGearGroupIndex + 1)
                            return true, 1
                        end
                    end
                end
            end
        end
    end

    return false

end




---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
--new function to separate code from updateGear
--fix problem = with manual direction change activated, when changing direction there is no new call to getBestStartGear
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
VehicleMotor.mrManageUpdateStartGear = function(self, gearSign, force)

    local newGear = self.gear
    local directionChanged = false
    local trySelectBestGear = false

    if gearSign < 0 and (self.currentDirection == 1 or self.gear == 0) then
        self:changeDirection(-1, true)
        directionChanged = true
    elseif gearSign > 0 and (self.currentDirection == -1 or self.gear == 0) then
        self:changeDirection(1, true)
        directionChanged = true
    elseif self.lastAcceleratorPedal ~= 0 and not Vehicle.mrGetIdleTurningActive(self.vehicle) then
        trySelectBestGear = true
    elseif self.mrBestStartGearSelected==0 then
        trySelectBestGear = true
    elseif self.mrBestStartGearSelected~=0 then
        return self.mrBestStartGearSelected
    end

    if directionChanged or force then
        self.mrBestStartGearSelected = 0 --reset best start gear and previous gear when changing direction
        self.previousGear = 0
        self.mrTransmissionLugTime = 0
        trySelectBestGear = true
    end

    if trySelectBestGear then
        local bestGear, maxFactorGroup = VehicleMotor.mrGetBestStartGear(self, self.currentGears)
        newGear = bestGear

        if self:getUseAutomaticGroupShifting() then
            if maxFactorGroup ~= nil and maxFactorGroup ~= self.activeGearGroupIndex then
                self:setGearGroup(maxFactorGroup)
            end
        end
    end

    return newGear
end


---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

--findGearChangeTargetGearPrediction
--trying to get something "simpler", less heavy on the cpu

--look at one gear above and one gear below current gear => better or not ?

--if engine rpm is on the high side = look at one gear (or 2 ?) above

--if engine rpm is on the low side = look at one gear (or 2 ?) below

--do not allow the engine to be lugged down too much (except is accPedal is below 1)

--powerMode = when acc = 1
--normalMode = in-between
--smoothMode = when acc is below 0.5

--accPedal should define "agressiveness" of the transmission management
--accPedal = 1 means we want to target maxPowerRpm and even maxPowerBandRpm

--Players who want the best "economy" = manual gear change
--auto = try to keep the best power, driving like an "old folk" (no need for acc pedal, acc lever full all the time and at least at nominal rpm ? just kidding )

--to get something better = take into account engine load when "in-between" rpm wanted range

--we can't rely on differentialRotAccelerationSmoothed, values are too "funny" (not stable at all)
--it's better to rely on engine rpm than differentialRpm
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

VehicleMotor.mrFindGearChangeTargetGearPrediction = function(self, curGear, gears, curGroupRatio, acceleratorPedal, dt)

    --protection against stupid values
    if curGear==0 then
        curGear = 1
    elseif curGear>#gears then
        curGear = 1
    end

    local gearFound = false
    local newGear = curGear
    local absAccPedal = math.abs(acceleratorPedal)
    local accPedalIdle = absAccPedal<0.1
    --local rpmMargin = 2*self.gearRatio --the smaller the gear (high gear ratio), the greater the margin since we can loose more rpm at low speed than high speed during shifting time
    local maxRpmNotGoverned = self.maxRpm-self.vehicle.mrGovernorRange
    local curGearRatio = gears[curGear].ratio
    local curGlobalRatio = curGearRatio * curGroupRatio

    local pendingGroupRatio = 1

    if self.gearGroups ~= nil then
        pendingGroupRatio = math.abs(self.gearGroups[self.activeGearGroupIndex].ratio) --group ratio can be negative
    end


    --adjust with acceleratorPedal value
    --accPedal 0 means we want to decelerate = we want high rpm
    local minRpmWanted = 0
    local maxRpmWanted = 0

    if accPedalIdle then
        minRpmWanted = 0.5*(self.mrPowerBandMinRpm+self.mrPowerBandMaxRpm) * math.min(math.abs(self.vehicle.lastSpeed)*1000, 1) --20250416 - no need to shift down up to the first gear when decelerating => max minRpmWanted reached at 3.6kph
        maxRpmWanted = maxRpmNotGoverned
    else
        minRpmWanted = MathUtil.lerp(self.minRpm, self.mrPowerBandMinRpm, absAccPedal)
        maxRpmWanted = MathUtil.lerp(self.minRpm*1.4, self.mrPowerBandMaxRpm, absAccPedal)
    end

    local engineRpm = 0.5*(math.abs(self.differentialRotSpeed*curGlobalRatio*30/math.pi) + self.motorRotSpeed*30/math.pi) --20250911 - take the avg between clutch and engine rpm
    local forceLug = false

    if engineRpm<self.minRpm then
        forceLug = true
    end

    --20250615 check if we are going too fast => shift gear down if possible in such a case to get more engine stopping power
    if curGear>1 then
        local spdLimit = self:getSpeedLimit()
        if math.abs(self.vehicle.lastSpeed)*3600>math.max(1+spdLimit, 1.1*spdLimit) then --speedLimit in kph
            local newEngineRpmTmp = engineRpm * pendingGroupRatio * gears[curGear-1].ratio/curGlobalRatio
            if newEngineRpmTmp<1.05*maxRpmNotGoverned then
                gearFound = true
                newGear = curGear-1
            end
        end
    end


    if engineRpm>=minRpmWanted and engineRpm<=maxRpmWanted then
        --nothing to do, all is good
        gearFound = true
    end

    --20250422 - new way of determining if we should shift down or not = check the "motorRotAcceleration" and the totalTime we are below wantedRpm
    --if motorRotAcc is positive and we are not so low in rpm = don't shift down and keep the current gear

    if not gearFound and engineRpm<minRpmWanted then --and self.mrTransmissionLastShiftDirection<=0 then

        --increment "lug" time
        if forceLug then
            self.mrTransmissionLugTime = self.mrTransmissionLugTime + 3*dt --forcelug = 3 times faster to shift down
        elseif self.motorRotAcceleration<10 or forceLug then --less than 100rpm/s
            self.mrTransmissionLugTime = self.mrTransmissionLugTime + dt
        end

        --we are running at too low rpm
        --=> shift down
        local newTmpGear = 0
        local maxNewPowerFx = 0

        if curGear>1 and self.mrTransmissionLugTime>self.mrTransmissionLugMaxTime then
            --check one gear down
            local newEngineRpmTmp = engineRpm * pendingGroupRatio * gears[curGear-1].ratio/curGlobalRatio
            if newEngineRpmTmp<maxRpmNotGoverned then
                maxNewPowerFx = self.torqueCurve:get(engineRpm)*engineRpm --only shift down if we got more power doing so
                local newPowerFx = self.torqueCurve:get(newEngineRpmTmp)*newEngineRpmTmp
                if accPedalIdle or newPowerFx>maxNewPowerFx then
                    newTmpGear = curGear-1
                    maxNewPowerFx = newPowerFx
                end

                --check another gear down, just in case
                if curGear>2 then
                    local newEngineRpmTmp2 = engineRpm * pendingGroupRatio * gears[curGear-2].ratio/curGlobalRatio
                    if newEngineRpmTmp2<maxRpmNotGoverned then --and newEngineRpm<minRpmWanted ?
                        newPowerFx = self.torqueCurve:get(newEngineRpmTmp2)*newEngineRpmTmp2
                        if accPedalIdle or newPowerFx>maxNewPowerFx then
                            newTmpGear = curGear-2
                        end
                    end
                end
            end
        end

        --manage result
        if newTmpGear>0 then
            gearFound = true
            newGear = newTmpGear
        end

    else
        --reset lug time
        self.mrTransmissionLugTime = 0
    end

    if not gearFound and curGear<#gears and engineRpm>0.5*(minRpmWanted+maxRpmWanted) and absAccPedal>0 then
        --check one gear up

        local newEngineRpm = engineRpm * pendingGroupRatio * gears[curGear+1].ratio/curGlobalRatio
        --only shift gear up when we get more power
        local currentPowerFx = self.torqueCurve:get(engineRpm)*engineRpm
        local newPowerFx = self.torqueCurve:get(newEngineRpm)*newEngineRpm

        if newPowerFx>1.05*currentPowerFx then
            newGear = curGear+1
            --check another gear up, just in case
            if curGear<(#gears-1) then
                local ratioComparison = pendingGroupRatio*gears[curGear+2].ratio/curGlobalRatio
                if ratioComparison>0.49 then --do not allow shifting 2 gears up if there is a factor greater than 2 between the current gear and the new gear
                    newEngineRpm = engineRpm * ratioComparison
                    newPowerFx = self.torqueCurve:get(newEngineRpm)*newEngineRpm
                    if newPowerFx>1.15*currentPowerFx then --2 gears up only if it provides more than 15% increased power
                        newGear = curGear+2
                        --check again another gear up, just in case
                        if curGear<(#gears-2) then
                            ratioComparison = pendingGroupRatio*gears[curGear+3].ratio/curGlobalRatio
                            if ratioComparison>0.44 then --do not allow shifting 3 gears up if there is a factor greater than 2.25 between the current gear and the new gear
                                newEngineRpm = engineRpm * ratioComparison
                                newPowerFx = self.torqueCurve:get(newEngineRpm)*newEngineRpm
                                if newPowerFx>1.25*currentPowerFx then  --3 gears up only if it provides more than 25% increased power
                                    newGear = curGear+3
                                end
                            end
                        end
                    end
                end
            end

            --20250422 - check if we are under wantedRpmMin
            if newEngineRpm<minRpmWanted then
                --timer to allow the engine to rev up (it should since we give it more power)
                self.mrTransmissionLastShiftDirection = 1
                self.mrTransmissionLastShiftDirectionTimer = self.mrTransmissionLastShiftDirectionTime
            end

        end

    end

    return newGear

end

---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- MR = if getUseAutomaticGroupShifting is false, we check what is the best gear nevertheless
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
VehicleMotor.mrGetBestStartGear = function(self, gears)
    local directionMultiplier = self.directionChangeUseGroup and 1 or self.currentDirection

    local minFactor = math.huge
    local minFactorGear, minFactorGroup = 1, 1

    local maxFactor = 0
    local maxFactorGear, maxFactorGroup = 1, 1 -- use min gear in min group as default return value
    if self.gearGroups ~= nil and self:getUseAutomaticGroupShifting() then

        --check if 1 group = right direction, otherwise, find the first one matching the current direction
        if self.directionChangeUseGroup and math.sign(self.gearGroups[1].ratio * directionMultiplier)~=self.currentDirection then
            for j=2, #self.gearGroups do
                local groupRatio = self.gearGroups[j].ratio * directionMultiplier
                if math.sign(groupRatio) == self.currentDirection then
                    minFactorGroup = j
                    maxFactorGroup = j
                    break --break for
                end
            end
        end

        for j=1, #self.gearGroups do
            local groupRatio = self.gearGroups[j].ratio * directionMultiplier

            --get the index of the first group in the right direction

            if not self.directionChangeUseGroup or math.sign(groupRatio) == self.currentDirection then
                for i=1, #gears do
                    local factor = self:getStartInGearFactor(gears[i].ratio * groupRatio)
                    if factor < self.startGearThreshold then
                        if factor > maxFactor then
                            maxFactor = factor
                            maxFactorGear = i
                            maxFactorGroup = j
                        end
                    end

                    if factor < minFactor then
                        minFactor = factor
                        minFactorGear = i
                        minFactorGroup = j
                    end
                end
            end
        end
    else
        local gearRatioMultiplier = self:getGearRatioMultiplier()
        for i=1, #gears do
            local factor = self:getStartInGearFactor(gears[i].ratio * gearRatioMultiplier)
            if factor < self.startGearThreshold then
                if factor > maxFactor then
                    maxFactor = factor
                    maxFactorGear = i
                end
            end

            if factor < minFactor then
                minFactor = factor
                minFactorGear = i
            end
        end
    end

    -- return the gear with the lowest factor if we don't find any gear below self.startGearThreshold
    if maxFactor == 0 then
        return minFactorGear, minFactorGroup
    end

    return maxFactorGear, maxFactorGroup
end


---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- MR = we only need availablePower
-- Far easier for the cpu to handle
-- Cherry on the cake : it seems to fix the "memory usage going to the sky" when debugmode is active and GIANTS Studio is remote connected.
-- No more 32GB+ memory usage by "GIANTS Engine"
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
VehicleMotor.mrUpdateStartGearValues = function(self,superFunc, dt)
    local neededPtoTorque = PowerConsumer.getTotalConsumedPtoTorque(self.vehicle, nil, nil, true) / self:getPtoMotorRpmRatio()
    local ptoPower = self.peakMotorPowerRotSpeed * neededPtoTorque
    self.startGearValues.availablePower = self.peakMotorPower - ptoPower
end
VehicleMotor.updateStartGearValues = Utils.overwrittenFunction(VehicleMotor.updateStartGearValues, VehicleMotor.mrUpdateStartGearValues)


---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- MR = we want to keep trace of the shift direction when getIsAutomaticShiftingAllowed() is true
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
VehicleMotor.mrApplyTargetGear = function(self, superFunc)
    local gearRatioMultiplier = self:getGearRatioMultiplier()
    self.gear = self.targetGear
    if self.gearShiftMode ~= VehicleMotor.SHIFT_MODE_MANUAL_CLUTCH then
        if self.currentGears[self.gear] ~= nil then
            self.minGearRatio = self.currentGears[self.gear].ratio * gearRatioMultiplier
            self.maxGearRatio = self.minGearRatio

            if self.vehicle:getIsAutomaticShiftingAllowed() then
                local newGlobalRatio = self.minGearRatio
                if math.sign(newGlobalRatio)~=math.sign(self.mrTransmissionLastShiftGlobalRatio) then
                    self.mrTransmissionLastShiftDirection = 0
                elseif newGlobalRatio==self.mrTransmissionLastShiftGlobalRatio then
                    self.mrTransmissionLastShiftDirection = 0
                elseif math.abs(newGlobalRatio)>math.abs(self.mrTransmissionLastShiftGlobalRatio) then
                    self.mrTransmissionLastShiftDirection = -1 --downshift
                else
                    self.mrTransmissionLastShiftDirection = 1 --upshift
                end
                self.mrTransmissionLastShiftGlobalRatio = newGlobalRatio
                if self.mrTransmissionLastShiftDirection~=0 then
                    --activate timer
                    self.mrTransmissionLastShiftDirectionTimer = self.mrTransmissionLastShiftDirectionTime
                end
            end

        else
            self.minGearRatio = 0
            self.maxGearRatio = 0
        end

        self.startDebug = 0
    end

    self.gearChangeTime = self.gearChangeTimeOrig

    local directionMultiplier = self.directionChangeUseGear and self.currentDirection or 1
    SpecializationUtil.raiseEvent(self.vehicle, "onGearChanged", self.gear * directionMultiplier, self.targetGear * directionMultiplier, 0, self.previousGear)
end
VehicleMotor.applyTargetGear = Utils.overwrittenFunction(VehicleMotor.applyTargetGear, VehicleMotor.mrApplyTargetGear)

---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- MR = applyTargetGear applies the pending group and gear
-- problem = if manual gears and powershift group, it means that if a gear change is pending (or direction change), and we shift a group, the gear and group are shifted right now without waiting for timers
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
VehicleMotor.mrSetGearGroup = function(self, superFunc, groupIndex, isLocked)
    local lastActiveGearGroupIndex = self.activeGearGroupIndex
    self.activeGearGroupIndex = groupIndex
    self.gearGroupChangedIsLocked = isLocked

    if self.activeGearGroupIndex ~= lastActiveGearGroupIndex then
        if self.groupType == VehicleMotor.TRANSMISSION_TYPE.POWERSHIFT and self.activeGearGroupIndex > lastActiveGearGroupIndex then
            self.loadPercentageChangeCharge = 1
        end

        if self.directionChangeUseGroup then
            self.currentDirection = self.activeGearGroupIndex == self.directionChangeGroupIndex and -1 or 1
        end

        if self.gearShiftMode ~= VehicleMotor.SHIFT_MODE_MANUAL_CLUTCH then
            if self.groupType == VehicleMotor.TRANSMISSION_TYPE.DEFAULT then
                self.groupChangeTimer = self.groupChangeTime
                self.gear = 0
                self.minGearRatio = 0
                self.maxGearRatio = 0
            elseif self.groupType == VehicleMotor.TRANSMISSION_TYPE.POWERSHIFT then
                --problem = if a gear change is pending, this call would shift both the group and gear
                --self:applyTargetGear()
                self.groupChangeTimer = 10
            end
        end

        SpecializationUtil.raiseEvent(self.vehicle, "onGearGroupChanged", self.activeGearGroupIndex, self.groupType == VehicleMotor.TRANSMISSION_TYPE.DEFAULT and self.groupChangeTime or 0)
    end
end
VehicleMotor.setGearGroup = Utils.overwrittenFunction(VehicleMotor.setGearGroup, VehicleMotor.mrSetGearGroup)

---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- MR = shiftGroup is only called by player, not by automatic gear/group shifting. We want to memorize that
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
VehicleMotor.mrShiftGroup = function(self, superFunc, up)
    if not self.gearGroupChangedIsLocked then
        if self:getIsGearGroupChangeAllowed() then
            self.mrManualGroupShifterActivated = true
        end
    end
    superFunc(self, up)
end
VehicleMotor.shiftGroup = Utils.overwrittenFunction(VehicleMotor.shiftGroup, VehicleMotor.mrShiftGroup)

---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- MR = when PTO is active = no turbo ?
-- self.lastMotorRpm = rpm for sound (look at VehicleMotor:update to check where this function is called
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
VehicleMotor.mrSetLastRpm = function(self, superFunc, lastRpm)
    local oldMotorRpm = self.lastMotorRpm

    self.lastRealMotorRpm = lastRpm

    --MR : no need for interpolation
    self.lastMotorRpm = self.lastRealMotorRpm

    -- calculate turbo speed scale depending on rpm and motor load
    --local rpmPercentage = (self.lastMotorRpm - math.max(self.lastPtoRpm or self.minRpm, self.minRpm)) / (self.maxRpm - self.minRpm)
    local rpmPercentage = (self.lastMotorRpm - self.minRpm) / (self.maxRpm - self.minRpm)
    local targetTurboRpm = rpmPercentage * self:getSmoothLoadPercentage()
    self.lastTurboScale = self.lastTurboScale * 0.95 + targetTurboRpm * 0.05

    if self.lastAcceleratorPedal == 0 or (self.minGearRatio == 0 and self.autoGearChangeTime > 0) then
        self.blowOffValveState = self.lastTurboScale
    else
        self.blowOffValveState = 0
    end

    self.constantRpmCharge = 1 - math.min(math.abs(self.lastMotorRpm - oldMotorRpm) * 0.15, 1)
end
VehicleMotor.setLastRpm = Utils.overwrittenFunction(VehicleMotor.setLastRpm, VehicleMotor.mrSetLastRpm)

---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- MR = even on full-powershift and CVT, there can be a clutch pedal
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
VehicleMotor.mrGetManualClutchPedal = function(self, superFunc)

    return self.manualClutchValue

end
VehicleMotor.getManualClutchPedal = Utils.overwrittenFunction(VehicleMotor.getManualClutchPedal, VehicleMotor.mrGetManualClutchPedal)

---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- MR = describe the torque down to 0rpm => 0 Nm @0 rpm (IRL, would be 0 torque at higher rpm)
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
VehicleMotor.mrGetTorqueAndSpeedValues = function(self, superFunc)
    local rotationSpeeds = {}
    local torques = {}
    if self.gearShiftMode == VehicleMotor.SHIFT_MODE_MANUAL_CLUTCH then
        table.insert(rotationSpeeds, 0)
        table.insert(torques, 0)
    end
    for _,v in ipairs(self:getTorqueCurve().keyframes) do
        table.insert(rotationSpeeds, v.time*math.pi/30)
        table.insert(torques, self:getTorqueCurveValue(v.time))
    end

    return torques, rotationSpeeds
end
VehicleMotor.getTorqueAndSpeedValues = Utils.overwrittenFunction(VehicleMotor.getTorqueAndSpeedValues, VehicleMotor.mrGetTorqueAndSpeedValues)

---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- MR = impossible to start engine if clutch is not depressed and a gear is engaged (it would wear down or destroy the starter
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
VehicleMotor.mrGetCanMotorRun = function(self, superFunc)
    if self.gearShiftMode == VehicleMotor.SHIFT_MODE_MANUAL_CLUTCH then
        if not self.vehicle:getIsMotorStarted() then
            if self.backwardGears or self.forwardGears then
                if self.manualClutchValue == 0 and self.maxGearRatio ~= 0 then
--                     local factor = 1
--                     local motorRpm = self:getNonClampedMotorRpm()
--                     if motorRpm > 0 then
--                         factor = (self:getClutchRpm() + 50) / motorRpm
--                     end

--                     if factor < 0.2 then
                        return false, VehicleMotor.REASON_CLUTCH_NOT_ENGAGED
--                     end
                end
            end
        end
    end

    return true
end
VehicleMotor.getCanMotorRun = Utils.overwrittenFunction(VehicleMotor.getCanMotorRun, VehicleMotor.mrGetCanMotorRun)