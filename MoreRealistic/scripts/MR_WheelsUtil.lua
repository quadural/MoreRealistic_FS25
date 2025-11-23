
WheelsUtil.mrUpdateWheelsPhysics = function(self, superFunc, dt, currentSpeed, acceleration, doHandbrake, stopAndGoBraking)

    --update mrLastUpdateWheelsPhysicsTime
    --useful when automatic motor start/stop is not enabled => when entering a vehicle with engine ON, most of the time the vehicle would drive a little bit because we are controlling the player moving toward the tractor when pressing the "E" key to enter it
    local lastCallTime = self.mrLastUpdateWheelsPhysicsTime
    self.mrLastUpdateWheelsPhysicsTime = g_time
    local updateControlVehicle = next(self.spec_motorized.differentials) ~= nil and self.spec_motorized.motorizedNode ~= nil
    if not updateControlVehicle then
        return superFunc(self, dt, currentSpeed, acceleration, doHandbrake, stopAndGoBraking)
    end

    WheelsUtil.mrUpdateDrivenWheelsData(self)

    -------------------------------------------------
    -- AutoDrive mod controlled vehicle = do not allow MR to interfer
    -------------------------------------------------
    if self.ad~=nil then
        if self.ad.stateModule~=nil then
            if self.ad.stateModule.isActive~=nil then
                if self.ad.stateModule:isActive() then
                    --20250606 - AutoDrive gives opposite orders to the vehicle when it wants to decelerate (full full full stop full full full stop etc etc) => one frame every 4 frames, we get the reduce speed/brake information
                    --this is too dangerous with heavy vehicles like tractors and trailers => disable MR engine for the vehicle
                    return superFunc(self, dt, currentSpeed, acceleration, doHandbrake, stopAndGoBraking)
                end
            end
        end
    end
    -------------------------------------------------


    --20250511 - AIVehicleUtil.driveAlongCurvature set the doHandbrake parameter to true as soon as the "maxspeed" is >0
    --protection against such "weird" command
    --moreover : AI doesn't seem to use the brake pedal => acc=0 means AI want to decelerate
    local aiDriving = false
    if self:getIsAIActive() then
        aiDriving = true
        if acceleration==0 then
            doHandbrake = true
        else
            doHandbrake = false
        end
    end

    --SpecializationUtil.raiseEvent(self, "onVehiclePhysicsUpdate", 0, 0, false, 0) --reset brake lights and reverse lights

    if not aiDriving then
        if (g_time-lastCallTime)>500 then
            self.mrTemporizeAccelerationTimer = 500
        end
        if self.mrTemporizeAccelerationTimer>0 then
            acceleration = 0
            self.mrTemporizeAccelerationTimer = self.mrTemporizeAccelerationTimer - dt
        end
    end

    local motor = self.spec_motorized.motor

    --reset mrLastMinMotorRot
    if motor.clutchSlippingTimer<=0 then
       motor.mrLastMinMotorRot = 0
    end

    self.spec_motorized.mrEngineIsBraking = true --reset engineBraking
    self.spec_motorized.mrEngineBrakingPowerToApply = 0

    local neededPtoTorque, ptoTorqueVirtualMultiplicator = 0,0

    neededPtoTorque, ptoTorqueVirtualMultiplicator = PowerConsumer.getTotalConsumedPtoTorque(self)
    neededPtoTorque = neededPtoTorque / motor:getPtoMotorRpmRatio()
    motor:setExternalTorqueVirtualMultiplicator(ptoTorqueVirtualMultiplicator)


    local minRotForPTO = 0
    local minRotForPTOidle = 0

    if neededPtoTorque>0 then
        minRotForPTO, _ = motor:getRequiredMotorRpmRange()
        minRotForPTO = minRotForPTO * math.pi/30
        if not self.mrForcePtoRpm then
            minRotForPTO = 0.8*minRotForPTO
        end
        self.mrForcePtoRpm = false
        minRotForPTOidle = math.max(125, minRotForPTO) --125 = 1200rpm
    end

    minRotForPTOidle = math.max(minRotForPTOidle, motor.mrMinRot)

    --separate acceleration into accPedal and brakePedal
    local accPedal, brakePedal = 0, 0

    local isManualTransmission = motor.backwardGears ~= nil or motor.forwardGears ~= nil
    local useManualDirectionChange = (isManualTransmission and motor.gearShiftMode ~= VehicleMotor.SHIFT_MODE_AUTOMATIC)
                                  or motor.directionChangeMode == VehicleMotor.DIRECTION_CHANGE_MODE_MANUAL
    useManualDirectionChange = useManualDirectionChange and self:getIsManualDirectionChangeAllowed()

    local absSpd = math.abs(currentSpeed)

    if useManualDirectionChange then
        if math.sign(acceleration)>0 then
            accPedal = acceleration*motor.currentDirection --can be negative for "motor:updateGear"
        else
            brakePedal = -acceleration
        end
    else --auto direction change
        if self.spec_drivable ~= nil then
            acceleration = acceleration * self.spec_drivable.reverserDirection
        end

        local spdSign = math.sign(currentSpeed)

        if math.abs(acceleration)==0 then
            self.mrAutoDirChangeWaitingForRelease = false
        end

        if absSpd>0.0005 then --0.0005 = 1.8kph
            self.mrAutoDirChangeWantedDirection = 0 --we want to stop before deciding the direction
            if spdSign~=math.sign(acceleration) then
                brakePedal = math.abs(acceleration) --accPedal = 0
            else
                accPedal = acceleration --can be negative for "motor:updateGear"
                --check if motor.gear not in the same direction as acc and currentSpeed
                if math.sign(motor.currentDirection)~=math.sign(acceleration) then --currentSpeed same sign as acceleration, and so, we can change transmission direction on the fly
                    --change transmission direction
                    motor:changeDirection(math.sign(acceleration))
                end
            end
        elseif acceleration~=0 then

            local stopped = absSpd<0.00003 or math.abs(self.spec_wheels.mrAvgDrivenWheelsSpeed)<0.1

            if stopped then --0.1 m/s => 0.36kph
                if stopAndGoBraking or not self.mrAutoDirChangeWaitingForRelease then
                    self.mrAutoDirChangeWantedDirection = math.sign(acceleration)
                end
            end

            if self.mrAutoDirChangeWantedDirection~=0 and math.sign(acceleration)==math.sign(self.mrAutoDirChangeWantedDirection) then
                --keep accelerate, do not try to brake even if sign(currentSpeed)~=sign(acceleration)
                accPedal = acceleration --can be negative for "motor:updateGear"
                if math.sign(motor.currentDirection)~=math.sign(acceleration) then
                    --change transmission direction
                    motor:changeDirection(math.sign(acceleration))
                end
            elseif math.sign(motor.currentDirection)~=math.sign(acceleration) then--if not stopped and spdSign~=math.sign(acceleration) then
                --keep braking
                brakePedal = math.abs(acceleration)
            else
                accPedal = acceleration
            end

        end

        if acceleration~=0 then
            self.mrAutoDirChangeWaitingForRelease = true
        end

    end

    --warning : base game engine => updateGear wants negative accPedal value for reverseGears and positive value for forwardGears
    VehicleMotor.mrUpdateGear(motor, accPedal, brakePedal, dt) --we don't want the return values of accPedal and brakePedal
    accPedal = math.abs(accPedal)

    local smoothAcc, smoothBrake = WheelsUtil.getSmoothedAcceleratorAndBrakePedals(self, accPedal, brakePedal, dt)

    --only smooth if we are going in the right direction
    if math.abs(currentSpeed)>0.00014 and math.sign(currentSpeed)~=math.sign(acceleration) then --0.00014 = 0.5kph // we want to avoid going in the wrong direction because acc is too weak whereas player is fully pressing acc key
        --no acc smooth
        smoothAcc = accPedal
    end

    accPedal = smoothAcc
    if not self:getIsAIActive() then
        --do not smooth brakepedal for AI
        brakePedal = smoothBrake^2 --0.5 input brake = 25% brake power
    end

    local minGearRatio, maxGearRatio = motor:getMinMaxGearRatio()

    --limit accPedal if "was changing direction"
    --issue = if changing direction and the engine "object" has not lost all its rpm, the changing can be a little bit "brutal"
    if math.sign(minGearRatio)*math.sign(self.spec_motorized.mrLastMinGearRatioSet)<0 then
        motor.mrIsChangingDirection = true
    elseif motor.mrLastMotorObjectGearRatio~=0 then
        motor.mrIsChangingDirection = false
    end

    local maxAcceleration = 5 --m/s^2                               motor:getAccelerationLimit()
    local maxMotorRotAcceleration = 0.1*motor.maxRpm --rad/s^2       motor:getMotorRotationAccelerationLimit()
    local clutchForce = 1 -- doesn't seem to do anything in the game

    --handbrake = neutral + full brake
    if doHandbrake then
        self:controlVehicle(0, 0, 0, minRotForPTOidle, math.huge, 0.0, 0.0, 0.0, 0.0, neededPtoTorque)
        self:brake(1)
        --display brake ligths / reverse lights
        SpecializationUtil.raiseEvent(self, "onVehiclePhysicsUpdate", 0, 1, false, currentSpeed)
        return
    end

    --case : hard braking wanted
    if (aiDriving and brakePedal>0) or brakePedal>0.9 then
        --braking wanted (acc pedal released and brake pedal depressed)
        self:controlVehicle(0, 0, 0, minRotForPTOidle, math.huge, 0.0, 0.0, 0.0, 0.0, neededPtoTorque) --auto un-clutch to avoid stalling the engine
        self:brake(brakePedal)

        if math.abs(currentSpeed)<0.00005 or math.abs(self.spec_wheels.mrAvgDrivenWheelsSpeed)<0.1 then
            motor.lowBrakeForceLocked = true --useful when playing with manual clutch
        end

        --display brake light (and reverse light if needed)
        SpecializationUtil.raiseEvent(self, "onVehiclePhysicsUpdate", 0, brakePedal, false, currentSpeed)
        return
    end

    --case PowerReversing : "changing direction change" but too much speed (only for power reversing gearbox)
    if isManualTransmission and useManualDirectionChange and motor.mrIsChangingDirection and motor.directionChangeTime==0 and math.sign(minGearRatio)*motor.differentialRotSpeed<-0.15 then--0.15 = 0.54kph

        --power reverser and engine brake power
        self.spec_motorized.mrEngineBrakingPowerToApply = motor.mrEngineBrakingPowerFx*math.max(accPedal,0.1)*motor.maxRpm*(motor.peakMotorTorque+motor.lastMotorExternalTorque)*0.077 --0.736/9.55=0.077

        --"power reverser"
        local idleRot = motor.mrMinRot
        local targetRot = motor.mrMaxRot
        if math.abs(acceleration)~=1 then
            targetRot = idleRot + math.abs(acceleration) * (targetRot-idleRot)
        end
        minGearRatio = math.clamp((0.1*targetRot+0.9*motor.motorRotSpeed) / motor.differentialRotSpeed, -3000,3000)
        maxGearRatio = minGearRatio
        self:controlVehicle(0, 999, maxAcceleration, minRotForPTOidle, math.max(targetRot, minRotForPTO), maxMotorRotAcceleration, minGearRatio, maxGearRatio, clutchForce, neededPtoTorque)
        self:brake(brakePedal)

        motor.autoGearChangeTimer = 150 --do not allow shifting gears while power reversing (especially if gears are not powershift)

        motor.stallTimer = 0 -- prevent stalling while power reversing

        --display brake ligths
        SpecializationUtil.raiseEvent(self, "onVehiclePhysicsUpdate", 0, brakePedal, false, currentSpeed)
        return
    end


    --case : neutral and "acceleration" not 0
    local clutchPedalDepressed = motor:getManualClutchPedal() > 0.90
    local neutralActive = (minGearRatio == 0 and maxGearRatio == 0) or clutchPedalDepressed

    if clutchPedalDepressed then
        motor.lowBrakeForceLocked = false
    end

    --case : no accPedal, no brakePedal
    -- auto brake or engine brake
    if math.abs(acceleration)<0.001 then
        if motor.lowBrakeForceLocked
        or (g_gameSettings:getValue(GameSettings.SETTING.GEAR_SHIFT_MODE) ~= VehicleMotor.SHIFT_MODE_MANUAL_CLUTCH and (math.abs(currentSpeed)<0.00005 or math.abs(self.spec_wheels.mrAvgDrivenWheelsSpeed)<0.1)) then --0.00005 = 0.18kph
            --auto park brake
            -- if we once locked the low brake force, we keep it locked until the player provides input
            motor.lowBrakeForceLocked = true --handbrake ?
            self:controlVehicle(0, 0, 0, minRotForPTOidle, math.huge, 0, 0, 0, 1, neededPtoTorque)
            self:brake(1)

            --no brake light, no reverse light
            SpecializationUtil.raiseEvent(self, "onVehiclePhysicsUpdate", 0, 0, false, 0)
            return
        end
    end

    motor.lowBrakeForceLocked = false

    if neutralActive then
        self:brake(brakePedal)
        local tRot = motor.mrMinRot
        --if clutchPedalDepressed then
        tRot = tRot + accPedal * (motor.mrMaxRot-motor.mrMinRot)
        --end
        tRot = math.max(minRotForPTOidle, tRot)
        self:controlVehicle(0, 0, 0, tRot, math.huge, 0, 0, 0, 0, neededPtoTorque)

        --display brake ligths / reverse light
        SpecializationUtil.raiseEvent(self, "onVehiclePhysicsUpdate", 0, brakePedal, false, currentSpeed)
        return
    end

    --case : AI driving too fast
    local displayBrake = brakePedal
    if aiDriving then
        displayBrake = 0
        if absSpd>0.001 then --0.001 = 3.6kph
            local spdLimit = motor:getSpeedLimit() --kph
            local spdKph = absSpd*3600
            if spdKph>1.05*spdLimit and spdKph>(spdLimit+1) then --20250530 - avoid lot of "micro" braking while maneuvring in fields
                if spdKph>20 then
                    brakePedal = 10*math.min(1.1, spdKph/(1.05*spdLimit))-10 --2kph or 10% overspeed = maxbrake
                else
                    brakePedal = 0.5*(spdKph-spdLimit) --2kph overspeed = maxbrake
                end
            end
        end
    end

    self:brake(brakePedal)

    --hydrostatic transmission management :
    if self.mrTransmissionIsHydrostatic then
        --20250923 - not linear response to acc
        accPedal = accPedal^1.5
        if self.mrTransmissionIsHydrostaticAutomotive then
            WheelsUtil.mrUpdateWheelsPhysicsHydrostaticAutomotive(self, dt, accPedal, maxAcceleration, maxMotorRotAcceleration, clutchForce, neededPtoTorque, minRotForPTO)
        else
            WheelsUtil.mrUpdateWheelsPhysicsHydrostatic(self, dt, accPedal, maxAcceleration, maxMotorRotAcceleration, clutchForce, neededPtoTorque, minRotForPTO)
        end
        --reset brake
        --self:brake(0)
        --display reverse light if needed
        SpecializationUtil.raiseEvent(self, "onVehiclePhysicsUpdate", accPedal, displayBrake, false, currentSpeed)
        return
    elseif minGearRatio~=maxGearRatio then
        --20250923 - not linear response to acc
        accPedal = accPedal^1.5
        --default "CVT" transmission
        WheelsUtil.mrUpdateWheelsPhysicsCVT(self, dt, accPedal, maxAcceleration, maxMotorRotAcceleration, clutchForce, neededPtoTorque, minRotForPTO)
        --reset brake
        --self:brake(0)
        --display reverse light if needed
        SpecializationUtil.raiseEvent(self, "onVehiclePhysicsUpdate", accPedal, displayBrake, false, currentSpeed)
        return
    end

    --case : gear engaged (clutch pedal not depressed)
    local electronicMaxSpeed = motor:getMaximumForwardSpeed()
    if self.movingDirection < 0 then
        electronicMaxSpeed = motor:getMaximumBackwardSpeed()
    end

    local maxSpeed = (0.45+motor:getSpeedLimit())/3.6 --m/s (0.45 more kph because most of the time, there is slippage = we don't reach the target speed)
    local targetRot = motor.mrMaxRot

    if maxGearRatio~=motor.mrLastGearRatio then
        motor.mrLastGearRatio = maxGearRatio
    end

    local idleRot = motor.mrMinRot

    --fixed ratio transmission = we can limit speed by rpm
    self.spec_motorized.mrEngineIsBraking = false

    --allow more rpm (min rpm) when clutch is not fully engaged
    local minMotorRot = idleRot

    --20250609 - more rpm at idle when pto is on
    if minRotForPTO>0 then
        minMotorRot = minRotForPTOidle --125 = 1200rpm
    else
        if motor.clutchSlippingTimer>0 then
            if motor.mrLastMinMotorRot==0 then
                motor.mrLastMinMotorRot = motor.mrMinRot
            end
            local clutchingWantedRot = MathUtil.lerp(motor.mrMinRot, motor.mrClutchingMaxRot, accPedal)
            if motor.clutchSlippingTimer<1000 then
                minMotorRot = MathUtil.lerp(minMotorRot, clutchingWantedRot, motor.clutchSlippingTimer / 1000)
            else
                minMotorRot = clutchingWantedRot
            end
            --do not allow too quick raising of the min rpm
            minMotorRot = math.min(minMotorRot, motor.mrLastMinMotorRot+40*dt/1000) --about 400rpm per second
        elseif motor.gearShiftMode == VehicleMotor.SHIFT_MODE_MANUAL_CLUTCH then
            minMotorRot = 0 --20250605 - take into account manual clutch => pedal not depress = clutch engaged = engine can stall
        end
    end
    motor.mrLastMinMotorRot = minMotorRot

    targetRot = idleRot + accPedal * (targetRot-idleRot) --rad/s
    targetRot = math.min(targetRot, math.abs(maxSpeed*maxGearRatio))
    local currentClutchSpd = motor.differentialRotSpeed*maxGearRatio
    if (currentClutchSpd)>(targetRot+10.472) then --100 * math.pi / 30 => 100rpm to rad/s
        --limit accelerationPedal
        accPedal = 0
        if motor.lastRealMotorRpm>(motor.minRpm+1) then
            self.spec_motorized.mrEngineIsBraking = true
        end
    elseif currentClutchSpd>targetRot then
        accPedal = math.min(accPedal, 1-(currentClutchSpd-targetRot)/10.472)
    end

    --20250603 - take into account ptoRpm, but after regulating
    if minRotForPTO>0 then
        targetRot = math.max(targetRot, minRotForPTO)
    end

    --20250601 - limit minRpm compared to actual rpm => minRpm should not be greater than actual "clutch" rpm
    --local minRotToApply = math.min(minMotorRpm*math.pi/30, currentClutchSpd+5) -- +50rpm
    --minRotToApply = math.min(minRotToApply, motor.mrMinRot)

    --we want some slipping between gears
    local lastRatio = self.spec_motorized.mrLastMinGearRatioSet
    if lastRatio==0 then
        if math.abs(motor.differentialRotSpeed)<0.5 then
            lastRatio = motor.mrLastMotorObjectRotSpeed * 4
        elseif motor.differentialRotSpeed>0.5 then
            lastRatio = motor.mrLastMotorObjectRotSpeed / motor.differentialRotSpeed
        else --<-0.5
            lastRatio = motor.mrLastMotorObjectRotSpeed / motor.differentialRotSpeed
        end
    elseif math.sign(lastRatio)~=math.sign(maxGearRatio) then
        --change direction
        if motor.directionChangeTime==0  then
            lastRatio = math.sign(maxGearRatio)*500
        else
            lastRatio = maxGearRatio --no smoothing
        end
    end

    if math.abs(lastRatio-maxGearRatio)>0.1 then
        maxGearRatio = 0.2*maxGearRatio + 0.8*lastRatio
        minGearRatio = maxGearRatio
    end

    if accPedal<0.1 then
        self.spec_motorized.mrEngineIsBraking = true
    end

    accPedal = accPedal^0.5

    --20250608 - manual + clutch = accPedal can't be "0" (we don't want the tractor to stall at idle, with a gear engaged
    if g_gameSettings:getValue(GameSettings.SETTING.GEAR_SHIFT_MODE) == VehicleMotor.SHIFT_MODE_MANUAL_CLUTCH  and self.spec_motorized:getIsMotorStarted() then
        local tMinRot = math.max(minMotorRot, motor.mrMinRot)
        if motor.mrLastMotorObjectRotSpeed<tMinRot then
            local clutchRot = motor.differentialRotSpeed*self.spec_motorized.mrLastMinGearRatioSet
            if clutchRot<tMinRot then
                if clutchRot<(tMinRot-10) then
                    accPedal = 1
                else
                    accPedal = math.max(accPedal, 0.1+0.9*(tMinRot-clutchRot)/10)
                end
            end
        end
        minMotorRot = 0
    end

    --self:controlVehicle(accPedal, electronicMaxSpeed, maxAcceleration, minRotToApply, targetRot, maxMotorRotAcceleration, minGearRatio, maxGearRatio, clutchForce, neededPtoTorque)
    self:controlVehicle(accPedal, electronicMaxSpeed, maxAcceleration, minMotorRot, targetRot, maxMotorRotAcceleration, minGearRatio, maxGearRatio, clutchForce, neededPtoTorque)


    --display reverse light if needed
    SpecializationUtil.raiseEvent(self, "onVehiclePhysicsUpdate", accPedal, displayBrake, false, currentSpeed)
    return

end
WheelsUtil.updateWheelsPhysics = Utils.overwrittenFunction(WheelsUtil.updateWheelsPhysics, WheelsUtil.mrUpdateWheelsPhysics)


--*****************************************
--** Hydro transmission (standard = full throttle and then vary the hydraulic motor ratio)
--*****************************************
WheelsUtil.mrUpdateWheelsPhysicsHydrostatic = function(self, dt, accPedal, maxAcceleration, maxMotorRotAcceleration, clutchForce, neededPtoTorque, minRotForPTO)

    local motor = self.spec_motorized.motor
    local gearDirection = motor.currentDirection --math.sign(motor.minGearRatio)
    local maxGearRatioPossible = 800

    --hydrostatic = when we want to move => full rpm and then, acc pedal = hydrostatic lever = speed wanted
    local targetRot = self.mrTransmissionMaxEngineRotWanted
    targetRot = math.max(targetRot, minRotForPTO)



    --determined target speed
    local electronicMaxSpeed = motor:getMaximumForwardSpeed() --max vehicle speed, or regulator set speed, or working tool max speed
    local minGearRatio = motor.minForwardGearRatio
    if math.sign(gearDirection)<0 then --motor.currentDirection<0 then
        electronicMaxSpeed = motor:getMaximumBackwardSpeed()
        minGearRatio = motor.minBackwardGearRatio
    end

    --tool speed limit
    electronicMaxSpeed = math.min(electronicMaxSpeed, motor:getSpeedLimit()/3.6)

    --gearRatio function of hydrostatic lever
    local wantedGearRatio = math.min(maxGearRatioPossible, minGearRatio/math.max(0.005, accPedal))

    --limit gearratio according to electronicMaxSpeed too (avoid being able to harvest at great speed going downhill)
    wantedGearRatio = math.clamp(targetRot/electronicMaxSpeed, wantedGearRatio, maxGearRatioPossible)

    local curGearRatio = math.abs(motor.mrLastMotorObjectGearRatio)
    if curGearRatio==0 then
        curGearRatio = motor.mrLastMotorObjectRotSpeed / math.max(0.1, math.abs(motor.differentialRotSpeed))
        curGearRatio = math.clamp(curGearRatio, minGearRatio, maxGearRatioPossible)
    end
    local newGearRatio = maxGearRatioPossible

--     probleme = we want same engine braking when accpedal = 1 or 0 ?
--     same code for overspeed, or gearRatio too low or wrong direction ?

     --check if we are overspeeding => engine brake
    if motor.mrLastMotorObjectRotSpeed>(targetRot+1) then
        local ffx = math.max(1, motor.mrLastMotorObjectRotSpeed/self.mrTransmissionMaxEngineRotWanted)
        ffx = math.min(ffx-0.995, 0.1)*10 --max braking power @10% more rpm (ffx between 0.05 and 1)
        self.spec_motorized.mrEngineBrakingPowerToApply = motor.mrEngineBrakingPowerFx*motor.peakMotorPower*self.mrTransmissionPowerRatio*ffx
    end


    if math.abs(motor.differentialRotSpeed)<0.01 or motor.differentialRotSpeed*gearDirection>0 then

        if (curGearRatio-wantedGearRatio)>0.1 then --case 1 : curGearRatio>wantedGearRatio => we want to increase speed (lower the gearRatio)
            --fx function of difference between wanted and current ratio
            --local fx = 1-dt*0.06*curGearRatio/(3000*wantedGearRatio/minGearRatio) --not good, we should have the same acc in forward or reverse
            local fx = 1-dt*0.06*curGearRatio/3000/(wantedGearRatio/minGearRatio)^0.5 --the greater the wantedGearRatio (lower gear), the slower the acc
            newGearRatio = curGearRatio * fx * targetRot / math.max(1, motor.mrLastMotorObjectRotSpeed)
            newGearRatio = math.clamp(newGearRatio, wantedGearRatio, maxGearRatioPossible)
            accPedal = 1
            self.spec_motorized.mrEngineIsBraking = false

        elseif (wantedGearRatio-curGearRatio)>0.1 then --case 2 : we want to decelerate (increase gearRatio)
            --trying to keep the targetRot wanted
            -- => setting the gearRatio to allow the engine rpm to be just above the targetRot
            newGearRatio = (1+0.005*dt*0.06) * curGearRatio * targetRot / math.max(1, motor.mrLastMotorObjectRotSpeed)
            newGearRatio = math.min(newGearRatio, wantedGearRatio)
            newGearRatio = math.max(newGearRatio, minGearRatio) --avoid getting ratio too low when going downhill
            if accPedal>0 then
                accPedal = 1
            end
            self.spec_motorized.mrEngineBrakingPowerToApply = math.max(self.spec_motorized.mrEngineBrakingPowerToApply, motor.mrEngineBrakingPowerFx*motor.peakMotorPower*self.mrTransmissionPowerRatio*20/newGearRatio)

        else
            --we are in the wanted gearRatio
            newGearRatio = curGearRatio
            if accPedal==0 and wantedGearRatio==maxGearRatioPossible then
                self.spec_motorized.mrEngineBrakingPowerToApply = math.max(self.spec_motorized.mrEngineBrakingPowerToApply, motor.mrEngineBrakingPowerFx*motor.peakMotorPower*self.mrTransmissionPowerRatio)
            else

                if motor.mrLastMotorObjectRotSpeed>1.02*targetRot then
                    accPedal = 0
                else
                    accPedal = 1
                    self.spec_motorized.mrEngineIsBraking = false
                end

                if motor.mrLastMotorObjectRotSpeed<0.95*targetRot then
                    --not enough hp => we need to increase the gearratio to help the engine
                    newGearRatio = 1.001*newGearRatio
                end

            end

        end

    else --wrong direction = we want to decelerate
        newGearRatio = curGearRatio * targetRot / math.max(1, motor.mrLastMotorObjectRotSpeed)
        newGearRatio = math.min(newGearRatio, maxGearRatioPossible)
        accPedal = 0
        --20250604- apply a factor of 0.8 since the controlVehicle is also braking the vehicle with the engine inertia
        self.spec_motorized.mrEngineBrakingPowerToApply = math.max(self.spec_motorized.mrEngineBrakingPowerToApply, 0.2*motor.mrEngineBrakingPowerFx*motor.peakMotorPower*self.mrTransmissionPowerRatio)

        if newGearRatio == maxGearRatioPossible and math.abs(motor.differentialRotSpeed)<0.2 then --0.1 = 0.72kph
            --engage right direction
            --gearDirection = motor.currentDirection
            accPedal = 1
            self.spec_motorized.mrEngineIsBraking = false
        else
            gearDirection = -gearDirection
        end

    end

    --local minTargetRot = 0
    --(0.9-newGearRatio/maxGearRatioPossible) * targetRot
    newGearRatio = newGearRatio * gearDirection

    self:controlVehicle(accPedal, electronicMaxSpeed, maxAcceleration, 0.95*minRotForPTO, targetRot, maxMotorRotAcceleration, newGearRatio, newGearRatio, clutchForce, neededPtoTorque)

end


--*****************************************
--** Hydro transmission automotive (agrifac, ropa, holmer...)
--** adjust engine rpm function of wanted speed and current speed
--*****************************************
WheelsUtil.mrUpdateWheelsPhysicsHydrostaticAutomotive = function(self, dt, accPedal, maxAcceleration, maxMotorRotAcceleration, clutchForce, neededPtoTorque, minRotForPTO)

    local motor = self.spec_motorized.motor
    local gearDirection = motor.currentDirection
    local targetMaxRot = self.mrTransmissionMaxEngineRotWanted
    local targetMinRot = math.max(self.mrTransmissionMinEngineRotWanted, minRotForPTO)

    local maxRatio = 750
    local minRadsDrop = 5 --50rpm => 50*pi/30 (rpm to rad/s)

    --determined target speed m/s
    local targetSpeed = motor:getMaximumForwardSpeed() --max vehicle speed, or regulator set speed, or working tool max speed
    local minGearRatio = motor.minForwardGearRatio
    if math.sign(gearDirection)<0 then
        targetSpeed = motor:getMaximumBackwardSpeed()
        minGearRatio = motor.minBackwardGearRatio
    end

    targetSpeed = math.abs(accPedal * targetSpeed)

    --tool speed limit
    targetSpeed = math.min(targetSpeed, motor:getSpeedLimit()/3.6)

    --check current engine rpm and gearRatio
    local lastRatio = math.abs(motor.mrLastMotorObjectGearRatio)

    --reset automotive target rot if needed
    if motor.mrLastMotorObjectRotSpeed<(motor.minRpm*0.105) then --rpm to rad/s
        self.mrTransmissionAutomotiveTargetRot = 0
    end

    if lastRatio==0 then
        lastRatio = maxRatio
    end
    local newGearRatio = lastRatio
    local lastSpd = math.abs(motor.differentialRotSpeed) --since differential is based on virtual wheels with 1m radius => rad/s = m/s

    --check if we are overspeeding => engine brake
    if lastSpd>1 and lastSpd>(targetSpeed+0.1) then
        local ffx = math.max(1, lastSpd/math.max(1,targetSpeed))
        ffx = math.min(ffx-0.995, 0.1)*10 --max braking power @10% more speed (ffx between 0.05 and 1)
        --limit at low speed
        ffx = math.min(ffx, 0.25*lastSpd)
        self.spec_motorized.mrEngineBrakingPowerToApply = motor.mrEngineBrakingPowerFx*motor.peakMotorPower*self.mrTransmissionPowerRatio*ffx
    end

    self.mrTransmissionAutomotiveTargetRot = math.max(self.mrTransmissionAutomotiveTargetRot, targetMinRot)


    if math.abs(motor.differentialRotSpeed)<0.01 or motor.differentialRotSpeed*gearDirection>0 then
        if lastSpd<targetSpeed then
            --not enough speed
            accPedal = 1

            --increase automotive targetRot since we want more power
            self.mrTransmissionAutomotiveTargetRot = math.min(targetMaxRot, self.mrTransmissionAutomotiveTargetRot+13*dt/1000) --target about 130 more rpm per second

            targetMaxRot = 0.5*minRadsDrop + self.mrTransmissionAutomotiveTargetRot

            --trying to target wanted engine rpm but with a drop rpm to allow acceleration
            local dropRads = math.max(minRadsDrop, lastRatio/10) --at least 50rpm drop
            newGearRatio = (targetMaxRot-dropRads) / math.max(0.1, lastSpd)

            self.spec_motorized.mrEngineIsBraking = false
        else
            if targetSpeed==0 and lastSpd<0.1 then
                accPedal = 0
                newGearRatio = minGearRatio
                targetMaxRot = targetMinRot
            elseif lastSpd>(targetSpeed+0.1) then --too much speed = increase rpm and brake
                accPedal = 0
                self.mrTransmissionAutomotiveTargetRot = math.min(targetMaxRot, self.mrTransmissionAutomotiveTargetRot+15*dt/1000) --target about 150 more rpm per second
                targetMaxRot = self.mrTransmissionAutomotiveTargetRot
                newGearRatio = (self.mrTransmissionAutomotiveTargetRot+minRadsDrop) / math.max(0.1, lastSpd)
            else
                --target speed reach = lower targetRot
                self.mrTransmissionAutomotiveTargetRot = math.max(targetMinRot, self.mrTransmissionAutomotiveTargetRot-10*dt/1000) --target about 50 less rpm per second
                targetMaxRot = self.mrTransmissionAutomotiveTargetRot
                newGearRatio = targetMaxRot / math.max(0.1, lastSpd)
                self.spec_motorized.mrEngineIsBraking = false
                accPedal = 1
            end
        end
    else --wrong direction = we want to decelerate

        --increase engine rpm to simulate hydraulics motors flowing toward hydraulic pump and then this pump tries to rotate the engine
        accPedal = 0
        self.mrTransmissionAutomotiveTargetRot = math.min(targetMaxRot, self.mrTransmissionAutomotiveTargetRot+15*dt/1000) --target about 150 more rpm per second

        newGearRatio = (self.mrTransmissionAutomotiveTargetRot+minRadsDrop) / math.max(0.1, lastSpd)
        newGearRatio = math.min(newGearRatio, maxRatio)

        self.spec_motorized.mrEngineBrakingPowerToApply = math.max(self.spec_motorized.mrEngineBrakingPowerToApply, motor.mrEngineBrakingPowerFx*motor.peakMotorPower*self.mrTransmissionPowerRatio)

        if newGearRatio == maxRatio then
            --engage right direction
            accPedal = 1
            self.spec_motorized.mrEngineIsBraking = false
        else
            gearDirection = -gearDirection
        end

    end

    newGearRatio = math.clamp(newGearRatio, minGearRatio, maxRatio)

    newGearRatio = newGearRatio * gearDirection
    self:controlVehicle(accPedal, targetSpeed, maxAcceleration, 0, targetMaxRot, maxMotorRotAcceleration, newGearRatio, newGearRatio, clutchForce, neededPtoTorque)
end


--*****************************************
--** CVT transmission
--** adjust engine rpm function of wanted speed and current speed
--*****************************************
WheelsUtil.mrUpdateWheelsPhysicsCVT = function(self, dt, accPedal, maxAcceleration, maxMotorRotAcceleration, clutchForce, neededPtoTorque, minRotForPTO)

    local motor = self.spec_motorized.motor
    local gearDirection = motor.currentDirection
    local targetMaxRot = motor.peakMotorPowerRotSpeed
    local targetBrakingRot = 1.05*motor.mrMaxRot
    local targetMinRot = math.max(motor.mrMinRot, minRotForPTO)
    local targetEcoRot = math.max(targetMinRot, motor.mrMinEcoRot)

    local cvtEngineBrakingFx = 0.7 --0.7 because CVT = less "engine braking" than hydrostatic
    local motorRotAccFx = 0.5
    local isIncreasingRate = false

    --determined target speed m/s
    local targetSpeed = motor:getMaximumForwardSpeed() --max vehicle speed, or regulator set speed, or working tool max speed (in meters per second)
    local minGearRatio = motor.minForwardGearRatio
    local maxGearRatio = motor.maxForwardGearRatio
    if math.sign(gearDirection)<0 then
        targetSpeed = motor:getMaximumBackwardSpeed()
        minGearRatio = motor.minBackwardGearRatio
        maxGearRatio = motor.maxBackwardGearRatio
    end

    targetSpeed = math.abs(accPedal * targetSpeed)

    --tool speed limit
    targetSpeed = math.min(targetSpeed, motor:getSpeedLimit()/3.6)

    --check current engine rpm and gearRatio
    local lastRatio = math.abs(motor.mrLastMotorObjectGearRatio)
    local lastMinRatio = math.abs(self.spec_motorized.mrLastMinGearRatioSet)
    --local lastMaxRatio = math.abs(self.spec_motorized.mrLastMaxGearRatioSet)

    if lastRatio==0 then
        --try to find a suitable gear ratio
        lastRatio = motor.mrLastMotorObjectRotSpeed/math.max(1, math.abs(motor.differentialRotSpeed))
        lastRatio = math.clamp(lastRatio, minGearRatio, maxGearRatio)
    end
    local newGearRatioMin, newGearRatioMax = lastRatio, lastRatio
    local lastSpd = math.abs(motor.differentialRotSpeed) --since differential is based on virtual wheels with 1m radius => rad/s = m/s
    --local lastClutchSpeed = math.abs(motor.differentialRotSpeed)*lastRatio

    if motor.mrCvtCurrentSpd==nil then
        motor.mrCvtCurrentSpd = lastSpd
    else
        motor.mrCvtCurrentSpd = 0.75*motor.mrCvtCurrentSpd + 0.25*lastSpd --smoothing
    end
    lastSpd = motor.mrCvtCurrentSpd


    --case : wrong direction
    if math.abs(motor.differentialRotSpeed)>0.01 and motor.differentialRotSpeed*gearDirection<0 then

        motorRotAccFx = 0.5 + accPedal


        --increase engine rpm to get more engine braking power
        if motor.mrLastMotorObjectRotSpeed<targetBrakingRot then
            isIncreasingRate = true
            motor.mrCvtRatioIncRate = motor.mrCvtRatioIncRate + 2*lastRatio*dt/1000
            --newGearRatioMin = lastRatio + 0.3*(lastRatio^0.5) * motor.mrCvtRatioIncRate * dt/1000
            local rpmFx = targetBrakingRot/math.max(1, motor.mrLastMotorObjectRotSpeed)
            newGearRatioMin = lastRatio + (rpmFx^2) * motor.mrCvtRatioIncRate * dt/1000
            motorRotAccFx = 10
        end

        local rpmFactor = cvtEngineBrakingFx*motor.mrLastMotorObjectRotSpeed/targetBrakingRot
        self.spec_motorized.mrEngineBrakingPowerToApply = rpmFactor*motor.mrEngineBrakingPowerFx*motor.peakMotorPower*self.mrTransmissionPowerRatio

        if newGearRatioMin >= maxGearRatio or math.abs(motor.differentialRotSpeed)<0.15 then
            --engage right direction
            --accPedal = 1
            self.spec_motorized.mrEngineIsBraking = false
        else
            accPedal = 0
            gearDirection = -gearDirection

            if math.sign(gearDirection)==1 then
                minGearRatio = motor.minForwardGearRatio
                maxGearRatio = motor.maxForwardGearRatio
            else
                minGearRatio = motor.minBackwardGearRatio
                maxGearRatio = motor.maxBackwardGearRatio
            end
        end

        newGearRatioMax = maxGearRatio

    --below = right direction
    else

        newGearRatioMax = maxGearRatio

        --we are overspeeding => engine brake
        if lastSpd>(targetSpeed+0.12) then
            local ffx = math.max(1, lastSpd/math.max(1,targetSpeed))
            ffx = math.min(ffx-0.995, 0.1)*10 --max braking power when 10% more speed (resulting ffx between 0.05 and 1)
            --limit at low speed
            --ffx = math.min(ffx, 0.25*lastSpd)
            local rpmFactor = cvtEngineBrakingFx*motor.mrLastMotorObjectRotSpeed/targetBrakingRot
            self.spec_motorized.mrEngineBrakingPowerToApply = rpmFactor*motor.mrEngineBrakingPowerFx*motor.peakMotorPower*self.mrTransmissionPowerRatio*ffx
            accPedal = 0

            motorRotAccFx = 10

            --increase engine rpm to get more engine braking power, but take into account current speed compared to wanted speed
            local diff = lastSpd-targetSpeed
            if diff>0.3 then
                local ffx2 = math.min(1, 2*diff) --1.8kph overspeed = max braking engine rpm required // 1kph overspeed = 55% braking rpm
                if motor.mrLastMotorObjectRotSpeed<(targetBrakingRot*ffx2) then
                    --increase engine rpm to get more engine braking power
                    isIncreasingRate = true
                    motor.mrCvtRatioIncRate = motor.mrCvtRatioIncRate + ffx2*0.5*lastRatio*dt/1000
                    newGearRatioMin = lastRatio + motor.mrCvtRatioIncRate * dt/1000
                end
            end

        else
            motor.mrCvtRatioIncRate = 0
            self.spec_motorized.mrEngineIsBraking = false

            newGearRatioMin = minGearRatio
            motorRotAccFx = 0.2

            --scenario = power reversing at high speed => engine rpm raises and power reversing again before changing direction. We want to avoid the engine rpm to snap back from "max engine braking rpm" to "max power rpm"
            if lastSpd>2 and motor.mrLastMotorObjectRotSpeed>(targetMaxRot+1) then
                newGearRatioMin = lastMinRatio * (1-dt/3000)
            elseif lastSpd>(targetSpeed-0.02) and motor.mrLastMotorObjectRotSpeed>targetEcoRot and motor.smoothedLoadPercentage<0.8 then --scenario = target speed reached and engine not @100% load
                motorRotAccFx = -0.2
            elseif motor.rawLoadPercentage>0.91 or motor.mrLastMotorObjectRotSpeed<targetEcoRot then
                --limit motorRotAccFx when near target speed
                local ffx3 = 0.5 + 0.5*math.min(1, math.abs(targetSpeed-lastSpd))
                motorRotAccFx = motorRotAccFx * ffx3
            elseif lastRatio>minGearRatio then
                motorRotAccFx = 0 -- no engine rpm change wanted
            end

        end

    end

    if not isIncreasingRate and motor.mrCvtRatioIncRate>0 then
        motor.mrCvtRatioIncRate = math.max(0, motor.mrCvtRatioIncRate-2*lastRatio*dt/1000)
    end

    newGearRatioMin = math.clamp(newGearRatioMin, minGearRatio, maxGearRatio)
    newGearRatioMax = math.clamp(newGearRatioMax, minGearRatio, maxGearRatio)
    newGearRatioMin = newGearRatioMin * gearDirection
    newGearRatioMax = newGearRatioMax * gearDirection

    maxAcceleration = math.min(1+0.5*lastSpd, maxAcceleration) --limit acc at low speed to avoid very fast take off

    if targetMinRot>motor.mrLastMotorObjectRotSpeed then
        motorRotAccFx = 0.5
    end

    local maxRot = motor.mrLastMotorObjectRotSpeed + motorRotAccFx * maxMotorRotAcceleration * dt/1000
    targetMinRot = math.min(maxRot, targetMinRot) --case : engine at low rev (cruising without load) and engaging the PTO (which means we want a higher "minRot" than the current rpm)
    self:controlVehicle(accPedal, targetSpeed, maxAcceleration, targetMinRot, maxRot, maxMotorRotAcceleration, newGearRatioMin, newGearRatioMax, clutchForce, neededPtoTorque)

end


WheelsUtil.mrUpdateDrivenWheelsData = function(self)
    if self.spec_wheels.mrNbDrivenWheels>0 then
        local totalWeightOnDrivenWheels = 0
        local totalWheelSpeed = 0
        local totalWheelSlip = 0
        self.mrWheelShapesCreated = true
        for i, wheel in ipairs(self.spec_wheels.wheels) do
            if not wheel.physics.wheelShapeCreated then
                self.mrWheelShapesCreated = false
            elseif wheel.physics.mrIsDriven then
                totalWeightOnDrivenWheels = totalWeightOnDrivenWheels + wheel.physics.mrLastTireLoad --KN
                totalWheelSpeed = totalWheelSpeed + wheel.physics.mrLastWheelSpeed
                totalWheelSlip = totalWheelSlip + wheel.physics.mrLastLongSlipS
            end
        end
        self.spec_wheels.mrTotalWeightOnDrivenWheels = totalWeightOnDrivenWheels
        self.spec_wheels.mrAvgDrivenWheelsSpeed = totalWheelSpeed/self.spec_wheels.mrNbDrivenWheels
        self.spec_wheels.mrAvgDrivenWheelsSlip = totalWheelSlip/self.spec_wheels.mrNbDrivenWheels
    end
end


WheelsUtil.mrGetTireRollingResistance = function(tireType, groundType, wetScale, snowScale)
    if wetScale == nil then
        wetScale = 0
    end
    local coeff = WheelsUtil.tireTypes[tireType].mrRollingResistanceCoeffs[groundType]

    if wetScale>0 then
        local coeffWet = WheelsUtil.tireTypes[tireType].mrRollingResistanceCoeffsWet[groundType]
        coeff = coeff + (coeffWet-coeff)*wetScale
    end

    --20250509 -- wheels are bouncing a lot in field => differentials consume lot of power (we are losing power in differentials trying to manage driven wheels speed)
    --and so, we can reduce rolling resistance in field otherwise, this is really hard to get speed with full trailer in field
    if groundType==WheelsUtil.GROUND_FIELD then
        coeff = coeff * 0.75
    end

    if snowScale>0 then
        local coeffSnow = WheelsUtil.tireTypes[tireType].mrRollingResistanceCoeffsSnow[groundType]
        coeff = coeff + (coeffSnow-coeff)*snowScale
    end

    return coeff

end

-- WheelsUtil.mrGetFrictionFix = function(groundType)
--     return RealisticUtils.frictionFixTable[groundType]
-- end

---Get ground type
-- @param boolean isField is on field
-- @param boolean isRoad is on road
-- @param float depth depth of terrain
-- @param densityBits (FieldGroundType.GRASS, FieldGroundType.GRASS_CUT ...)
-- @param terrainAttributes (...)
-- @return integer groundType ground type
WheelsUtil.mrGetGroundType = function(isField, isRoad, depth, densityType, terrainAttribute)
    -- terrain softness:
    -- [  0, 0.1]: road
    -- [0.1, 0.8]: hard terrain
    -- [0.8, 1  ]: soft terrain
    if isField then
        --mr : GRASS = SOFT_TERRAIN --g_currentMission
        if densityType==FieldGroundType.GRASS or densityType==FieldGroundType.GRASS_CUT then
            return WheelsUtil.GROUND_SOFT_TERRAIN, 0
        elseif densityType==FieldGroundType.HARVEST_READY or densityType==FieldGroundType.HARVEST_READY_OTHER then
            return WheelsUtil.GROUND_FIELD, 1 --1 means subtype for field is firmer than cultivated/plowed/etc
        else
            return WheelsUtil.GROUND_FIELD, 0
        end
    elseif isRoad or depth < 0.1 then
        return WheelsUtil.GROUND_ROAD, 0
    else
        --mr : check terrainAttribute
        local materialName = RealisticUtils.terrainAttributeToName[terrainAttribute]
        if materialName~=nil then
            if materialName=="dirt" then
                return WheelsUtil.GROUND_SOFT_TERRAIN, 0
            elseif materialName=="grass" then
                return WheelsUtil.GROUND_SOFT_TERRAIN, 0
            elseif materialName=="gravel" then
                return WheelsUtil.GROUND_HARD_TERRAIN, 0
            elseif materialName=="sand" then
                return WheelsUtil.GROUND_SOFT_TERRAIN, 0
            elseif materialName=="leaves" then
                return WheelsUtil.GROUND_SOFT_TERRAIN, 0
            elseif materialName=="asphalt" then
                return WheelsUtil.GROUND_ROAD, 0
            end
        end

        if depth > 0.8 then
            return WheelsUtil.GROUND_SOFT_TERRAIN, 0
        else
            return WheelsUtil.GROUND_HARD_TERRAIN, 0
        end

    end
end

--return complete wheel assembly mass
--all parameters in meters
--category = can be nil ? else => CAR, TRACTOR, HARVESTER, TELEHANDLER, WHEELLOADER, TRAILER, FORESTRY, ATV, SKIDSTEER, TRUCK, MISC, MOTORBIKE, FORKLIFT, TRACTOR_COMMUNAL
--tireType = MUD, OFFROAD, STREET, CRAWLER, CHAINS, METALSPIKES
--return 0 if no mass can be determined
WheelsUtil.mrGetMassFromDimension = function(width, wheelRadius, rimRadius, category)


    if category=="TRACTOR" then
        return WheelsUtil.mrGetMassFromDimensionTractor(width, wheelRadius, rimRadius)
    elseif category=="HARVESTER" then
        return 1.15*WheelsUtil.mrGetMassFromDimensionTractor(width, wheelRadius, rimRadius)--harvester = same as tractor, but a little heavier most of the time (tire + rim)
    elseif category=="TRAILER" then
        return WheelsUtil.mrGetMassFromDimensionTrailer(width, wheelRadius, rimRadius)
    elseif category=="TRUCK" then
        return WheelsUtil.mrGetMassFromDimensionTruck(width, wheelRadius, rimRadius)
    end

    return 0

end

WheelsUtil.mrGetMassFromDimensionTractor = function(width, wheelRadius, rimRadius)

    --protection against "stupid" values
    if rimRadius>(wheelRadius-0.1) then
        rimRadius = wheelRadius-0.75*width--default = 75 flank
    end

    --if WheelsUtil.tireTypes[tireType].name=="MUD" then
    local airVolumeFx = ((wheelRadius-0.1)^2-rimRadius^2)*math.pi*(width-0.1)

    --2nd protection against "stupid" values
    local wholeWheelMass = 0
    if airVolumeFx<0 then
        wholeWheelMass = 1.3*width*math.pi*wheelRadius^2 --no rim, whole rubber wheel
    else
        --simplified "magic" formula to get some reasonable number representing a complete tractor wheel
        --of course, IRL, each tire model does not weight the same, and each rim is different too as far as weight is concerned (cast iron rim ? steel rim ? DW ? TW ? reinforced ?)
        --wholeWheelMass = 253*airVolumeFx^1.05 + 407*(rimRadius)^0.9
        wholeWheelMass = 500*(wheelRadius*width/0.65)^0.25*wheelRadius^1.05*airVolumeFx^0.25
    end

    return 0.001*wholeWheelMass --kilo to metric ton

end

--Note : I checked some Giants values, and they were quite good but the magic formula allow us to throw at it any dimension and get realistic values
WheelsUtil.mrGetMassFromDimensionTrailer = function(width, wheelRadius, rimRadius)

    --protection against "stupid" values
    if rimRadius>(wheelRadius-0.1) then
        rimRadius = wheelRadius-0.75*width--default = 75 flank
    end

    --simplified "magic" formula to get some reasonable number representing a complete trailer wheel
    --of course, IRL, each tire model does not weight the same, and each rim is different too as far as weight is concerned (cast iron rim ? steel rim ? DW ? TW ? reinforced ?)
    local wholeWheelMass = 2260*rimRadius^3+333*width*wheelRadius

    return 0.001*wholeWheelMass --kilo to metric ton

end

WheelsUtil.mrGetMassFromDimensionTruck = function(width, wheelRadius, rimRadius)

    --protection against "stupid" values
    if rimRadius>(wheelRadius-0.1) then
        rimRadius = wheelRadius-0.75*width--default = 75 flank
    end

    --simplified "magic" formula to get some reasonable number representing a complete truck wheel (drive wheel)
    --of course, IRL, each tire model does not weight the same, and each rim is different too as far as weight is concerned (steer wheel, drive wheel, trailer wheel, aluminium rim)
    local flank = (wheelRadius-rimRadius)/width
    local wholeWheelMass = 105 * (wheelRadius*2)^0.65 * (width/0.3)^0.9 * flank^0.5 * (rimRadius*3.937)^1.1

    return 0.001*wholeWheelMass --kilo to metric ton

end

