--width and radius in meters, load in KN
WheelPhysics.mrGetPressureFx0 = function(width, radius, load)
    local contactPatch = width * radius * 0.5236 -- 2*pi*r/12 (ideal deformation of the wheel = about 1/12 of circonference)
    if contactPatch>0 and load>0 then
        return load / (373*contactPatch^2) -- magic formula = load(T) / patch² / 38
    end
    return 0
end


WheelPhysics.mrUpdateDynamicFriction0 = function(self, dt)

    if self.mrFrictionScale~=nil then
        self.mrDynamicFrictionScale = self.mrFrictionScale
        return
    end

    if self.mrIsDriven then
        if self.mrLastBrakeForce>0 then
            if self.mrDynamicFrictionScale>1.2 then
                self.mrDynamicFrictionScale = 1.2
                self.isFrictionDirty = true
            end
        else

            local minFx = 1
            local maxFx = 1.2
            local groundFx = 100
            local spd0 = 3

            if self.hasSnowContact then
                minFx = 1
                maxFx = 1.2
                groundFx = 70
            else
                if self.mrLastGroundType==WheelsUtil.GROUND_ROAD then
                    maxFx = 2.5
                    groundFx = 130
                    spd0 = 2 -- reach max friction at lower speed
                elseif self.mrLastGroundType==WheelsUtil.GROUND_HARD_TERRAIN then
                    maxFx = 2.2
                    groundFx = 100
                elseif self.mrLastGroundType==WheelsUtil.GROUND_SOFT_TERRAIN then
                    maxFx = 2
                    groundFx = 75

                    --20250623 - limit maxFx if too much slipping
                    if self.mrLastLongSlipS>0.35 then
                        maxFx = (0.35/self.mrLastLongSlipS)*maxFx
                    end

                elseif self.mrLastGroundType==WheelsUtil.GROUND_FIELD then
                    if self.mrLastGroundSubType==1 then --firmer ground field (eg: harvest state)
                        maxFx = 1.8
                        groundFx = 60
                    else
                        maxFx = 1.7
                        groundFx = 45
                    end

                    --20250623 - limit maxFx if too much slipping
                    if self.mrLastLongSlipS>0.25 then
                        maxFx = (0.25/self.mrLastLongSlipS)*maxFx
                    end

                end

                local groundWetness = g_currentMission.environment.weather:getGroundWetness()
                --50% less maxFx when wetness=1
                if groundWetness>0.01 then
                    maxFx = (1-0.5*groundWetness)*maxFx
                end

                maxFx = math.max(maxFx, minFx)

            end

            local tyreFx = groundFx*self.mrTotalWidth*self.radius/math.max(0.1, self.mrLastTireLoad)
            tyreFx = math.clamp(tyreFx, minFx, maxFx)
            local curSpd = self.vehicle.lastSpeed*1000
            local newDynamicFrictionScale = 1
            --we want to get tyreFx*minFx/maxFx at speed lower than 0.1m/s, then we want to reach tyreFx at spd0 m/s
--             if curSpd>=spd0 then --10.8kph
--                 newDynamicFrictionScale = tyreFx
--             elseif curSpd>0.1 then --0.36kph
--                 local mm = minFx/maxFx
--                 local a0 = tyreFx*(1-mm)/(spd0-0.1)
--                 local speedFx = math.min(1, mm + a0*curSpd)
--                 newDynamicFrictionScale = speedFx*tyreFx
--             else
--                 newDynamicFrictionScale = tyreFx*minFx/maxFx
--             end

            --we want to get tyreFx*0.8 at speed lower than 0.1m/s, then we want to reach tyreFx at spd0 m/s
            if curSpd>=spd0 then --10.8kph
                newDynamicFrictionScale = tyreFx
            elseif curSpd>0.1 then --0.36kph
                local a0 = 0.2/(spd0-0.1)
                local speedFx = 0.8 + a0*(curSpd-0.1)
                newDynamicFrictionScale = speedFx*tyreFx
            else
                newDynamicFrictionScale = math.max(tyreFx*0.8, minFx)
            end

            --20250601 - limit newDynamicFrictionScale at low speed (against a wall for example)
            newDynamicFrictionScale = math.min(newDynamicFrictionScale, math.max(minFx, math.abs(self.mrLastWheelSpeed)))

            --20250515 - add some more friction when wheels are rotated
            newDynamicFrictionScale = newDynamicFrictionScale * (1+0.2*math.abs(self.steeringAngle))

            --20250701 - add contact normal ratio
            newDynamicFrictionScale = math.max(self.mrLastContactNormalRatio*newDynamicFrictionScale, minFx)

            self.mrDynamicFrictionScaleS = 0.9*self.mrDynamicFrictionScaleS + 0.1*newDynamicFrictionScale

            if math.abs(self.mrDynamicFrictionScaleS-self.mrDynamicFrictionScale)>0.02 then
                self.mrDynamicFrictionScale = self.mrDynamicFrictionScaleS
                self.isFrictionDirty = true
            end

        end

    else
        --not mrIsDriven
        local wantedFriction = 1.2 * math.clamp(self.vehicle.lastSpeed*240, 1, 2) --x2 @30kph
        if math.abs(self.mrDynamicFrictionScale-wantedFriction)>0.1 then
            self.isFrictionDirty = true
            self.mrDynamicFrictionScale = wantedFriction
        end
    end

end
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
--MR : handle the "onStay" case too
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
WoodCrusher.mrWoodCrusherMoveTriggerCallback = function(self, superFunc, triggerId, otherActorId, onEnter, onLeave, onStay, otherShapeId)
    local vehicle = g_currentMission.nodeToObject[otherActorId]
    if vehicle == nil and getRigidBodyType(otherActorId) == RigidBodyType.DYNAMIC then
        local splitType = g_splitShapeManager:getSplitTypeByIndex(getSplitType(otherActorId))
        if splitType ~= nil and splitType.woodChipsPerLiter > 0 then
            --MR : handle the "onStay" case too. Sometimes, the onEnter or onLeave callback are not raised (example : when loading a game with a wood log already in place in the wood crusher)
            if onStay then
                if self.moveTriggerNodes[otherActorId] == nil then
                    self.moveTriggerNodes[otherActorId] = 1
                    self.vehicle:raiseActive()
                end
            elseif onEnter then
                self.moveTriggerNodes[otherActorId] = Utils.getNoNil(self.moveTriggerNodes[otherActorId],0)+1
                self.vehicle:raiseActive()
            elseif onLeave then
                local c = self.moveTriggerNodes[otherActorId]
                if c ~= nil then
                    c = c-1
                    if c == 0 then
                        self.moveTriggerNodes[otherActorId] = nil
                    else
                        self.moveTriggerNodes[otherActorId] = c
                    end
                end
            end
        end
    end
end
WoodCrusher.woodCrusherMoveTriggerCallback = Utils.overwrittenFunction(WoodCrusher.woodCrusherMoveTriggerCallback, WoodCrusher.mrWoodCrusherMoveTriggerCallback)


---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
--MR : handle the "onStay" case too
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
WoodCrusher.mrWoodCrusherDownForceTriggerCallback = function(self, superFunc, triggerId, otherActorId, onEnter, onLeave, onStay, otherShapeId)
    local vehicle = g_currentMission.nodeToObject[otherActorId]
    if vehicle == nil and getRigidBodyType(otherActorId) == RigidBodyType.DYNAMIC then
        local splitType = g_splitShapeManager:getSplitTypeByIndex(getSplitType(otherActorId))
        if splitType ~= nil and splitType.woodChipsPerLiter > 0 then
            for i=1, #self.downForceNodes do
                local downForceNode = self.downForceNodes[i]
                if downForceNode.trigger == triggerId then
                    --MR : handle the "onStay" case too. Sometimes, the onEnter or onLeave callback are not raised (example : when loading a game with a wood log already in place in the wood crusher)
                    if onStay then
                        if downForceNode.triggerNodes[otherActorId] == nil then
                            downForceNode.triggerNodes[otherActorId] = 1
                            self.vehicle:raiseActive()
                        end
                    elseif onEnter then
                        downForceNode.triggerNodes[otherActorId] = Utils.getNoNil(downForceNode.triggerNodes[otherActorId], 0) + 1
                        self.vehicle:raiseActive()
                    elseif onLeave then
                        local c = downForceNode.triggerNodes[otherActorId]
                        if c ~= nil then
                            c = c-1
                            if c == 0 then
                                downForceNode.triggerNodes[otherActorId] = nil
                            else
                                downForceNode.triggerNodes[otherActorId] = c
                            end
                        end
                    end
                end
            end
        end
    end
end
WoodCrusher.woodCrusherDownForceTriggerCallback = Utils.overwrittenFunction(WoodCrusher.woodCrusherDownForceTriggerCallback, WoodCrusher.mrWoodCrusherDownForceTriggerCallback)















--debug
WoodCrusher.updateWoodCrusher = function(self, woodCrusher, dt, isTurnedOn)
    if isTurnedOn then
        if self.isServer then
            for node in pairs(woodCrusher.crushNodes) do
                WoodCrusher.crushSplitShape(self, woodCrusher, node)
                woodCrusher.crushNodes[node] = nil
                woodCrusher.moveTriggerNodes[node] = nil
            end

            local maxTreeSizeY = 0
            for id in pairs(woodCrusher.moveTriggerNodes) do
                if not entityExists(id) then
                    woodCrusher.moveTriggerNodes[id] = nil
                else
                    for i=1, #woodCrusher.downForceNodes do
                        local downForceNode = woodCrusher.downForceNodes[i]
                        if downForceNode.triggerNodes[id] ~= nil or downForceNode.trigger == nil then
                            local x, y, z = getWorldTranslation(downForceNode.node)
                            local nx, ny, nz = localDirectionToWorld(downForceNode.node, 1,0,0)
                            local yx, yy, yz = localDirectionToWorld(downForceNode.node, 0,1,0)

                            local minY,maxY, minZ,maxZ = testSplitShape(id, x,y,z, nx,ny,nz, yx,yy,yz, downForceNode.sizeY, downForceNode.sizeZ)
                            if minY ~= nil then
                                local cx,cy,cz = localToWorld(downForceNode.node, 0, (minY+maxY)*0.5, (minZ+maxZ)*0.5)
                                local downX,downY,downZ = localDirectionToWorld(downForceNode.node, 0, -downForceNode.force, 0)
                                addForce(id, downX, downY, downZ, cx,cy,cz, false)
                                --#debug drawDebugLine(cx, cy, cz, 1, 0, 0, cx+downX, cy+downY, cz+downZ, 0, 1, 0, true)
                            end
                        end
                    end

                    if woodCrusher.shapeSizeDetectionNode ~= nil then
                        local x, y, z = getWorldTranslation(woodCrusher.shapeSizeDetectionNode)
                        local nx, ny, nz = localDirectionToWorld(woodCrusher.shapeSizeDetectionNode, 1,0,0)
                        local yx, yy, yz = localDirectionToWorld(woodCrusher.shapeSizeDetectionNode, 0,1,0)

                        local minY, maxY, _, _ = testSplitShape(id, x, y, z, nx, ny, nz, yx, yy, yz, woodCrusher.cutSizeY, woodCrusher.cutSizeZ)
                        if minY ~= nil then
                            if woodCrusher.mainDrumRefNode ~= nil then
                                maxTreeSizeY = math.max(maxTreeSizeY, maxY)
                            end
                        end
                    end
                end
            end
            if woodCrusher.mainDrumRefNode ~= nil then
                local x, y, z = getTranslation(woodCrusher.mainDrumRefNode)
                local ty = math.min(maxTreeSizeY, woodCrusher.mainDrumRefNodeMaxY)
                if ty > y then
                    y = math.min(y + 0.0003*dt, ty)
                else
                    y = math.max(y - 0.0003*dt, ty)
                end

                setTranslation(woodCrusher.mainDrumRefNode, x, y, z)
            end

            if next(woodCrusher.moveTriggerNodes) ~= nil or woodCrusher.crushingTime > 0 then
                self:raiseActive()
            end
        end
    end
end







VehicleMotor.mrUpdateOLD = function(self, superFunc, dt)
    local clutchSlippingTimer = self.clutchSlippingTimer
    local motorRotationAccelerationLimit = self.motorRotationAccelerationLimit --fix bug : in neutral, engine rpm acceleration is not right according to "self.motorRotationAccelerationLimit"
    self.motorRotationAccelerationLimit = self.motorRotationAccelerationLimit/10
    superFunc(self, dt)
    self.motorRotationAccelerationLimit = motorRotationAccelerationLimit

    local vehicle = self.vehicle
    if next(vehicle.spec_motorized.differentials) ~= nil and vehicle.spec_motorized.motorizedNode ~= nil then
        --self.mrLastMotorObjectRotSpeed, _, self.mrLastMotorObjectGearRatio = getMotorRotationSpeed(vehicle.spec_motorized.motorizedNode) --moved to "motorized:onUpdate"
        if self.gearShiftMode ~= VehicleMotor.SHIFT_MODE_MANUAL_CLUTCH and not self.mrTransmissionIsHydrostatic then
            -- dynamically adjust the max gear ratio while starting in a gear and have not reached the min. differential speed
            -- this simulates clutch slipping and allows a smooth acceleration
            if (self.backwardGears or self.forwardGears) and self.gearRatio ~= 0 and self.maxGearRatio ~= 0 then
                if self.lastAcceleratorPedal ~= 0 then
                    local slippingWantedRpm = MathUtil.lerp(self.minRpm, self.mrClutchingMaxRpm, math.abs(self.lastAcceleratorPedal))
                    local minDifferentialSpeed = slippingWantedRpm / math.abs(self.maxGearRatio) * math.pi / 30
                    if math.abs(self.differentialRotSpeed) < minDifferentialSpeed * 0.75 then
                        self.clutchSlippingTimer = self.clutchSlippingTime
                        self.clutchSlippingGearRatio = self.gearRatio
                    else
                        self.clutchSlippingTimer = math.max(clutchSlippingTimer - dt, 0)
                    end
                else
                    self.clutchSlippingTimer = 0
                end
            end
        end
    end

    --fix visual bug = left foot keeps going from pedal clutch to idle
    if self.lastSmoothedClutchPedal<0.01 then
        self.lastSmoothedClutchPedal = 0
    end

end
VehicleMotor.update = Utils.overwrittenFunction(VehicleMotor.update, VehicleMotor.mrUpdate)


WheelPhysics.mrUpdateDynamicFriction1 = function(self, dt)
    --20250111 - too difficult to get homogenous results by playing with friction to get right wheel slip
    --trying to guess the expected wheel slip (target slip) and then update the friction accordingly

    if self.mrIsDriven then
        if self.mrLastBrakeForce>0 then
            if self.mrDynamicFrictionScale>1.2 then
                self.mrDynamicFrictionScale = 1.2
                self.isFrictionDirty = true
            end
        else
            local newDynamicFrictionScale = 1

            --local F1 = math.abs(self.vehicle.spec_motorized.motor.mrLastAppliedTorqueS * self.vehicle.spec_motorized.motor.gearRatio)
            --local F1 = math.abs(self.vehicle.spec_motorized.motor.lastMotorAvailableTorque * self.vehicle.spec_motorized.motor.gearRatio)
            --local F2 = self.vehicle.spec_wheels.mrTotalWeightOnDrivenWheels * 1 --friction

            local maxDynamicFrictionFx = 2.5

            if self.mrLastGroundType==WheelsUtil.GROUND_ROAD then
                maxDynamicFrictionFx = 3
            elseif self.mrLastGroundType==WheelsUtil.GROUND_HARD_TERRAIN then
                maxDynamicFrictionFx = 2.75
            elseif self.mrLastGroundType==WheelsUtil.GROUND_SOFT_TERRAIN then
                maxDynamicFrictionFx = 2.5
            elseif self.mrLastGroundType==WheelsUtil.GROUND_FIELD then
                --maxDynamicFrictionFx = 3--2025059-in field, the vehicle's wheels are bouncing a lot => the lateral slip is consuming friction all the time, we can use a higher maxFX--2.1
                --20250525 : only true on ploughed land ?
                maxDynamicFrictionFx = 2
            end

            if maxDynamicFrictionFx>1 then
                if self.vehicle.spec_wheels.mrTotalWeightOnDrivenWheels>0 and self.mrLastTireLoad>0 then
                    local F1 = (self.mrLastTireLoad / self.vehicle.spec_wheels.mrTotalWeightOnDrivenWheels) * self.vehicle.spec_motorized.motor.lastMotorAvailableTorque * math.abs(self.vehicle.spec_motorized.motor.gearRatio)
                    local F2 = self.mrLastTireLoad * self.tireGroundFrictionCoeff

                    if F2==0 then
                        newDynamicFrictionScale = 1
                    elseif F1>1.1*F2 then
                        newDynamicFrictionScale = 1
                    elseif F1<F2 then
                        newDynamicFrictionScale = maxDynamicFrictionFx
                    else
                        newDynamicFrictionScale = (11*maxDynamicFrictionFx-10)-10*(maxDynamicFrictionFx-1)*F1/F2 --from 3 to 1
                    end
                end

                local spdFX = 1
                local curSpd = self.vehicle.lastSpeed*3600

                --20250412 - more speed = more dynamicFrictionFx possible, but not so much above 20kph
                if curSpd>30 then
                    spdFX = 2
                elseif curSpd>20 then
                    spdFX = 3.45-(curSpd-20)*0.145
                elseif curSpd>10 then
                    spdFX = 3.45
                else
                    spdFX = 1 + (curSpd*maxDynamicFrictionFx*0.2)^0.5
                end

                --20250515 - take into account wheelSpeed (not vehicle speed)
                spdFX = math.max(spdFX, 1.2-0.5*math.abs(self.mrLastWheelSpeed))

                newDynamicFrictionScale = math.min(newDynamicFrictionScale, spdFX)

                --20250515 - add some more friction when wheels are rotated
                newDynamicFrictionScale = newDynamicFrictionScale * (1+0.2*math.abs(self.steeringAngle))

            end

            self.mrDynamicFrictionScaleS = 0.9*self.mrDynamicFrictionScaleS + 0.1*newDynamicFrictionScale

            if math.abs(self.mrDynamicFrictionScaleS-self.mrDynamicFrictionScale)>0.02 then
                self.mrDynamicFrictionScale = self.mrDynamicFrictionScaleS
                self.isFrictionDirty = true
            end
        end

    else
        --not mrIsDriven
        local wantedFriction = 1.2 * math.clamp(self.vehicle.lastSpeed*240, 1, 2) --x2 @30kph
        if math.abs(self.mrDynamicFrictionScale-wantedFriction)>0.1 then
            self.isFrictionDirty = true
            self.mrDynamicFrictionScale = wantedFriction
        end
    end
end



Combine.mrGetActiveConsumedPtoPower = function(self)
    local spec = self.spec_combine
    local isTurnedOn = self:getIsTurnedOn()
    local neededPower = 0

    --pipe
    if self.spec_dischargeable.currentDischargeState~=Dischargeable.DISCHARGE_STATE_OFF then
        neededPower = neededPower + self.mrCombineUnloadingPower
    end

    if isTurnedOn then

        local fruitCapacityFx = 1
        local fruitThreshingFx = 1
        local fruitChopperFx = 1

        --get fruit capacityFx, ThreshingFx and ChopperFx from FruitTypeDesc
        if spec.lastCuttersInputFruitType~=nil then
            local fruitTypeDesc = g_fruitTypeManager:getFruitTypeByIndex(spec.lastCuttersInputFruitType)
            if fruitTypeDesc~=nil then
                fruitCapacityFx = fruitTypeDesc.mrCapacityFx or 1
                fruitThreshingFx = fruitTypeDesc.mrThreshingFx or 1
                fruitChopperFx = fruitTypeDesc.mrChopperFx or 1
            end
        end

        self.mrCombineLitersBuffer = self.mrCombineLitersBuffer + self.mrCombineLastLitersThreshed
        self.mrCombineLastLitersThreshed = 0
        --sample every 750 millisecond
        if g_time>self.mrCombineLitersBufferTime then
            local maxTime = 750
            local totalTime = maxTime + g_time - self.mrCombineLitersBufferTime
            self.mrCombineLitersPerSecond = 1000*self.mrCombineLitersBuffer / totalTime
            self.mrCombineLitersPerSecondS = 0.8*self.mrCombineLitersPerSecondS + 0.2*self.mrCombineLitersPerSecond --smooth
            self.mrCombineLitersBuffer = 0
            self.mrCombineLitersBufferTime = g_time + maxTime
        end

        --threshingSystem
        neededPower = neededPower + self.mrCombineThreshingIdlePower
        if self.mrCombineLitersPerSecondS>0 then
            neededPower = neededPower + self.mrCombineThreshingPowerFx * self.mrCombineLitersPerSecondS * 5 * fruitThreshingFx / RealisticMain.COMBINE_CAPACITY_FX
        end

        --chopper
        if spec.isSwathActive==false then
            neededPower = neededPower + self.mrCombineChopperIdlePower
            if self.mrCombineLitersPerSecondS>0 then
                neededPower = neededPower + self.mrCombineChopperPowerFx * self.mrCombineLitersPerSecondS * 2.85 * fruitChopperFx / RealisticMain.COMBINE_CAPACITY_FX --about 1KW per ton per hour for wheat (fruitChopperFx==1). 1ton per hour for Wheat = 0.35 liters per second => factor 2.85 to get 1KW
            end
        end

        --update mrCombineSpeedLimit
        --conversion : tons per hour to liter per second
        local maxCapacity = self.mrCombineSpotRate*0.35*RealisticMain.COMBINE_CAPACITY_FX*fruitCapacityFx --Metric Ton per hour to Liters per second. Base "fruit" = wheat // 1000/0.79/3600 liters for wheat = 0.35


        local spd = self.lastSpeedReal*3600
        local peakWantedPower = 0.85*self.spec_powerConsumer.sourceMotorPeakPower
        local overloaded = false

        --if both maxPower and maxCapacity are reached => decrease speed even faster
        if neededPower>peakWantedPower then --check needed power not too high
            if self.mrCombineSpeedLimit>(spd+2) then self.mrCombineSpeedLimit=spd end
            self.mrCombineSpeedLimit = math.max(3, self.mrCombineSpeedLimit-0.1*((neededPower/peakWantedPower)^2)*g_physicsDtLastValidNonInterpolated/1000) --kph
            overloaded = true
        end
        if self.mrCombineLitersPerSecond>1.01*maxCapacity then --check max capacity
            if self.mrCombineSpeedLimit>(spd+2) then self.mrCombineSpeedLimit=spd end
            self.mrCombineSpeedLimit = math.max(3, self.mrCombineSpeedLimit-0.1*((self.mrCombineLitersPerSecond/maxCapacity)^2)*g_physicsDtLastValidNonInterpolated/1000) --kph
            overloaded = true
        end

        if not overloaded and self.mrCombineLitersPerSecondS<0.95*maxCapacity then
            self.mrCombineSpeedLimit = math.min(self.mrCombineSpeedLimitMax, self.mrCombineSpeedLimit + (0.5-0.526*self.mrCombineLitersPerSecondS/maxCapacity)*g_physicsDtLastValidNonInterpolated/1000)
        end

        --update last ton per hour rate
        if spec.lastCuttersOutputFillType~=nil and spec.lastCuttersOutputFillType~=FillType.UNKNOWN then
            local fillTypeDesc = g_fillTypeManager:getFillTypeByIndex(spec.lastCuttersOutputFillType)
            self.mrCombineLastTonsPerHour = fillTypeDesc.massPerLiter * self.mrCombineLitersPerSecondS * 3600
        end

    else
        self.mrCombineLitersPerSecond = 0
        self.mrCombineLitersPerSecondS = 0
        self.mrCombineSpeedLimit = 99
    end


    return neededPower

end


-- VehicleMotor:getStartInGearFactor => can be called a lot of time = it needs to be very "fast" computing wise
VehicleMotor.mrGetStartInGearFactorOld = function(self, superFunc, ratio)

    --no need to compute anything if driven wheels are not touching the ground
    if self.vehicle.spec_wheels.mrTotalWeightOnDrivenWheels<1 then --KN
        return math.huge
    end

    --we don't want a start gear that runs at more than 1.75m.s-1 @1000rpm (6.3kph)
    local absRatio = math.abs(ratio)
    if absRatio<60 then
        return math.huge
    end

    -- if we cannot run the gear with at least 25% rpm with the current speed limit we skip it
    if self:getRequiredRpmAtSpeedLimit(ratio) < self.minRpm + (self.maxRpm - self.minRpm) * 0.25 then
        return math.huge
    end

    --check if the ratio is not too low (too much slippage if using it to start)
    --rough formula to exclude the first gears
    if absRatio>(230*self.vehicle.spec_wheels.mrTotalWeightOnDrivenWheels/self.startGearValues.availablePower) then
        return absRatio --we return the absRatio as "factor" value so that the getBestStartGear function can choose the lower gearRatio if nothing better is found
    end

    --1m radius normalized wheel => Power (KW) = wheelSpd (Rad/s) * torque (KN)
    --and : Torque = ground force
    -- => ground force = Power / wheelSpd
    local rimPull = absRatio*self.startGearValues.availablePower/self.peakMotorPowerRotSpeed
    local slipFx = rimPull / (self.vehicle.spec_wheels.mrTotalWeightOnDrivenWheels)

    if slipFx>1 then
        return absRatio --we return the absRatio as "factor" value so that the getBestStartGear function can choose the lower gearRatio if nothing better is found
    end

    local _, y, _ = localDirectionToWorld(self.vehicle.components[1].node, 0, 0, 1)
    if ratio < 0 then
        y = -y
    end

    --we don't want to take into account positive slope assistance (best example : tractor with trailer at still at the top of a hill road. Tractor on flat surface, and trailer still on the slope = we don't want the tractor to try to start in too high a gear)
    --0.707 = about 45° angle = 100% slope => no need to go further, the slipFx should already be "overloaded" (even without any implement => more slope = less tractive weight)
    y = math.clamp(y, 0, 0.7)

    --add the current powerConsumerForce too
    local pullFactor = (rimPull - self.startGearValues.maxForce) / (9.81*self.vehicle:getTotalMass())
    pullFactor = pullFactor-y

    if pullFactor<0.25 then
        return math.huge --we don't want a pull factor too weak (example : starting from a soaked field = larger rolling resistance than starting from road)
    end

    --compute "rank"	
    return 0.25/pullFactor --we want a "low" value to avoid "startGearThreshold" value from base game engine

end


----------------------------------------------------------------------------------------------------------------------------------------------------------
--
--
--
----------------------------------------------------------------------------------------------------------------------------------------------------------


VehicleMotor.mrUpdateGear = function(self, superFunc, acceleratorPedal, brakePedal, dt)

    if acceleratorPedal==0 and self.doSecondBestGearSelection==3 then
        self.autoGearChangeTimer = 2000 --allow 2s for the engine to start moving the tractor with the "bestStartGear"
        self.idleGearChangeTimer = 1
    end

    local adjAcceleratorPedal, adjBrakePedal = superFunc(self,acceleratorPedal, brakePedal, dt)
    if self.groupChangeTimer<-1 then
        self.groupChangeTimer=-1 --fix bug "self.groupChangeTimer" decreasing infinitely (never reset if groupChangeType = powershift)
    end

    return adjAcceleratorPedal, adjBrakePedal
end
VehicleMotor.updateGear = Utils.overwrittenFunction(VehicleMotor.updateGear, VehicleMotor.mrUpdateGear)



----------------------------------------------------------------------------------------------------------------------------------------------------------
--
--
--
----------------------------------------------------------------------------------------------------------------------------------------------------------
VehicleMotor.findGearChangeTargetGearPrediction0 = function(self, curGear, gears, gearSign, gearChangeTimer, acceleratorPedal, dt)
    local newGear = curGear
    local gearRatioMultiplier = self:getGearRatioMultiplier()

    local minAllowedRpm, maxAllowedRpm = self.minRpm, self.maxRpm
    --print(string.format("rpmRange [%.2f %.2f]", minAllowedRpm, maxAllowedRpm))
    local gearRatio = math.abs(gears[curGear].ratio * gearRatioMultiplier)

    local differentialRotSpeed = math.max(self.differentialRotSpeed*gearSign, 0.0001)
    local differentialRpm = differentialRotSpeed * 30 / math.pi
    local clutchRpm = differentialRpm * gearRatio
    --log("differentialRpm", differentialRpm, "gearRatio", gearRatio, "clutchRpm", clutchRpm, "gearSign", gearSign, "self.differentialRotSpeed", self.differentialRotSpeed)


    -- 1. Predict the velocity of the vehicle after the gear change
    local diffSpeedAfterChange
    if math.abs(acceleratorPedal) < 0.0001 then
        -- Assume that we will continue decelerating with 80% of the current deceleration
        local brakeAcc = math.min(self.differentialRotAccelerationSmoothed*gearSign*0.8, 0)
        diffSpeedAfterChange = math.max(differentialRotSpeed + brakeAcc * self.gearChangeTime*0.001, 0)
        --print(string.format("brake expectedAcc: %.3f realAcc %.3f %.3f max: %.2f gr: %.2f speed: %.2f", brakeAcc, self.vehicle.lastSpeedAcceleration*1000*1000, self.differentialRotAccelerationSmoothed, maxExpectedAcc, gearRatio, self.vehicle.lastSpeedReal*1000))
    else
        -- Ignore wheels mass as it is usually negligible and the calculation below is not correct when the differential acceleration is not uniformely distributed
        --[[local neededWheelsInertiaTorque = 0
        local specWheels = self.vehicle.spec_wheels
        for _, wheel in pairs(specWheels.wheels) do
            local invRotInterita = 2.0 / (wheel.mass*wheel.radius * wheel.radius)
            neededWheelsInertiaTorque = neededWheelsInertiaTorque + invRotInterita * self.differentialRotAcceleration * wheel.radius
        end
        neededWheelsInertiaTorque = neededWheelsInertiaTorque / (gearRatio*gearRatio)]]

        local lastMotorRotSpeed = self.motorRotSpeed - self.motorRotAcceleration * (g_physicsDtLastValidNonInterpolated*0.001)
        local lastDampedMotorRotSpeed = lastMotorRotSpeed / (1.0 + self.dampingRateFullThrottle/self.rotInertia*g_physicsDtLastValidNonInterpolated*0.001)


        local neededInertiaTorque = (self.motorRotSpeed - lastDampedMotorRotSpeed)/(g_physicsDtLastValidNonInterpolated*0.001) * self.rotInertia

        local lastMotorTorque = (self.motorAppliedTorque - self.motorExternalTorque - neededInertiaTorque)

        --print(string.format("load: %.3f expected torque: %.3f neededPtoTorque %.3f neededInertiaTorque %.4f", self.motorAppliedTorque, self.motorAvailableTorque, self.motorExternalTorque, neededInertiaTorque))

        local totalMass = self.vehicle:getTotalMass()
        local expectedAcc = lastMotorTorque * gearRatio / totalMass -- differential rad/s^2

        -- The the difference in acceleration is due to gravity and thus will pull back the vehicle when changing gears and some other reasons (non-accounted mass (e.g. trees), collisions, wheel damping, wheel mass, ...)
        -- Use a fixed factor of 90% to separate the effect of the gravity
        local uncalculatedAccFactor = 0.9
        local gravityAcc = math.max(expectedAcc*uncalculatedAccFactor - math.max(self.differentialRotAccelerationSmoothed*gearSign, 0), 0)

        --print(string.format("expectedAcc: %.3f realAcc: %.3f %.3f gravityAcc: %.3f gr: %.2f mass %.1f speed: %.3f dt %.2fms", expectedAcc, self.vehicle.lastSpeedAcceleration*1000*1000, self.differentialRotAcceleration, gravityAcc, gearRatio, totalMass, self.vehicle.lastSpeedReal*1000, g_physicsDtLastValidNonInterpolated))

        diffSpeedAfterChange = math.max(differentialRotSpeed - gravityAcc * self.gearChangeTime*0.001, 0)

        --log("differentialRotSpeed", differentialRotSpeed, "gravityAcc", gravityAcc, "expectedAcc", expectedAcc, "self.differentialRotAccelerationSmoothed", self.differentialRotAccelerationSmoothed, "gearRatio", gearRatio, "lastMotorTorque", lastMotorTorque, "neededInertiaTorque", neededInertiaTorque, "lastDampedMotorRotSpeed", lastDampedMotorRotSpeed, "lastMotorRotSpeed", lastMotorRotSpeed)
    end


    -- 2. Find the gear that gives the maximum power in the valid rpm range after the gear change
    --    If none is valid, store the gear that will get closest to the valid rpm range

    -- TODO allow some clutch slippage to extend the possible rpm range (e.g. when accelerating and switching from gear 1 to gear 2)

    local maxPower = 0
    local maxPowerGear = 0
    for gear=1, #gears do
        local rpm
        if gear == curGear then
            rpm = clutchRpm
        else
            rpm = diffSpeedAfterChange * math.abs(gears[gear].ratio * gearRatioMultiplier) * 30 / math.pi
        end

        -- if we could start in this gear we allow changes, no matter of rpm and power
        local startInGearFactor = self:getStartInGearFactor(gears[gear].ratio * gearRatioMultiplier)
        local minRpmFactor = 1
        if startInGearFactor < self.startGearThreshold then
            minRpmFactor = 0
        end

        -- current gear is always allowed since clutchRpm could be slightly highe ror lower then the limits due to float 32
        if (rpm <= maxAllowedRpm and rpm >= minAllowedRpm * minRpmFactor) or gear == curGear then
            local power = self:getTorqueCurveValue(rpm) * rpm
            --print(string.format(" power %.2f @ %.d %d", power, gear, rpm))
            if power >= maxPower then
                maxPower = power
                maxPowerGear = gear
            end
        end
    end

    --local curPower = self:getTorqueCurveValue(clutchRpm) * clutchRpm
    --print(string.format("power %.2f @ %d rpms: %.2f %.2f diffSpeedAfterChange: %.10f drpm: %.2f", curPower, curGear, clutchRpm, diffSpeedAfterChange * gearRatio * 30 / math.pi, diffSpeedAfterChange, self.differentialRotAccelerationSmoothed * gearRatio * 30 / math.pi))

    local neededPowerPct = 0.8

    -- 3. Find the gear with the best tradeoff (lots of power with low rpm)
    --    Or use the the gear will get closest to the valid rpm range if none of the gears are good
    if maxPowerGear ~= 0 then
        local bestTradeoff = 0

        for gear=#gears,1,-1 do
            local validGear = false
            local nextRpm
            if gear == curGear then
                nextRpm = clutchRpm
            else
                nextRpm = diffSpeedAfterChange * math.abs(gears[gear].ratio * gearRatioMultiplier) * 30 / math.pi
            end

            -- if we could start in this gear we allow changes, no matter of rpm and power
            local startInGearFactor = self:getStartInGearFactor(gears[gear].ratio * gearRatioMultiplier)
            local minRpmFactor = 1
            local neededPowerPctGear = neededPowerPct
            if startInGearFactor < self.startGearThreshold then
                neededPowerPctGear = 0
                minRpmFactor = 0
            end

            if nextRpm <= maxAllowedRpm and nextRpm >= minAllowedRpm * minRpmFactor or gear == curGear then
                local nextPower = self:getTorqueCurveValue(nextRpm) * nextRpm

                -- Choose the gear if it gets close enough to the max power
                if nextPower >= maxPower*neededPowerPctGear or gear == curGear then
                    local powerFactor = (nextPower - maxPower*neededPowerPctGear) / (maxPower*(1-neededPowerPctGear)) -- 0 when at 80% of maxPower, 1 when at maxPower
                    local curSpeedRpm = differentialRpm * math.abs(gears[gear].ratio * gearRatioMultiplier)
                    local rpmFactor = math.clamp((maxAllowedRpm - curSpeedRpm) / math.max(maxAllowedRpm-minAllowedRpm, 0.001), 0, 2)
                    if rpmFactor > 1 then
                        rpmFactor = 1 - (rpmFactor - 1) * 4
                    end

                    local gearChangeFactor
                    if gear == curGear then
                        gearChangeFactor = 1
                    else
                        gearChangeFactor = math.min(-gearChangeTimer / 2000, 0.9) -- the longer we wait, the less penality we add for gear changes
                    end

                    local rpmPreferenceFactor = 0
                    -- when shifting down the lower gear should have a higher rpm, otherwise we penalize it with -1
                    if gear < curGear then
                        rpmPreferenceFactor = math.clamp((nextRpm - clutchRpm) / 250, -1, 0)
                    end

                    -- when starting with a preselected/higher gear we force to use it as long as the factor is still valid
                    if gear < self.bestGearSelected then
                        local factor = self:getStartInGearFactor(gearRatio)
                        if factor < self.startGearThreshold then
                            gearChangeFactor = gearChangeFactor - 3
                        end
                    end

                    -- prefer middle rpm range instead of upper and lower 20% of range
                    rpmPreferenceFactor = rpmPreferenceFactor - (1-math.min(math.sin(rpmFactor * math.pi)*5, 2)) * 0.7

                    -- if multiple gears are able to stay in the prefered rpm range, we always prefer the gear we are in until it's getting out of the range
                    -- this prevents to much shifting when we have a lot of gears with small ratio steps
                    -- only apply if rpmPreferenceFactor is postive so we do not negative influence the current gear
                    if gear == curGear and rpmPreferenceFactor > 0 then
                        rpmPreferenceFactor = rpmPreferenceFactor * 1.5
                    end

                    if math.abs(acceleratorPedal) < 0.0001 then
                        rpmFactor = 1-rpmFactor -- choose a high rpm when decelerating
                    else
                        rpmFactor = rpmFactor * 2
                    end

                    -- when just rolling allow downshifting to use motor brake when below 25% of rpm range
                    -- so we avoid hitting always the highest rpm on the lower gear (would be better for motor break, but sounds stupid)
                    if math.abs(acceleratorPedal) < 0.0001 then
                        if (clutchRpm - minRpmFactor) / (maxAllowedRpm - minRpmFactor) > 0.25 then
                            if gear < curGear then
                                powerFactor = 0
                                rpmFactor = 0
                            elseif gear == curGear then
                                powerFactor = 1
                                rpmFactor = 1
                            end
                        end
                    end

                    -- if we could start in the gear we don't care about the power and rpm preference
                    -- only apply to higher gears, so we won't accidentally rate lower gears higher than current gear if current gear is in higher rpms
                    if gear > curGear then
                        if startInGearFactor < self.startGearThreshold then
                            powerFactor = 1
                            rpmPreferenceFactor = 1
                        end
                    end

                    local tradeoff = powerFactor + rpmFactor + gearChangeFactor + rpmPreferenceFactor

                    if tradeoff >= bestTradeoff then
                        bestTradeoff = tradeoff
                        newGear = gear
                    --    print(string.format("better tradeoff %.2f with %d power: %.2f vs %.2f @ %d rpm %.2f/%.2f vs %.2f factors: %.2f %.2f %.2f %.2f", tradeoff, gear, nextPower, maxPower, maxPowerGear, nextRpm, curSpeedRpm, clutchRpm, powerFactor, rpmFactor, gearChangeFactor, rpmPreferenceFactor))
                    --else
                    --    print(string.format("worse  tradeoff %.2f with %d power: %.2f vs %.2f @ %d rpm %.2f/%.2f vs %.2f factors: %.2f %.2f %.2f %.2f", tradeoff, gear, nextPower, maxPower, maxPowerGear, nextRpm, curSpeedRpm, clutchRpm, powerFactor, rpmFactor, gearChangeFactor, rpmPreferenceFactor))
                    end

                    if VehicleDebug.state == VehicleDebug.DEBUG_TRANSMISSION then
                        gears[gear].lastTradeoff = tradeoff
                        gears[gear].lastDiffSpeedAfterChange = gear == curGear and diffSpeedAfterChange or nil
                        gears[gear].lastPowerFactor = powerFactor
                        gears[gear].lastRpmFactor = rpmFactor
                        gears[gear].lastGearChangeFactor = gearChangeFactor
                        gears[gear].lastRpmPreferenceFactor = rpmPreferenceFactor
                        gears[gear].lastNextPower = nextPower
                        gears[gear].nextPowerValid = true
                        gears[gear].lastNextRpm = nextRpm
                        gears[gear].nextRpmValid = true
                        gears[gear].lastMaxPower = maxPower
                        gears[gear].lastHasPower = true
                    end

                    validGear = true
                else
                    if VehicleDebug.state == VehicleDebug.DEBUG_TRANSMISSION then
                        gears[gear].lastNextPower = nextPower
                    end
                end
            end

            if not validGear then
                if VehicleDebug.state == VehicleDebug.DEBUG_TRANSMISSION then
                    gears[gear].lastTradeoff = 0
                    gears[gear].lastPowerFactor = 0
                    gears[gear].lastRpmFactor = 0
                    gears[gear].lastGearChangeFactor = 0
                    gears[gear].lastRpmPreferenceFactor = 0
                    gears[gear].lastDiffSpeedAfterChange = gear == curGear and diffSpeedAfterChange or nil
                    gears[gear].lastNextRpm = nextRpm
                    gears[gear].nextRpmValid = nextRpm <= maxAllowedRpm and nextRpm >= minAllowedRpm * minRpmFactor
                    gears[gear].nextPowerValid = false
                    gears[gear].lastMaxPower = maxPower
                    gears[gear].lastHasPower = false
                end
            end
        end
    else
        local minDiffGear = 0
        local minDiff = math.huge
        for gear=1,#gears do
            local rpm = diffSpeedAfterChange * math.abs(gears[gear].ratio * gearRatioMultiplier) * 30 / math.pi
            local diff = math.max(rpm - maxAllowedRpm, minAllowedRpm - rpm)
            if diff < minDiff then
                --print(string.format("better min diff gear: %d diff: %.2f rpm: %.2f" , gear, diff, rpm))
                minDiff = diff
                minDiffGear = gear
            end
        end
        newGear = minDiffGear
    end

    if self.groupChangeTimer<-1 then
        self.groupChangeTimer=-1 --fix bug "self.groupChangeTimer" decreasing infinitely (never reset if groupChangeType = powershift)
    end

    return newGear
end



----------------------------------------------------------------------------------------------------------------------------------------------------------
--
--
--
----------------------------------------------------------------------------------------------------------------------------------------------------------
VehicleMotor.mrFindGearChangeTargetGearPrediction = function(self, superFunc, curGear, gears, gearSign, gearChangeTimer, acceleratorPedal)

    local newGear = curGear
    local absAccPedal = math.abs(acceleratorPedal)
    local gearRatioMultiplier = math.abs(self:getGearRatioMultiplier())
    local curRatio = gears[curGear].ratio

    --adjust with acceleratorPedal value
    local minRpmWanted = MathUtil.lerp(self.minRpm, self.minPowerBandRpm, absAccPedal)
    local maxRpmWanted = MathUtil.lerp(self.minRpm*1.4, self.maxPowerBandRpm, absAccPedal)

    local differentialRpm = math.max(self.differentialRotSpeed*gearSign, 0.0001) * 9.5493 --30 / math.pi
    local clutchRpm = differentialRpm * curRatio * gearRatioMultiplier

    local gearFound = false


    if clutchRpm<minRpmWanted then
        if curGear>1 then
            --check one gear down
            local newClutchRpm = clutchRpm * gears[curGear-1].ratio/curRatio
            if newClutchRpm<maxRpmWanted then
                newGear = curGear-1
            end
        end
    elseif curGear<#gears then
        if self.differentialRotAccelerationSmoothed*gearSign>2 then
            if curGear<(#gears-1) then --fast acceleration = we try to shift gear up 2 times
                local newClutchRpm = clutchRpm * gears[curGear+2].ratio/curRatio
                if newClutchRpm>0.9*minRpmWanted then
                    newGear = curGear+2
                    gearFound = true
                end
            end
            if not gearFound then
                newGear = curGear+1 --acc so fast we don't ahev to check rpm to shift one gear up
            end
        elseif self.differentialRotAccelerationSmoothed*gearSign>1 then
            local newClutchRpm = clutchRpm * gears[curGear+1].ratio/curRatio
            if newClutchRpm>0.9*minRpmWanted then
                newGear = curGear+1
            end
        else
            local newClutchRpm = clutchRpm * gears[curGear+1].ratio/curRatio
            if newClutchRpm>minRpmWanted or clutchRpm>(self.maxRpm-0.7*self.vehicle.mrGovernorRange) then
                newGear = curGear+1
            end
        end
    end

    return newGear

end


----------------------------------------------------------------------------------------------------------------------------------------------------------
--
--
--
----------------------------------------------------------------------------------------------------------------------------------------------------------
VehicleMotor.updateGear = function(self, acceleratorPedal, brakePedal, dt)

    if acceleratorPedal==0 and self.doSecondBestGearSelection==3 then
        self.autoGearChangeTimer = 1000 --allow 1s for the engine to start moving the tractor with the "bestStartGear"
        self.idleGearChangeTimer = 1 --prevent "trySelectBestGear" in all iteration when at still and getUseAutomaticGearShifting is true and getIsAutomaticShiftingAllowed is true (useless cpu consumption)
    end

    self.lastAcceleratorPedal = acceleratorPedal
    local adjAcceleratorPedal = acceleratorPedal
    if self.gearChangeTimer >= 0 then
        self.gearChangeTimer = self.gearChangeTimer - dt
        if self.gearChangeTimer < 0 then
            if self.targetGear ~= 0 then
                self.allowGearChangeTimer = 3000
                self.allowGearChangeDirection = math.sign(self.targetGear-self.previousGear)

                self:applyTargetGear()
            end
        end
        adjAcceleratorPedal = 0
    elseif self.groupChangeTimer > 0 or self.directionChangeTimer > 0 then
        self.groupChangeTimer = self.groupChangeTimer - dt
        self.directionChangeTimer = self.directionChangeTimer - dt
        if self.groupChangeTimer < 0 and self.directionChangeTimer < 0 then
            self:applyTargetGear()
        end
    else
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
        local forceGearChange = false
        if self.backwardGears or self.forwardGears then
            if self:getUseAutomaticGearShifting() then
                self.autoGearChangeTimer = self.autoGearChangeTimer - dt

                -- the users action to accelerate will always allow shfting
                -- this is just to avoid shifting while vehicle is not moving, but shfting conditions change (attaching tool, lowering/lifting tool etc.)
                if self.vehicle:getIsAutomaticShiftingAllowed() or acceleratorPedal ~= 0 then
                    -- slower than 1,08km/h
                    if math.abs(self.vehicle.lastSpeed) < 0.0003 then
                        local directionChanged = false
                        local trySelectBestGear = false
                        local allowGearOverwritting = false
                        if gearSign < 0 and (self.currentDirection == 1 or self.gear == 0) then
                            self:changeDirection(-1, true)
                            directionChanged = true
                        elseif gearSign > 0 and (self.currentDirection == -1 or self.gear == 0) then
                            self:changeDirection(1, true)
                            directionChanged = true
                        elseif self.lastAcceleratorPedal == 0 and self.idleGearChangeTimer <= 0 then
                            trySelectBestGear = true
                            self.doSecondBestGearSelection = 3
                        elseif self.doSecondBestGearSelection > 0 and self.lastAcceleratorPedal ~= 0 then
                            self.doSecondBestGearSelection = self.doSecondBestGearSelection - 1
                            if self.doSecondBestGearSelection == 0 then
                                -- do another try for the best gear directly after acceleration started
                                -- the selected gear may not be correct due to an active speed limit (when accelerating with cruise control)
                                trySelectBestGear = true
                                allowGearOverwritting = true
                            end
                        end

                        if directionChanged then
                            if self.targetGear ~= self.gear then
                                newGear = self.targetGear
                            end

                            trySelectBestGear = true
                        end

                        if trySelectBestGear then
                            local bestGear, maxFactorGroup = self:getBestStartGear(self.currentGears)
                            if bestGear ~= self.gear or bestGear ~= self.bestGearSelected then
                                newGear = bestGear

                                if bestGear > 1 or allowGearOverwritting then
                                    self.bestGearSelected = bestGear
                                    self.allowGearChangeTimer = 0
                                end
                            end

                            if self:getUseAutomaticGroupShifting() then
                                if maxFactorGroup ~= nil and maxFactorGroup ~= self.activeGearGroupIndex then
                                    self:setGearGroup(maxFactorGroup)
                                end
                            end
                        end
                    else
                        if self.gear ~= 0 then
                            if self.autoGearChangeTimer <= 0 then
                                if math.sign(acceleratorPedal) ~= math.sign(self.currentDirection) then
                                    acceleratorPedal = 0
                                end
                                newGear = self:findGearChangeTargetGearPrediction(self.gear, self.currentGears, self.currentDirection, self.autoGearChangeTimer, acceleratorPedal, dt)

                                if self:getUseAutomaticGroupShifting() then
                                    if self.gearGroups ~= nil then
                                        -- if we are in the highest gear and the maximum rpm range (50rpm threshold) we shift one group up
                                        if self.activeGearGroupIndex < #self.gearGroups then
                                            if math.abs(math.min(self:getLastRealMotorRpm(), self.maxRpm)-self.maxRpm) < 50 then
                                                if self.gear == #self.currentGears then
                                                    -- if in the highest gear we immediately shift up
                                                    local nextRatio = self.gearGroups[self.activeGearGroupIndex + 1].ratio
                                                    if math.sign(self.gearGroups[self.activeGearGroupIndex].ratio) == math.sign(nextRatio) then
                                                        -- only shift up if we got at least 25% of the rpm range with the current set speed limit
                                                        -- we try the same gear in the next group and if this does not work we go down all the gears until we find a valid rpm
                                                        -- important with active cruise control or field work
                                                        for i=self.gear, 1, -1 do
                                                            nextRatio = nextRatio * self.currentGears[i].ratio
                                                            if self:getRequiredRpmAtSpeedLimit(nextRatio) > self.minRpm + (self.maxRpm - self.minRpm) * 0.25 then
                                                                self:shiftGroup(true)
                                                                newGear = i
                                                                break
                                                            end
                                                        end
                                                    end
                                                elseif self.groupType == VehicleMotor.TRANSMISSION_TYPE.POWERSHIFT then
                                                    -- if we are stuck in a gear we wait a few seconds and then shift up
                                                    -- this only applies for power shift groups since we expect a normal group shift with clutch is also not possible like the gear shift
                                                    if math.sign(self.gearGroups[self.activeGearGroupIndex].ratio) == math.sign(self.gearGroups[self.activeGearGroupIndex + 1].ratio) then
                                                        self.gearGroupUpShiftTimer = self.gearGroupUpShiftTimer + dt
                                                        if self.gearGroupUpShiftTimer > self.gearGroupUpShiftTime then
                                                            self.gearGroupUpShiftTimer = 0
                                                            self:shiftGroup(true)
                                                        end
                                                    else
                                                        self.gearGroupUpShiftTimer = 0
                                                    end
                                                end
                                            else
                                                self.gearGroupUpShiftTimer = 0
                                            end
                                        else
                                            self.gearGroupUpShiftTimer = 0
                                        end

                                        -- in case we are in the first gear and below 25% of the rpm and in the group we are we would not have any gear to start we shift a group down
                                        if self.gear == 1 then
                                            if self.lastRealMotorRpm < self.minRpm + (self.maxRpm - self.minRpm) * 0.25 then
                                                local _, maxFactorGroup = self:getBestStartGear(self.currentGears)
                                                if maxFactorGroup < self.activeGearGroupIndex then
                                                    if math.sign(self.gearGroups[maxFactorGroup].ratio) == math.sign(self.gearGroups[self.activeGearGroupIndex].ratio) then
                                                        self:setGearGroup(maxFactorGroup)
                                                    end
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                            newGear = math.min(math.max(newGear, 1), #self.currentGears)
                        end
                    end

                    -- prevent transmission from downshifting when it just upshifted. So at least try the new gear for 3sec, maybe we get the rpm higher
                    self.allowGearChangeTimer = self.allowGearChangeTimer - dt
                    if self.allowGearChangeTimer > 0 and acceleratorPedal * self.currentDirection > 0 then
                        if newGear < self.gear then
                            if self.allowGearChangeDirection ~= math.sign(newGear-self.gear) then
                                --log("prevent from shifting again in the other direction", self.allowGearChangeDirection, newGear, self.gear)
                                newGear = self.gear
                            end
                        end
                    end
                end
            end
        end
        if newGear ~= self.gear or forceGearChange then
            if newGear ~= self.bestGearSelected then
                self.bestGearSelected = -1
            end

            self.targetGear = newGear
            self.previousGear = self.gear
            self.gear = 0
            self.minGearRatio = 0
            self.maxGearRatio = 0
            self.autoGearChangeTimer = self.autoGearChangeTime
            self.gearChangeTimer = self.gearChangeTime
            self.lastGearChangeTime = g_time
            adjAcceleratorPedal = 0

            local directionMultiplier = self.directionChangeUseGear and self.currentDirection or 1
            SpecializationUtil.raiseEvent(self.vehicle, "onGearChanged", self.gear * directionMultiplier, self.targetGear * directionMultiplier, self.gearChangeTimer)

            if self.gearChangeTimer == 0 then
                self.gearChangeTimer = -1
                self.allowGearChangeTimer = 3000
                self.allowGearChangeDirection = math.sign(self.targetGear-self.previousGear)

                self:applyTargetGear()
            end
        end
    end

    if self.gearShiftMode == VehicleMotor.SHIFT_MODE_MANUAL_CLUTCH then
        if self.backwardGears or self.forwardGears then
            local curRatio, tarRatio
            if self.currentGears[self.gear] ~= nil then
                tarRatio = self.currentGears[self.gear].ratio * self:getGearRatioMultiplier()
                curRatio = math.min(self.motorRotSpeed / math.max(self.differentialRotSpeed, 0.00001), 5000)
            end

            local ratio = 0
            if tarRatio ~= nil then
                ratio = MathUtil.lerp(math.abs(tarRatio), math.abs(curRatio), math.min(self.manualClutchValue, 0.9) / 0.9 * 0.5) * math.sign(tarRatio)
            end
            self.minGearRatio, self.maxGearRatio = ratio, ratio

            if self.manualClutchValue == 0 and self.maxGearRatio ~= 0 then
                local factor = (self:getClutchRotSpeed() * 30 / math.pi + 50) / self:getNonClampedMotorRpm()

                if factor < 0.2 then
                    self.stallTimer = self.stallTimer + dt

                    if self.stallTimer > 500 then
                        self.vehicle:stopMotor()
                        self.stallTimer = 0
                    end
                else
                    self.stallTimer = 0
                end
            else
                self.stallTimer = 0
            end
        end
    end

    if self:getUseAutomaticGearShifting() then
        if math.abs(self.vehicle.lastSpeed) > 0.0003 then
            if self.backwardGears or self.forwardGears then
                if (self.currentDirection > 0 and adjAcceleratorPedal < 0) -- driving forwards and braking
                or (self.currentDirection < 0 and adjAcceleratorPedal > 0) then -- driving backwards and braking
                    adjAcceleratorPedal = 0
                    brakePedal = 1
                end
            end
        end
    end

    return adjAcceleratorPedal, brakePedal
end



----------------------------------------------------------------------------------------------------------------------------------------------------------
--
--
--
----------------------------------------------------------------------------------------------------------------------------------------------------------
VehicleMotor.mrManageUpdateStartGear = function(self, gearSign)
    local newGear = self.gear
    local directionChanged = false
    local trySelectBestGear = false
    local allowGearOverwritting = false
    if gearSign < 0 and (self.currentDirection == 1 or self.gear == 0) then
        self:changeDirection(-1, true)
        directionChanged = true
    elseif gearSign > 0 and (self.currentDirection == -1 or self.gear == 0) then
        self:changeDirection(1, true)
        directionChanged = true
    elseif self.lastAcceleratorPedal == 0 and self.idleGearChangeTimer <= 0 then
        trySelectBestGear = true
        self.doSecondBestGearSelection = 3
    elseif self.doSecondBestGearSelection > 0 and self.lastAcceleratorPedal ~= 0 then
        self.doSecondBestGearSelection = self.doSecondBestGearSelection - 1
        if self.doSecondBestGearSelection == 0 then
            -- do another try for the best gear directly after acceleration started
            -- the selected gear may not be correct due to an active speed limit (when accelerating with cruise control)
            trySelectBestGear = true
            allowGearOverwritting = true
        end
    end

    if directionChanged then
        if self.targetGear ~= self.gear then
            newGear = self.targetGear
        end
        trySelectBestGear = true
    end

    if trySelectBestGear then
        local bestGear, maxFactorGroup = self:getBestStartGear(self.currentGears)
        if bestGear ~= self.gear or bestGear ~= self.bestGearSelected then
            newGear = bestGear

            if bestGear > 1 or allowGearOverwritting then
                self.bestGearSelected = bestGear
                self.allowGearChangeTimer = 0
            end
        end

        if self:getUseAutomaticGroupShifting() then
            if maxFactorGroup ~= nil and maxFactorGroup ~= self.activeGearGroupIndex then
                self:setGearGroup(maxFactorGroup)
            end
        end
    end

    return newGear
end


----------------------------------------
20250413
----------------------------------------
VehicleMotor.mrFindGearChangeTargetGearPrediction = function(self, curGear, gears, gearSign, gearChangeTimer, acceleratorPedal)

    local gearFound = false

    local newGear = curGear
    local absAccPedal = math.abs(acceleratorPedal)
    local curRatio = gears[curGear].ratio

    --adjust with acceleratorPedal value
    --accPedal 0 means we want to decelerate = we want high rpm
    local minRpmWanted = self.mrPowerBandMaxRpm
    local maxRpmWanted = self.maxRpm

    if absAccPedal>0 then
        minRpmWanted = MathUtil.lerp(self.minRpm, self.mrPowerBandMinRpm, absAccPedal)
        maxRpmWanted = MathUtil.lerp(self.minRpm*1.4, self.mrPowerBandMaxRpm, absAccPedal)
    end

    local engineRpm = self.motorRotSpeed*30/math.pi

    if engineRpm<(minRpmWanted-50) then
        if curGear>1 then
            --check one gear down
            local newEngineRpm = engineRpm * gears[curGear-1].ratio/curRatio
            if newEngineRpm<maxRpmWanted then
                --check another gear down, just in case
                if curGear>2 then
                    newEngineRpm = engineRpm * gears[curGear-2].ratio/curRatio
                    if newEngineRpm<maxRpmWanted then --and newEngineRpm<minRpmWanted ?
                        newGear = curGear-2
                        gearFound = true
                    end
                end
                if not gearFound then
                    newGear = curGear-1
                    gearFound = true
                end
            elseif self.rawLoadPercentage>0.9 then --engine is too low in rpm and the engine load is high => we really want to gear down
                if newEngineRpm<self.maxRpm then
                    newGear = curGear-1
                    gearFound = true
--                 else
--                     --check power just in case... we really really want to gear down
--                     local currentPowerFx = self.torqueCurve:get(engineRpm)*engineRpm
--                     local newPowerFx = self.torqueCurve:get(newEngineRpm)*newEngineRpm
--                     if newPowerFx>=currentPowerFx then
--                         newGear = curGear-1
--                         gearFound = true
--                     end
                end
            end
        end
--         if not gearFound and self:getUseAutomaticGroupShifting() and self.gearGroups ~= nil and self.rawLoadPercentage>0.9 then --ok, we didn't find any gear down possible, but the engine is still "struggling", maybe we can shift one group down ?
--             if self.activeGearGroupIndex>1 then --at least one group down available ?
--                 --check new power with one gear group down and best gear
--                 local currentPowerFx = self.torqueCurve:get(engineRpm)*engineRpm
--                 for gear=#gears, 1, -1 do
--                     local newEngineRpm = engineRpm * gears[gear].ratio * self.gearGroups[self.activeGearGroupIndex-1].ratio/(curRatio*self.gearGroups[self.activeGearGroupIndex].ratio)
--                     local newPowerFx = self.torqueCurve:get(newEngineRpm)*newEngineRpm
--                     if newPowerFx>=currentPowerFx then
--                         newGear = gear
--                         self:setGearGroup(self.activeGearGroupIndex-1)
--                         break
--                     end
--                 end
--             elseif self.activeGearGroupIndex<#self.gearGroups then --at least one group up available ?
--                 --check new power with one gear group up and best gear
--                 local currentPowerFx = self.torqueCurve:get(engineRpm)*engineRpm
--                 for gear=1, #gears do
--                     local newEngineRpm = engineRpm * gears[gear].ratio * self.gearGroups[self.activeGearGroupIndex+1].ratio/(curRatio*self.gearGroups[self.activeGearGroupIndex].ratio)
--                     local newPowerFx = self.torqueCurve:get(newEngineRpm)*newEngineRpm
--                     if newPowerFx>=currentPowerFx then
--                         newGear = gear
--                         self:setGearGroup(self.activeGearGroupIndex+1)
--                         break
--                     end
--                 end
--             end
--         end
    elseif curGear<#gears and engineRpm>minRpmWanted and absAccPedal>0 then
        --check one gear up

        local newEngineRpm = engineRpm * gears[curGear+1].ratio/curRatio

        --check if this is the last gear
        if curGear==(#gears-1) and self.rawLoadPercentage<0.33 then
            newGear = curGear+1
            gearFound = true
        else
            --only shift gear up when we get more power
            local currentPowerFx = self.torqueCurve:get(engineRpm)*engineRpm
            local newPowerFx = self.torqueCurve:get(newEngineRpm)*newEngineRpm

            if newPowerFx>=currentPowerFx then
                --check another gear up, just in case
                if curGear<(#gears-1) then
                    local ratioComparison = gears[curGear+2].ratio/curRatio
                    if ratioComparison>0.5 then --do not allow shifting several gears up if there is a factor greater than 2 between the current gear and the new gear
                        newEngineRpm = engineRpm * ratioComparison
                        newPowerFx = self.torqueCurve:get(newEngineRpm)*newEngineRpm
                        if newPowerFx>=currentPowerFx then
                            --check again another gear up, just in case
                            if curGear<(#gears-2) then
                                ratioComparison = gears[curGear+3].ratio/curRatio
                                newEngineRpm = engineRpm * ratioComparison
                                if ratioComparison>0.5 then --do not allow shifting several gears up if there is a factor greater than 2 between the current gear and the new gear
                                    newPowerFx = self.torqueCurve:get(newEngineRpm)*newEngineRpm
                                    if newPowerFx>=currentPowerFx then
                                        newGear = curGear+3
                                        gearFound = true
                                    end
                                end
                            end
                            if not gearFound then
                                newGear = curGear+2
                                gearFound = true
                            end
                        end
                    end
                end
                if not gearFound then
                    newGear = curGear+1
                end
            end
        end
    end

    return newGear

end

--*****************************************
--** Hydro transmission automotive
--** adjust engine rpm function of load
--*****************************************
WheelsUtil.mrUpdateWheelsPhysicsHydrostaticAutomotive = function(self, dt, accPedal, maxAcceleration, maxMotorRotAcceleration, clutchForce, neededPtoTorque, minRotForPTO)

    local motor = self.spec_motorized.motor
    local gearDirection = motor.currentDirection
    local targetMaxRot = self.mrTransmissionMaxEngineRotWanted
    local targetMinRot = self.mrTransmissionMinEngineRotWanted
    local targetAvgRot = 0.5*(targetMaxRot+targetMinRot)
    local resetCounter = true

    local maxRatio = 750

    --determined target speed m/s
    local targetSpeed = motor:getMaximumForwardSpeed() --max vehicle speed, or regulator set speed, or working tool max speed

    if math.sign(gearDirection)<0 then
        targetSpeed = motor:getMaximumBackwardSpeed()
    end

    targetSpeed = math.abs(accPedal * targetSpeed)

    --tool speed limit
    targetSpeed = math.min(targetSpeed, motor:getSpeedLimit()/3.6)

    --check current engine rpm and gearRatio
    local lastRatio = motor.mrLastMotorObjectGearRatio
    if lastRatio==0 then
        lastRatio = maxRatio
    end
    local curTheoreticalSpeed = motor.mrLastMotorObjectRotSpeed / lastRatio
    local newGearRatio = lastRatio

    if curTheoreticalSpeed<targetSpeed then
        --not enough speed
        accPedal = 1
        if motor.mrLastMotorObjectRotSpeed<targetAvgRot then
            --not enough rpm = increase gearRatio to get more rpm
            newGearRatio = math.min(maxRatio, lastRatio * (1 + dt/2000))
        elseif motor.mrLastMotorObjectRotSpeed>0.98*targetMaxRot then
            --enough rpm = lower gear ratio, faster and faster
            resetCounter = false
            self.mrTestCounter = self.mrTestCounter + dt

            newGearRatio = lastRatio * math.max(0.1, 1 - 0.01*self.mrTestCounter * dt/1000)
        else
            --wait with same parameters to see if rpm increase ?
        end
    else

    end

    if resetCounter then
        self.mrTestCounter = 0
    end

    self.spec_motorized.mrEngineIsBraking = false
    newGearRatio = newGearRatio * gearDirection
    self:controlVehicle(accPedal, targetSpeed, maxAcceleration, 0, targetMaxRot, maxMotorRotAcceleration, newGearRatio, newGearRatio, clutchForce, neededPtoTorque)
end

---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
--new function to separate code from updateGear
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
VehicleMotor.mrManageUpdateGroup1 = function(self, dt)

    local newGear = 0

    --1: check if we can shift a group up
    local resetGroupTimer = true
    if self.activeGearGroupIndex < #self.gearGroups then
        local lastRpm = self:getLastRealMotorRpm()
        if lastRpm>self.mrPowerBandMaxRpm then
            if math.sign(self.gearGroups[self.activeGearGroupIndex].ratio) == math.sign(self.gearGroups[self.activeGearGroupIndex + 1].ratio) then
                self.gearGroupUpShiftTimer = self.gearGroupUpShiftTimer + dt
                resetGroupTimer = false
                --do not shift right away. Allow gear change first.
                --except if we are already in the last gear = try to "up the group" without delay
                if self.gear == #self.currentGears or self.gearGroupUpShiftTimer > self.gearGroupUpShiftTime then
                    resetGroupTimer = true
                    --check if there is a gear in the new group that allows the engine to rev just under the current rpm
                    local nextGroupRatio = self.gearGroups[self.activeGearGroupIndex + 1].ratio
                    local currentFinalRatio = self.gearGroups[self.activeGearGroupIndex].ratio * self.currentGears[self.gear].ratio
                    for i=1, self.gear do
                        --we want a small difference in final gear ratio between current and target
                        --=> so we choose the first gear that allow a smaller final gear ratio with the new group
                        local checkRatio = nextGroupRatio*self.currentGears[i].ratio/currentFinalRatio
                        if checkRatio<1 then
                            --if checkRatio*lastRpm>self.mrPowerBandMinRpm or (self.gear == #self.currentGears and lastRpm>(self.maxRpm-0.7*self.vehicle.mrGovernorRange)) then --check if there are not too much difference (we don't want to go from C1 to D1 for example with a powerquad)
                            --20250413 - only shift group up if we get more power
                            local engineRpm = self.motorRotSpeed*30/math.pi
                            local newEngineRpm = engineRpm*checkRatio
                            local currentPowerFx = self.torqueCurve:get(engineRpm)*engineRpm
                            local newPowerFx = self.torqueCurve:get(newEngineRpm)*newEngineRpm
                            if newPowerFx>=currentPowerFx then
                                self:shiftGroup(true)
                                newGear = i
                                self.autoGearChangeTimer = self.autoGearChangeTime --we don't want to change group and then, a new gear change occurs without delay
                            end
                            break
                        end
                    end
                end
            end
        end
    end

    if resetGroupTimer then
        self.gearGroupUpShiftTimer = 0
    end

    return newGear

end

Vehicle.mrRegisters = function(_, superFunc)
    Vehicle.xmlSchema:register(XMLValueType.BOOL, "vehicle.MR", "Vehicle converted to MoreRealistic")
    superFunc()
end
Vehicle.registers = Utils.overwrittenFunction(Vehicle.registers, Vehicle.mrRegisters)

Vehicle.mrInit = function(_, superFunc)

    g_storeManager:addSpecType("aaMoreRealistic", nil, Vehicle.mrLoadSpecValueMoreRealistic, Vehicle.mrGetSpecValueIsMrVehicle, StoreSpecies.VEHICLE)

    superFunc()
end
Vehicle.init = Utils.overwrittenFunction(Vehicle.init, Vehicle.mrInit)


Vehicle.mrGetSpecValueIsMrVehicle = function(storeItem, realItem)
    if realItem~=nil then
        if realItem.mrIsMrVehicle then
            return "MR"
        end
    end
    if storeItem.specs.moreRealistic ~= nil then
        if storeItem.specs.moreRealistic then
            return "MR"
        end
    end
    return nil
end


function Vehicle.mrLoadSpecValueMoreRealistic(xmlFile, customEnvironment, baseDir)
    return xmlFile:getValue("vehicle.MR")
end
