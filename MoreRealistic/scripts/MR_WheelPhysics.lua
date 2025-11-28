WheelPhysics.mrNew = function(wheel, superFunc)

    local self = superFunc(wheel)

    self.mrTireGroundRollingResistanceCoeff = 0.01
    self.mrLastTireLoad = 0
    self.mrLastWheelSpeed = 0
    self.mrLastWheelSpeedS = 0
    self.mrLastLongSlip = 0
    self.mrLastLongSlipS = 0
    self.mrLastLatSlip = 0
    self.mrDynamicFrictionScale = 1
    self.mrDynamicFrictionScaleS = 1
    self.mrLastBrakeForce = 0
    self.mrIsDriven = false
    self.mrABS = false
    self.mrTotalWidth = 0
    self.mrFrictionNeedUpdate = true
    self.mrLastRrFx = 0
    self.mrLastContactNormalRatio = 1

    return self

end
WheelPhysics.new = Utils.overwrittenFunction(WheelPhysics.new, WheelPhysics.mrNew)

WheelPhysics.mrRegisterXMLPaths = function(schema, superFunc, key)
    superFunc(schema, key)
    --add mrABS param
    schema:register(XMLValueType.BOOL, key .. ".physics#mrABS", "Prevent locking of the wheel uring braking", false)
    schema:register(XMLValueType.BOOL, key .. ".physics#mrKeepMass", "Prevent replacing xml mass with mr autocompute wheel mass", false)
    schema:register(XMLValueType.FLOAT, key .. ".physics#mrFrictionScale", "Allow to set a given friction scale")
    schema:register(XMLValueType.FLOAT, key .. ".physics#mrForcePointRatio", "Allow to set a given force point ratio")
    schema:register(XMLValueType.FLOAT, key .. ".physics#mrForcePointPositionX", "Allow to force the x position of the forcepoint of the wheelshape")

end
WheelPhysics.registerXMLPaths = Utils.overwrittenFunction(WheelPhysics.registerXMLPaths, WheelPhysics.mrRegisterXMLPaths)


WheelPhysics.mrLoadFromXML = function(self, superFunc, xmlObject)
    --MR : wheels masses are a little bit "off" from Giants.
    --Example : 650/85R38, tyre + rim = 320kg + 180kg = about 530kg IRL (we can verify that by looking at https://shop.deere.com/ , or reading nebraska test reports
    --but base game mass of the whole wheel = 398kg
    --Some wheels are right though : for example, the "narrow" 480/80R50 wheels are set to 409kilos in the game (about 420kilos IRL)
    -- other data sources = https://www.allpneus.com/
    -- Problem = wheels masses are something very important in a tractor simulator, and so, we are trying to get some closer to IRL figures here
    if superFunc(self, xmlObject) then

        --override default "0.3" forcepointratio
--         if self.vehicle.mrIsMrVehicle and self.forcePointRatio>=0.2999 and self.forcePointRatio<=0.3001 then
--             self.forcePointRatio=0.5 --default MR forcePointValue (far from being realistic, we don't want to penalize too much casual players)
--         end


        self.mrForcePointRatio = xmlObject:getValue(".physics#mrForcePointRatio")
        if self.mrForcePointRatio~=nil then
            self.forcePointRatio = self.mrForcePointRatio
        elseif self.vehicle.mrIsMrVehicle and self.radius>=0.2  then
            --we want the force point about 10cm above the ground
            self.forcePointRatio = (self.radius-0.1)/self.radius
        end

        self.mrTotalWidth = self.width

        --add some randomness to the damping value
        self.rotationDamping = (0.5+math.random())*self.rotationDamping --80% to 120% base value

        --load mrABS
        self.mrABS = xmlObject:getValue(".physics#mrABS", false)

        self.mrFrictionScale = xmlObject:getValue(".physics#mrFrictionScale")
        self.mrForcePointPositionX = xmlObject:getValue(".physics#mrForcePointPositionX")

        --check if we override base game mass by self-computed MR mass
        local keepMass = xmlObject:getValue(".physics#mrKeepMass", false)
        if not keepMass then
            --check if we can get a "better" wheel mass
            local rimDimension = xmlObject:getValue(".outerRim#widthAndDiam", nil, true)
            if rimDimension~=nil then
                local category = nil
                if xmlObject.externalXMLFile~=nil then
                    category = xmlObject.externalXMLFile:getValue("wheel.metadata#category", nil, true)
                end
                local rimRadius = 0.5*MathUtil.inchToM(rimDimension[2])
                local newMass = WheelsUtil.mrGetMassFromDimension(self.width, self.radius, rimRadius, category)
                if newMass>0 then
                    self.mass = newMass
                    self.baseMass = self.mass
                end
            end
        end

        return true
    end
    return false
end
WheelPhysics.loadFromXML = Utils.overwrittenFunction(WheelPhysics.loadFromXML, WheelPhysics.mrLoadFromXML)

WheelPhysics.mrLoadAdditionalWheel = function(self, superFunc, xmlObject)
    superFunc(self, xmlObject)
    local xmlMass = xmlObject:getValue(".physics#mass", 0)
    local rimDimension = xmlObject:getValue(".outerRim#widthAndDiam", nil, true)
    local width = xmlObject:getValue(".physics#width", 0)
    local wheelRadius = xmlObject:getValue(".physics#radius", 0)

    if xmlMass>0 and rimDimension~=nil then
        --compute total wheel mass from tire and rim dimension
        local rimRadius = 0.5*MathUtil.inchToM(rimDimension[2])
        local category = nil
        if xmlObject.externalXMLFile~=nil then
            category = xmlObject.externalXMLFile:getValue("wheel.metadata#category", nil, true)
        end
        local newMass = WheelsUtil.mrGetMassFromDimension(width, wheelRadius, rimRadius, category)
        if newMass>0 then
            --1.33 factor because there is some addtionnal parts to attach dual/triple wheels to inner wheels (the rim can be different too)
            self.mass = self.mass - xmlMass + 1.33*newMass
        end
    end

    self.mrTotalWidth = self.mrTotalWidth + width

end
WheelPhysics.loadAdditionalWheel = Utils.overwrittenFunction(WheelPhysics.loadAdditionalWheel, WheelPhysics.mrLoadAdditionalWheel)

WheelPhysics.mrPostUpdate = function(self, dt)
    WheelPhysics.mrUpdateDynamicFriction(self, dt)
end
WheelPhysics.postUpdate = Utils.prependedFunction(WheelPhysics.postUpdate, WheelPhysics.mrPostUpdate)

---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- make use of mrDynamicFrictionScale instead of frictionScale
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
WheelPhysics.mrUpdateTireFriction = function(self, superFunc)
    if self.vehicle.isServer and self.vehicle.isAddedToPhysics then
        --test
--         self.maxLongStiffness = 300
--         self.maxLatStiffness = 5
--         self.maxLatStiffnessLoad = 1
        self.frictionScale = self.mrDynamicFrictionScale --update for debug display only
        self.mrLastFrictionApplied = self.tireGroundFrictionCoeff*self.mrDynamicFrictionScale
        setWheelShapeTireFriction(self.wheel.node, self.wheelShape, self.maxLongStiffness, self.maxLatStiffness, self.maxLatStiffnessLoad, self.tireGroundFrictionCoeff*self.mrDynamicFrictionScale)
        self.isFrictionDirty = false
    end
end
WheelPhysics.updateTireFriction = Utils.overwrittenFunction(WheelPhysics.updateTireFriction, WheelPhysics.mrUpdateTireFriction)

---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- 20250525 - rely on tyre spec and current load now
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
WheelPhysics.mrUpdateDynamicFriction = function(self, dt)

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

            local newDynamicFrictionScale = 1

            --limit "dynamic help" for narrow tires
            --we don't want player to keep narrow tire for every task
            local maxScale = 100*self.mrTotalWidth*self.radius/math.max(0.1, self.mrLastTireLoad)
            maxScale = math.max(0.8, maxScale)

            if maxScale>1 then
                local absSlip = math.abs(self.vehicle.spec_wheels.mrAvgDrivenWheelsSlip)--math.abs(self.mrLastLongSlipS)

                if self.hasSnowContact then
                    newDynamicFrictionScale = 1
                elseif self.mrLastGroundType==WheelsUtil.GROUND_ROAD then
                    if absSlip>=0.3 then
                        newDynamicFrictionScale = 0.9
                    else
                        newDynamicFrictionScale = 2.1-4*absSlip
                    end
                elseif self.mrLastGroundType==WheelsUtil.GROUND_HARD_TERRAIN then
                    if absSlip>=0.3 then
                        newDynamicFrictionScale = 0.9
                    else
                        newDynamicFrictionScale = 1.755-2.85*absSlip
                    end
                elseif self.mrLastGroundType==WheelsUtil.GROUND_SOFT_TERRAIN then
                    if absSlip>=0.5 then
                        newDynamicFrictionScale = 1
                    else
                        newDynamicFrictionScale = 1.6-1.2*absSlip
                    end
                elseif self.mrLastGroundType==WheelsUtil.GROUND_FIELD then
                    if self.mrLastGroundSubType==1 then --firmer ground field (eg: harvest state)
                        if absSlip>=0.5 then
                            newDynamicFrictionScale = 1
                        else
                            newDynamicFrictionScale = 1.4-0.8*absSlip
                        end
                    else --"soft" field
                        if absSlip>=0.5 then
                            newDynamicFrictionScale = 1
                        else
                            newDynamicFrictionScale = 1.1-0.2*absSlip
                        end
                    end
                end
            end

            newDynamicFrictionScale = math.min(newDynamicFrictionScale, maxScale)


            --20250515 - add some more friction when wheels are rotated
            newDynamicFrictionScale = newDynamicFrictionScale * (1+0.3*math.abs(self.steeringAngle))

            --20250701 - add contact normal ratio
            --newDynamicFrictionScale = math.max(self.mrLastContactNormalRatio*newDynamicFrictionScale, minFx)

            self.mrDynamicFrictionScaleS = 0.9*self.mrDynamicFrictionScaleS + 0.1*newDynamicFrictionScale

            if math.abs(self.mrDynamicFrictionScaleS-self.mrDynamicFrictionScale)>0.02 then
                self.mrDynamicFrictionScale = self.mrDynamicFrictionScaleS
                self.isFrictionDirty = true
            end

        end

    else
        --not mrIsDriven
        local wantedFriction = 1.2 * math.clamp(self.vehicle.lastSpeed*67, 1, 1.5) --total factor = x1.8 @80kph
        if math.abs(self.mrDynamicFrictionScale-wantedFriction)>0.1 then
            self.isFrictionDirty = true
            self.mrDynamicFrictionScale = wantedFriction
        end
    end

end


---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- return rolling resistance in KN
-- take into account wetness, tyre width/radius/current load, ground type and sub type
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
WheelPhysics.mrGetRollingResistance = function(self, wheelSpeed, tireLoad, rrCoeff)
    -- rolling resistance = coeff * normal force
    -- simplified model for rr

    --take into account wheel "crushed" under load => more rr if the wheel is "deformed"
    --this is especially relevant on soft ground
    local rrFx = 1
    if self.mrTotalWidth>0 then
        local groundWetness = g_currentMission.environment.weather:getGroundWetness()
        rrFx = WheelPhysics.mrGetRrFx(self.mrTotalWidth, self.radius, self.mrLastTireLoad, self.mrLastGroundType, self.mrLastGroundSubType, groundWetness)
    end
    self.mrLastRrFx = rrFx
    --depend on surface (soft and field)

    --20250514 - only 10% rr at still to avoid strange behavior when tractor is not heavy enough to pull a trailer on hilly road or muddy field => only for not driven wheels
    --full rr @1.782kph
    --at very low speed, we rely on high wheel damping to simulate rolling resistance
    local startFx = 1
    if not self.mrIsDriven then
        startFx = math.min(1, 0.1 + 1.8*math.abs(wheelSpeed))
    end

    return startFx * tireLoad * rrCoeff * rrFx
end



--width and radius in meters, load in KN
--return the ground pressure
-- 1 Kn/m2 = 1000 Pa
-- 1 Bar = 100000 Pa
-- => 1 bar = 100 Kn/m2
WheelPhysics.mrGetPressureFx = function(width, radius, load)
    if load>0 then
        local contactPatch = width*radius*0.53
        if contactPatch>0 then
            return 0.01 * load / contactPatch
        end
    end
    return 0
end


WheelPhysics.mrGetDryFx = function(pressureFx, groundType, groundSubType)
    local fx = 1
    if groundType==WheelsUtil.GROUND_FIELD then
        --loose field ground type
        if groundSubType==0 then
            if pressureFx<=0.6 then
                fx = 0.8
            elseif pressureFx<=1.6 then
                fx = 0.68+pressureFx*0.2 -- fx=1 @1.6 pressure
            else
                fx = 0.6+pressureFx*0.25 -- fx=1.85 @5 pressure
            end
            --20250819 - more rolling resistance on loose field
            fx = fx * 1.25
        else
            --firmer field ground type
            if pressureFx<=1 then
                fx = 0.8
            elseif pressureFx<=2.25 then
                fx = 0.64+pressureFx*0.16 -- fx=1 @2.25 pressure
            else
                fx = 0.55+pressureFx*0.2  -- fx=1.55 @5 pressure
            end
        end
    elseif groundType==WheelsUtil.GROUND_SOFT_TERRAIN then
        if pressureFx<=1.5 then
            fx = 0.8
        elseif pressureFx<=3.1 then
            fx = 0.6125+pressureFx*0.125 -- fx=1 @3.1 pressure
        else
            fx = 0.504+pressureFx*0.16   -- fx=1.304 @5 pressure
        end
    end
    return fx
end

WheelPhysics.mrGetWetFx = function(pressureFx, groundType, groundSubType)
    local fx = 1
    if groundType==WheelsUtil.GROUND_FIELD then
    --loose field ground type
        if groundSubType==0 then
            fx = 0.8+pressureFx*0.25 -- fx=1 @0.8 pressure
            --20250819 - more rolling resistance on loose field
            fx = fx * 1.25
        else
            --firmer field ground type
            fx = 0.8+pressureFx*0.2 -- fx=1 @1 pressure
        end
    elseif groundType==WheelsUtil.GROUND_SOFT_TERRAIN then
        fx = 0.8+pressureFx*0.13   -- fx=1 @1.54 pressure
    end
    return fx
end


WheelPhysics.mrGetRrFx = function(width, radius, load, groundType, groundSubType, wetness)
    local rrFx = 1
    wetness = wetness^0.5
    if groundType==WheelsUtil.GROUND_FIELD or groundType==WheelsUtil.GROUND_SOFT_TERRAIN then
        local pressureFx = WheelPhysics.mrGetPressureFx(width, radius, load)
        --limit max pressure (IRL, there would be no difference between 7bars or 20bars in bad conditions)
        pressureFx = math.min(pressureFx, 7)
        if wetness==0 then
            rrFx = WheelPhysics.mrGetDryFx(pressureFx, groundType, groundSubType)
        elseif wetness==1 then
            rrFx = WheelPhysics.mrGetWetFx(pressureFx, groundType, groundSubType)
        else --in between wetness
            rrFx = (1-wetness) * WheelPhysics.mrGetDryFx(pressureFx, groundType, groundSubType) + wetness * WheelPhysics.mrGetWetFx(pressureFx, groundType, groundSubType)
        end
    end
    return rrFx
end

WheelPhysics.mrUpdatePhysics = function(self, superFunc, brakeForce, torque)
    if self.vehicle.isServer and self.vehicle.isAddedToPhysics then

        local damping = 0.03 * self.mass
        local bForce = 0
        local rrForce = 0
        local engineBrakeForce = 0
        if not self.wheelShapeCreated then
            bForce = brakeForce
        else
            local tireLoad = getWheelShapeContactForce(self.wheel.node, self.wheelShape)
            local wheelSpeed = 0

            if tireLoad==nil then
                tireLoad =0
            end

            if self.hasGroundContact then
                --local wheelWeight =  self.wheel:getMass() * 9.81 --do not take into account direction of the contact normal (not significant compared to the total mass of the vehicle. A great incline on the road = something like 10% IRL => only 5.71 degree)

                --update wheel speed (m/s)
                wheelSpeed = getWheelShapeAxleSpeed(self.wheel.node, self.wheelShape) * self.radius
                wheelSpeed = wheelSpeed or 0 --m/s

                if self.mrIsDriven then
                    --update wheel slip
                    self.mrLastLongSlip, self.mrLastLatSlip = getWheelShapeSlip(self.wheel.node, self.wheelShape)
                    self.mrLastLongSlipS = self.mrLastLongSlipS * 0.9 + self.mrLastLongSlip * 0.1
                    damping = self.mass * (0.03 + 0.07*math.clamp(self.mrLastLongSlipS-0.1, 0, 1)) --more damping when slipping

                    --20250609 - trying to help the differential system to stabilize
                    -- when it goes crazy, we lose a lot of power (Eg : frame1 => wheel left = 50rpm and wheel right = 10rpm // frame2 => wheel left = 10rpm and wheel right = 50rpm // etc, etc,etc)
                    -- best example I could see = MT655 going at 7-8kph with lemken smaragdt (shallow mode) instead of 10-12kph (for no reason, wetness was 0, and 95% of the field was done at the right speed)
                    if wheelSpeed>1 and wheelSpeed>1.5*self.vehicle.spec_wheels.mrAvgDrivenWheelsSpeed then
                        damping = damping * 2
                    end

                    --20250701 - adding getWheelShapeContactNormal to help get better result for dynamicFrictionScale
                    local _,ny,_ = getWheelShapeContactNormal(self.wheel.node, self.wheelShape)
                    if ny~=nil then
                        self.mrLastContactNormalRatio = ny
                    else
                        self.mrLastContactNormalRatio = 1
                    end
                end
                rrForce = WheelPhysics.mrGetRollingResistance(self, wheelSpeed, tireLoad, self.mrTireGroundRollingResistanceCoeff) --20250725 - do not take into account wheelshape weight for rolling resistance
                --tireLoad = tireLoad + wheelWeight
            else
                --no ground contact = "random" damping (see loadFromXML)
                damping = self.rotationDamping
            end
            self.mrLastTireLoad = tireLoad --KN
            self.mrLastWheelSpeedS = 0.9*self.mrLastWheelSpeedS + 0.1*wheelSpeed
            self.mrLastWheelSpeed = wheelSpeed

            if brakeForce>0 and self.brakeFactor>0 then
                bForce = brakeForce * self.brakeFactor
            end

            if self.mrIsDriven and self.vehicle.spec_motorized.mrEngineBrakingPowerToApply>0 then
                if self.mrLastTireLoad>0 and self.vehicle.spec_wheels.mrTotalWeightOnDrivenWheels>0 then
                    --force * speed = power => force = power / speed
                    local engineBrake = self.vehicle.spec_motorized.mrEngineBrakingPowerToApply*self.mrLastTireLoad/self.vehicle.spec_wheels.mrTotalWeightOnDrivenWheels
                    --max engine brake "power" down to 3mph
                    engineBrakeForce = engineBrake/math.max(3, math.abs(wheelSpeed))
                end
            end

        end

        self.mrLastBrakeForce = bForce

        local totalForce = rrForce+bForce+engineBrakeForce

        --limit brakeforce to normal force * friction to avoid blocking wheel => ALB (auto load balance / anti lock brake regulator)
        if self.wheelShapeCreated and (self.mrIsDriven or self.mrABS) then
            if totalForce>self.restLoad then --minimum force = restLoad (10% of restLoad weight since normal (vertical) force = 9.81*restload)
                totalForce = math.min(totalForce, self.mrLastTireLoad*self.tireGroundFrictionCoeff)
                totalForce = math.max(totalForce, self.restLoad)
            end
        end

        --20250601 - increase damping at low speed
        if self.hasGroundContact then
            local lastSpeed = self.vehicle:getLastSpeed() --kph
            if lastSpeed<3 then
                damping = (100-33*lastSpeed)*damping --we want to simulate rolling resistance here since this is not really possible at very low speed with forces
            end
        end


        --brakeForce to force = value * radius (in fact, brakeForce param of this function = brake torque => force * radius = torque)
        self.mrLastBrakeTorque = totalForce*self.radius
        self.mrLastDamping = damping
        setWheelShapeProps(self.wheel.node, self.wheelShape, 0, totalForce*self.radius, self.steeringAngle, damping)

        --brakeForce = 0
        setWheelShapeAutoHoldBrakeForce(self.wheel.node, self.wheelShape, (bForce or 0) * self.autoHoldBrakeFactor) --what for ?

    end
end
WheelPhysics.updatePhysics = Utils.overwrittenFunction(WheelPhysics.updatePhysics, WheelPhysics.mrUpdatePhysics)



WheelPhysics.mrUpdateFriction = function(self, superFunc, dt, groundWetness)

    local lastSpeed = self.vehicle:getLastSpeed() --kph
    if lastSpeed>0.2 or self.mrLastWheelSpeedS>0.1 then
        self.mrFrictionNeedUpdate = true
    end

    if self.mrFrictionNeedUpdate then

        local isOnField = self.densityType ~= FieldGroundType.NONE

        local snowScale = 0
        if self.hasSnowContact then
            groundWetness = 0
            snowScale = 1
        else
            groundWetness = groundWetness^0.5
        end

        local groundType, groundSubType = WheelsUtil.mrGetGroundType(isOnField, self.contact ~= WheelContactType.GROUND, self.groundDepth, self.densityType, self.lastTerrainAttribute)
        local coeff = WheelsUtil.getTireFriction(self.tireType, groundType, groundWetness, snowScale)

        self.mrLastGroundSubType = groundSubType
        self.mrLastGroundType = groundType
        self.mrLastFrictionCoeff = coeff

        self.mrFrictionNeedUpdate = false

        if coeff ~= self.tireGroundFrictionCoeff then
            self.tireGroundFrictionCoeff = coeff
            self.isFrictionDirty = true
            --MR : update rolling resistance coeff too
            self.mrTireGroundRollingResistanceCoeff = WheelsUtil.mrGetTireRollingResistance(self.tireType, groundType, groundWetness, snowScale)
        end

    end

end
WheelPhysics.updateFriction = Utils.overwrittenFunction(WheelPhysics.updateFriction, WheelPhysics.mrUpdateFriction)


---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- 20250725 : wheelshape mass is not taken into account for physics.
-- Example : tractor with frontloader and masses in the rear wheels are tipping the same as the version without masses in the wheels
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
WheelPhysics.mrUpdateBase = function(self, superFunc)
    if self.vehicle.isServer and self.vehicle.isAddedToPhysics then
        local positionX, positionY, positionZ = self.positionX-self.directionX*self.deltaY, self.positionY-self.directionY*self.deltaY, self.positionZ-self.directionZ*self.deltaY

        --#debug if VehicleDebug.state == VehicleDebug.DEBUG_ATTRIBUTES then
        --#debug     local x1, y1, z1 = localToWorld(self.wheel.node, self.positionX, self.positionY, self.positionZ)
        --#debug     local x2, y2, z2 = localToWorld(self.wheel.node, positionX, positionY, positionZ)
        --#debug     drawDebugLine(x1, y1, z1, 1, 0, 0, x2, y2, z2, 0, 1, 0, false)
        --#debug end

        if self.wheelShape == 0 then
            self.wheelShapeCreationFrameIndex = g_updateLoopIndex
            self.wheelShapeCreated = false
        end

        local spring = self.spring
        local damperCompressionLowSpeed = self.damperCompressionLowSpeed
        local damperCompressionHighSpeed = self.damperCompressionHighSpeed
        local damperRelaxationLowSpeed = self.damperRelaxationLowSpeed
        local damperRelaxationHighSpeed = self.damperRelaxationHighSpeed

        if self.dynamicSuspension ~= nil then
            local springMultiplier = MathUtil.lerp(1, self.dynamicSuspension.springLoadMultiplier, self.dynamicSuspension.appliedAlpha)
            local dampingMultiplier = MathUtil.lerp(1, self.dynamicSuspension.dampingLoadMultiplier, self.dynamicSuspension.appliedAlpha)

            spring = spring * springMultiplier
            damperCompressionLowSpeed = damperCompressionLowSpeed * dampingMultiplier
            damperCompressionHighSpeed = damperCompressionHighSpeed * dampingMultiplier
            damperRelaxationLowSpeed = damperRelaxationLowSpeed * dampingMultiplier
            damperRelaxationHighSpeed = damperRelaxationHighSpeed * dampingMultiplier
        end

        local collisionGroup = WheelPhysics.COLLISION_GROUP
        local collisionMask = self.collisionMask or WheelPhysics.COLLISION_MASK
        --MR : greater wheel mass to simulate inertia
        local mass = 2*self.wheel:getMass()
        self.rotationDamping = 2*self.rotationDamping
        self.wheelShape = createWheelShape(self.wheel.node, positionX, positionY, positionZ, self.radius, self.suspTravel, spring, damperCompressionLowSpeed, damperCompressionHighSpeed, self.damperCompressionLowSpeedThreshold, damperRelaxationLowSpeed, damperRelaxationHighSpeed, self.damperRelaxationLowSpeedThreshold, mass, collisionGroup, collisionMask, self.wheelShape)

        local forcePointY = positionY - self.radius * self.forcePointRatio
        local steeringX, steeringY, steeringZ = localToLocal(getParent(self.wheel.repr), self.wheel.node, self.wheel.startPositionX, self.wheel.startPositionY+self.deltaY, self.wheel.startPositionZ)
        setWheelShapeForcePoint(self.wheel.node, self.wheelShape, self.positionX, forcePointY, positionZ)
        setWheelShapeSteeringCenter(self.wheel.node, self.wheelShape, steeringX, steeringY, steeringZ)

        local direction = self.torqueDirection
        setWheelShapeDirection(self.wheel.node, self.wheelShape, self.directionX, self.directionY, self.directionZ, self.axleX * direction, self.axleY * direction, self.axleZ * direction)
        setWheelShapeWidth(self.wheel.node, self.wheelShape, self.wheelShapeWidth, self.wheelShapeWidthOffset)

        setWheelShapeTerrainDisplacement(self.wheel.node, self.wheelShape, self.displacementAllowed and self.displacementScale or 0)

        self.isPositionDirty = false
    end
end
WheelPhysics.updateBase = Utils.overwrittenFunction(WheelPhysics.updateBase, WheelPhysics.mrUpdateBase)

---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- 20250725 : wheelshape mass is not taken into for physics.
-- Example : tractor with frontloader and masses in the rear wheels are tipping the same as the version without masses in the wheels
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
WheelPhysics.mrGetTireLoad = function(self, superFunc)
    --local gravity = 9.81

    local tireLoad = getWheelShapeContactForce(self.wheel.node, self.wheelShape)
    if tireLoad ~= nil then
--         local nx, ny, nz = getWheelShapeContactNormal(self.wheel.node, self.wheelShape)
--         local dx, dy, dz = localDirectionToWorld(self.wheel.node, self.directionX, self.directionY, self.directionZ)
--         tireLoad = -tireLoad * MathUtil.dotProduct(dx, dy, dz, nx, ny, nz)

--         return (tireLoad + math.max(ny * gravity, 0.0) * self.wheel:getMass()) / gravity
        return tireLoad/9.81
    end

    return 0
end
WheelPhysics.getTireLoad = Utils.overwrittenFunction(WheelPhysics.getTireLoad, WheelPhysics.mrGetTireLoad)

---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- 20250825 : better wheelshape forcePoint (x direction, especially visible while cornering with duals)
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
WheelPhysics.mrUpdateBase = function(self, superFunc)

    superFunc(self)

    if self.vehicle.isServer and self.vehicle.isAddedToPhysics then

        local posX = self.positionX
        if self.mrForcePointPositionX~=nil then
            posX = self.mrForcePointPositionX
        else
            if self.positionX>0.1 then
                posX = posX + 0.5*self.wheelShapeWidth --right wheel ?
            elseif self.positionX<-0.1 then
                posX = posX - 0.5*self.wheelShapeWidth --left wheel ?
            end
        end

        local positionY, positionZ = self.positionY-self.directionY*self.deltaY, self.positionZ-self.directionZ*self.deltaY
        local forcePointY = positionY - self.radius * self.forcePointRatio

        setWheelShapeForcePoint(self.wheel.node, self.wheelShape, posX, forcePointY, positionZ)

    end
end
WheelPhysics.updateBase = Utils.overwrittenFunction(WheelPhysics.updateBase, WheelPhysics.mrUpdateBase)