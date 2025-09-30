PowerConsumer.mrLoadMrValues = function(self, xmlFile)

    self.mrPowerConsumerForcePointX = getXMLFloat(xmlFile, "vehicle.mrPowerConsumer#forcePointX")
    self.mrPowerConsumerForcePointY = getXMLFloat(xmlFile, "vehicle.mrPowerConsumer#forcePointY")
    self.mrPowerConsumerForcePointZ = getXMLFloat(xmlFile, "vehicle.mrPowerConsumer#forcePointZ")
    self.mrPowerConsumerCheckPointX = getXMLFloat(xmlFile, "vehicle.mrPowerConsumer#checkPointX")
    self.mrPowerConsumerCheckPointY = getXMLFloat(xmlFile, "vehicle.mrPowerConsumer#checkPointY")
    self.mrPowerConsumerCheckPointZ = getXMLFloat(xmlFile, "vehicle.mrPowerConsumer#checkPointZ")
    self.mrPowerConsumerForcePointWorldY = getXMLFloat(xmlFile, "vehicle.mrPowerConsumer#forcePointWorldY")
    self.mrPowerConsumerCheckPointWorkAreaStartAndHeightOnly = getXMLBool(xmlFile, "vehicle.mrPowerConsumer#checkPointWorkAreaStartAndHeightOnly") or false
    self.mrPowerConsumerPtoForSoilWork = getXMLBool(xmlFile, "vehicle.mrPowerConsumer#ptoForSoilWork") or false
    self.mrPowerConsumerForcePtoRpm = getXMLBool(xmlFile, "vehicle.mrPowerConsumer#forcePtoRpm") or false
    self.mrPowerConsumerVaryWithAnimationAnimName = getXMLString(xmlFile, "vehicle.mrPowerConsumer#varyWithAnimationAnimName")
    self.mrPowerConsumerVaryWithAnimationStartFactor = getXMLFloat(xmlFile, "vehicle.mrPowerConsumer#varyWithAnimationStartFactor")
    self.mrPowerConsumerVaryWithAnimationEndFactor = getXMLFloat(xmlFile, "vehicle.mrPowerConsumer#varyWithAnimationEndFactor")

    self.mrPowerConsumerVaryWithVisibilityNode = nil
    self.mrPowerConsumerVaryWithVisibilityNodeStr = getXMLString(xmlFile, "vehicle.mrPowerConsumer#varyWithVisibilityNode")
    if self.mrPowerConsumerVaryWithVisibilityNodeStr~=nil then
        self.mrPowerConsumerVaryWithVisibilityFactor = getXMLFloat(xmlFile, "vehicle.mrPowerConsumer#varyWithVisibilityFactor") or 1
    end

    self.mrPowerConsumerCheckPointHardDefined = false
    if self.mrPowerConsumerCheckPointX~=nil or self.mrPowerConsumerCheckPointY~=nil or self.mrPowerConsumerCheckPointZ~=nil then
        self.mrPowerConsumerCheckPointHardDefined = true
        self.mrPowerConsumerCheckPointX = self.mrPowerConsumerCheckPointX or 0
        self.mrPowerConsumerCheckPointY = self.mrPowerConsumerCheckPointY or 0
        self.mrPowerConsumerCheckPointZ = self.mrPowerConsumerCheckPointZ or 0
    end

    self.mrPowerConsumerMaxGroundDistanceToApplyDraftForce = getXMLFloat(xmlFile, "vehicle.mrPowerConsumer#maxGroundDistance")

end


PowerConsumer.mrOnLoad = function(self, savegame)

    self.mrLastForce = 0
    self.mrLastNeededPtoPower = 0

    local categories = self.xmlFile:getValue("vehicle.storeData.category")
    self.mrStoreCategory = categories~=nil and categories[1] or "none"

    self.mrPtoPowerFxMin = 0.1
    self.mrPtoPowerFx = 1
    if self.spec_workArea~=nil and self.spec_workArea.forceNode ~= nil and self.mrPowerConsumerPtoForSoilWork then
        self.mrPtoPowerFx = self.mrPtoPowerFxMin
    end

    self.mrPtoCurrentRpm = 0
    self.mrPtoCurrentRpmRatio = 0 --ratio current pto rpm against wanted pto rpm

    if self.mrPowerConsumerVaryWithVisibilityNodeStr~=nil then
        self.mrPowerConsumerVaryWithVisibilityNode = I3DUtil.indexToObject(self.components, self.mrPowerConsumerVaryWithVisibilityNodeStr, self.i3dMappings)
    end

end
PowerConsumer.onLoad = Utils.appendedFunction(PowerConsumer.onLoad, PowerConsumer.mrOnLoad)


PowerConsumer.mrGetForceMultiplier = function(self)
    --MR => if the field is already cultivated or ploughed = less force needed to pull a cultivator or plow or seeder or any ground implement
    --we try to determine the "test" point => 50cm in front of "all work area" ?
    --1. get the center of all working area WorkAreaType
    local multiplier = 1
    local spec = self.spec_workArea
    if spec~=nil then

        --20260706 - check if there is a varying multiplier depending on animation
        if self.mrPowerConsumerVaryWithAnimationAnimName~=nil then
            if self.getAnimationTime~=nil then
                local animTime = self:getAnimationTime(self.mrPowerConsumerVaryWithAnimationAnimName)
                multiplier = MathUtil.lerp(self.mrPowerConsumerVaryWithAnimationStartFactor, self.mrPowerConsumerVaryWithAnimationEndFactor, animTime)
            end
        end

        --20250724 - check if there is a varying multiplier depending on node visibility
        if self.mrPowerConsumerVaryWithVisibilityNode~=nil then
            local visible = getVisibility(self.mrPowerConsumerVaryWithVisibilityNode)
            if visible then
                multiplier = multiplier * self.mrPowerConsumerVaryWithVisibilityFactor
            end
        end

        local wx, wy, wz
        local found = false
        if self.mrPowerConsumerCheckPointHardDefined then
            wx, wy, wz = localToWorld(self.components[1].node, self.mrPowerConsumerCheckPointX, self.mrPowerConsumerCheckPointY, self.mrPowerConsumerCheckPointZ)
            found = true
        else
            local minX, maxX, maxZ = math.huge,-math.huge,-math.huge

            for _, area in pairs(spec.workAreas) do
                if area.type==WorkAreaType.CULTIVATOR or area.type==WorkAreaType.PLOW or area.type==WorkAreaType.SOWINGMACHINE then
                    local x1, _, z1 = localToLocal(area.start, self.components[1].node, 0, 0, 0)
                    local x3, _, z3 = localToLocal(area.height, self.components[1].node, 0, 0, 0)
                    if self.mrPowerConsumerCheckPointWorkAreaStartAndHeightOnly then
                        minX = math.min(minX,x1,x3)
                        maxX = math.max(maxX,x1,x3)
                        maxZ = math.max(maxZ,z1,z3)
                    else
                        local x2, _, z2 = localToLocal(area.width, self.components[1].node, 0, 0, 0)
                        minX = math.min(minX,x1,x2,x3)
                        maxX = math.max(maxX,x1,x2,x3)
                        maxZ = math.max(maxZ,z1,z2,z3)
                    end
                    found = true
                end
            end
            if found then
                wx, wy, wz = localToWorld(self.components[1].node,0.5*(minX+maxX),0,maxZ+0.6)
            end
        end
        if found then
            local mission = g_currentMission
            local groundTypeMapId, groundTypeFirstChannel, groundTypeNumChannels = mission.fieldGroundSystem:getDensityMapData(FieldDensityMap.GROUND_TYPE)
            local densityBits = getDensityAtWorldPos(groundTypeMapId, wx, wy, wz)
            local densityType = bitAND(bitShiftRight(densityBits, groundTypeFirstChannel), 2^groundTypeNumChannels - 1)
            local groundType = FieldGroundType.getTypeByValue(densityType)

            if groundType==FieldGroundType.CULTIVATED or groundType==FieldGroundType.STUBBLE_TILLAGE or groundType==FieldGroundType.PLOWED or groundType==FieldGroundType.SOWN or groundType==FieldGroundType.DIRECT_SOWN or groundType==FieldGroundType.PLANTED or groundType==FieldGroundType.RIDGE or groundType==FieldGroundType.RIDGE_SOWN or groundType==FieldGroundType.SEEDBED then
                --multiplier = multiplier * 0.7 -- 30% less force needed to cultivate/sow/plow over already cultivated/sown/plowed land

                --20250727 - depend on the type of the tool
                multiplier = multiplier * PowerConsumer.mrGetAlreadyWorkedDraftForceMultiplier(self.mrStoreCategory)
            end

            if (VehicleDebug.state == VehicleDebug.DEBUG_PHYSICS or VehicleDebug.state == VehicleDebug.DEBUG_TUNING) and self.isActiveForInputIgnoreSelectionIgnoreAI then
                --display check position
                local dirX, dirY, dirZ = localDirectionToWorld(self.components[1].node, 0, 0, 1)
                local upX, upY, upZ = localDirectionToWorld(self.components[1].node, 0,1,0)
                DebugGizmo.renderAtPosition(wx, wy, wz, dirX, dirY, dirZ, upX, upY, upZ, "Check Point", false, 0.7)
            end

        end
    end

    return multiplier
end


--MR : at very low speed = using force dir node
-- then, apply force against the moving direction
PowerConsumer.mrOnUpdate = function(self, superFunc, dt, isActiveForInput, isActiveForInputIgnoreSelection, isSelected)

    --reset mrPtoPowerFx
    if self.mrPowerConsumerPtoForSoilWork then
        self.mrPtoPowerFx = self.mrPtoPowerFxMin --10% at idle
    else
        self.mrPtoPowerFx = 1
    end

    if self.isActive then
        local spec = self.spec_powerConsumer

        if spec.forceNode ~= nil and self.movingDirection~=0 and self.lastSpeedReal > 0.0001 then --0.36kph

            local vx, vy, vz = getLinearVelocity(spec.forceNode)
            local spd2d = MathUtil.vector2Length(vx,vz)

            if spd2d>0.1 then --0.36kph

                local multiplier = self:getPowerMultiplier()
                if multiplier == 0 then
                    --reset force
                    self.mrLastForce = 0
                else

                    --check distance to ground ?
                    if self.mrPowerConsumerMaxGroundDistanceToApplyDraftForce~=nil then
                        local x,y,z = getWorldTranslation(spec.forceNode)
                        local terrainHeight = getTerrainHeightAtWorldPos(g_terrainNode, x,y,z)
                        local distance = y - terrainHeight
                        if distance>self.mrPowerConsumerMaxGroundDistanceToApplyDraftForce then
                            return
                        end
                    end

                    local maxForce = spec.maxForce

                    --MR : max force dependant of speed and tool
                    local groundWetness = g_currentMission.environment.weather:getGroundWetness()
                    maxForce = maxForce*PowerConsumer.mrGetDraftForceMultiplier(self.mrStoreCategory, self.lastSpeedReal*3600, groundWetness, self.mrPtoCurrentRpmRatio)
                    local forceMultiplier = PowerConsumer.mrGetForceMultiplier(self)
                    maxForce = maxForce*forceMultiplier

                    --update pto power factor


                    if spec.ptoRpm>0.001 then
                        self.mrPtoPowerFx = PowerConsumer.mrGetPtoPowerMultiplier(self, self.mrStoreCategory, self.lastSpeedReal*3600, groundWetness, forceMultiplier)
                    end

                    local frictionForce = spec.forceFactor * spd2d * self:getTotalMass(false) / (dt/1000)
                    local force = math.min(frictionForce, maxForce) * multiplier

                    --MR = apply force when going in reverse too, even if the tool is not effectively "working"
                    if self.movingDirection ~= spec.forceDir then
                        force = 0.7*force
                    end

                    --MR = 2s to get max force
                    if self.mrLastForce~=force then
                        force = math.min(force, self.mrLastForce + force*dt/500)
                        self.mrLastForce = force
                    end

                    --MR : do not apply force always in the tool z direction : ground force should follow the traction direction like IRL
                    --local dx,dy,dz = localDirectionToWorld(spec.forceDirNode, 0, 0, force)

                    local px,py,pz = getCenterOfMass(spec.forceNode)
                    if self.mrPowerConsumerForcePointX~=nil then
                        px = self.mrPowerConsumerForcePointX
                    end
                    if self.mrPowerConsumerForcePointY~=nil then
                        py = self.mrPowerConsumerForcePointY
                    end
                    if self.mrPowerConsumerForcePointZ~=nil then
                        pz = self.mrPowerConsumerForcePointZ
                    end
                    if self.mrPowerConsumerForcePointWorldY~=nil then
                        local x1, y1, z1 = worldDirectionToLocal(spec.forceNode, 0, self.mrPowerConsumerForcePointWorldY, 0)
                        px = px+x1
                        py = py+y1
                        pz = pz+z1
                    end

                    if spd2d>0.5 then --1.8kph
                        local forceNodeSpd = MathUtil.vector3Length(vx,vy,vz)
                        addForce(spec.forceNode, -force*vx/forceNodeSpd,-force*vy/forceNodeSpd,-force*vz/forceNodeSpd, px,py,pz, true)
                    else
                        local dx,dy,dz = localDirectionToWorld(spec.forceDirNode, 0, 0, -force*self.movingDirection)
                        addForce(spec.forceNode, dx,dy,dz, px,py,pz, true)
                    end

                    if (VehicleDebug.state == VehicleDebug.DEBUG_PHYSICS or VehicleDebug.state == VehicleDebug.DEBUG_TUNING) and self.isActiveForInputIgnoreSelectionIgnoreAI then
                        local str = string.format("frictionForce=%.2f maxForce=%.2f -> force=%.2f", frictionForce, maxForce, force)
                        renderText(0.7, 0.85, getCorrectTextSize(0.02), str)
                        --MR : display force point position
                        local x, y, z = localToWorld(spec.forceNode, px,py,pz)
                        local dirX, dirY, dirZ = localDirectionToWorld(spec.forceDirNode, 0, 0, 1)
                        local upX, upY, upZ = localDirectionToWorld(spec.forceDirNode, 0,1,0)
                        DebugGizmo.renderAtPosition(x, y, z, dirX, dirY, dirZ, upX, upY, upZ, "Force Point", false, 0.7)
                    end
                end
            end
        end

        if spec.turnOnPeakPowerTimer > 0 then
            spec.turnOnPeakPowerTimer = spec.turnOnPeakPowerTimer - dt
        end

    end

end
PowerConsumer.onUpdate = Utils.overwrittenFunction(PowerConsumer.onUpdate, PowerConsumer.mrOnUpdate)

--speedLimitModifier = not realistic at all
PowerConsumer.getRawSpeedLimit = function(self, superFunc)
    local rawSpeedLimit = superFunc(self)

--     local spec = self.spec_powerConsumer
--     for i = #spec.speedLimitModifier, 1, -1 do
--         local modifier = spec.speedLimitModifier[i]
--         if spec.sourceMotorPeakPower >= modifier.minPowerKw and spec.sourceMotorPeakPower <= modifier.maxPowerKw then
--             return rawSpeedLimit + modifier.offset
--         end
--     end

    return rawSpeedLimit
end

--toolCategory = "storeData.category" value
--speed = kilometers per hour
PowerConsumer.mrGetDraftForceMultiplier = function(toolCategory, speed, wetness, rpmFactor)

    --help to get the base force for chisel cultivators = 38*(width/6)^0.95
    --help to get the base force for disc cultivator = 100 * (width/18.4)^0.85
    --help to get the base force for power harrow = 4 * width
    --help to get the base force for plough = 10 * width

    local multiplier = 1

    if toolCategory=="plows" then --curve for plows
        if speed<2 then
            multiplier = 0.8
        else
            multiplier = 0.7336+0.0333*speed --high horse power needed to go fast
        end
        --no malus with wetness for plough draftforce
    elseif toolCategory=="cultivators" then
        --curve for tine cultivators, 8kph = x1
        if speed<8 then
            multiplier = 0.8+0.025*speed --50% more speed = 7% more draft
        elseif speed<12 then
            multiplier = 0.6+0.05*speed --50% more speed = 20% more draft
        else
            multiplier = 0.48+0.06*speed --50% more speed = 30% more draft
        end
        --penalty with wetness for cultivators
        multiplier = multiplier * (1 + 0.25*wetness)
    elseif toolCategory=="discHarrows" then
        --curve for disc cultivators
        if speed<12 then
            multiplier = 0.9+0.0084*speed
        else
            multiplier = 0.7008+0.025*speed
        end
        --"quick" penalty with wetness for disc harrows
        multiplier = multiplier * (1 + wetness)
    elseif toolCategory=="powerHarrows" then
        --curve for power harrows
        if speed<10 then
            multiplier = 0.65+0.04*speed
        else
            multiplier = 1.05*(speed/10)^2
        end
        --penalty with wetness for powerHarrows
        multiplier = multiplier * (1 + 0.3*wetness)
        --should take into account rpm (low rpm = more draftforce), otherwise, player could unclutch going downhill to get more speed
        if rpmFactor~=nil then
            multiplier = multiplier * 1/math.max(0.3, rpmFactor) --1.2 more rpm = 83% draft // 0.8 rpm = 25% more draft
        end
    elseif toolCategory=="seeders" then
        --curve for seeders
        if speed<10 then
            multiplier = 0.9+0.01*speed
        else
            multiplier = 0.7+0.03*speed
        end
        --penalty with wetness for seeders
        multiplier = multiplier * (1 + 0.3*wetness)
    elseif toolCategory=="planters" then
        --curve for planters
        if speed<8 then
            multiplier = 0.92+0.01*speed
        else
            multiplier = 0.76+0.03*speed
        end
        --penalty with wetness for planters
        multiplier = multiplier * (1 + 0.2*wetness)
    elseif toolCategory=="subsoilers" then
        --curve for sub soilers, 8kph = x1
        if speed<8 then
            multiplier = 0.8+0.025*speed --50% more speed = 7% more draft
        elseif speed<12 then
            multiplier = 0.52+0.06*speed --50% more speed = 24% more draft
        else
            multiplier = 0.34+0.075*speed --50% more speed = 36% more draft
        end
        --penalty with wetness for sub soilers
        multiplier = multiplier * (1 + 0.175*wetness)
    elseif toolCategory=="spaders" then
        --curve for spaders
        if speed<7 then
            multiplier = 0.65+0.05*speed
        else
            multiplier = (speed/7)^2 --even at high rpm, the spader is not rotating fast enough to work the ground at these speeds = lot of draftforce to push unworked ground)
        end
        --no penalty with wetness for spaders
        --should take into account rpm (low rpm = more draftforce), otherwise, player could unclutch going downhill to get more speed
        if rpmFactor~=nil then
            multiplier = multiplier * 1/math.max(0.3, rpmFactor) --1.2 more rpm = 83% draft // 0.8 rpm = 25% more draft
        end
    end

    --at very low speed = more force needed (we don't want smaller tractor to be able to pull at very low speed heavy implements)
    if speed<3 then
        --25% more at 0kph, 0% at 3kph
        multiplier = multiplier * (1.249-speed*0.083)
    end

    --other
    return multiplier

end


---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
--
--toolCategory = "storeData.category" value
--speed = kilometers per hour
--wetness = 0 to 1
--currentGroundForceMultiplier = 0 to 1 (if there is a force multiplier applied to the draftforce => example : ground already cultivated or ploughed = less force needed)
--currentPtoRatio = 0 to 1.X (current pto rpm against wanted pto rpm)
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
PowerConsumer.mrGetPtoPowerMultiplier = function(self, toolCategory, speed, wetness, currentGroundForceMultiplier, currentPtoRatio)

    local multiplier = 1

    --take into account rpm ? problem = we can cheat by shifting up a gear or 2 => lower rpm = lower power since the torque is the same (=> more speed even if we lug the engine)
    -- IRL = the quality of the work would no be the same and less rpm = more "chunks" of ground to work at each rotation when driving at the same speed = more torque at the pto

    if toolCategory=="spaders" then
--         multiplier = 0.2+0.1333*speed --x1 @8kph
--         multiplier = multiplier * currentGroundForceMultiplier
--
--         multiplier = multiplier * (1/math.clamp(self.mrPtoCurrentRpmRatio, 0.75, 1.2))^1.25
        if speed<6 then
            multiplier = 0.5+0.085*speed
        else
            multiplier = 1.01
        end
        multiplier = multiplier / math.clamp(self.mrPtoCurrentRpmRatio, 0.75, 1.2)
        multiplier = multiplier * currentGroundForceMultiplier
        --no malus with wetness for spaders
    elseif toolCategory=="powerHarrows" then
        --curve for power harrows
        if speed<6 then
            multiplier = 0.5+0.085*speed
        else
            multiplier = 1.01
        end
        multiplier = multiplier / math.clamp(self.mrPtoCurrentRpmRatio, 0.75, 1.2)
        multiplier = multiplier * currentGroundForceMultiplier
        --no malus with wetness for power harrows
    end

    --other
    return multiplier

end


---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
--
--toolCategory = "storeData.category" value
--speed = kilometers per hour
--wetness = 0 to 1
--currentGroundForceMultiplier = 0 to 1 (if there is a force multiplier applied to the draftforce => example : ground already cultivated or ploughed = less force needed)
--currentPtoRatio = 0 to 1.X (current pto rpm against wanted pto rpm)
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
PowerConsumer.mrGetAlreadyWorkedDraftForceMultiplier = function(toolCategory)

    local multiplier = 0.7

    if toolCategory=="seeders" then
        multiplier = 0.45
    elseif toolCategory=="planters" then
        multiplier = 0.55
    elseif toolCategory=="powerHarrows" then
        multiplier = 0.85
    elseif toolCategory=="spaders" then
        multiplier = 0.75
    end

    return multiplier

end


PowerConsumer.mrGetConsumedPtoTorque = function(self, superFunc, expected, ignoreTurnOnPeak)
    if self:getDoConsumePtoPower() or (expected ~= nil and expected) then
        local spec = self.spec_powerConsumer

        local rpm = spec.ptoRpm
        if rpm > 0.001 then

            local consumingLoad, count = self:getConsumingLoad()
            if count > 0 then
                consumingLoad = consumingLoad / count
            else
                consumingLoad = 1
            end

            local turnOnPeakPowerMultiplier = 1
            if ignoreTurnOnPeak == false then
                turnOnPeakPowerMultiplier = math.max(math.max(math.min(spec.turnOnPeakPowerTimer / spec.turnOnPeakPowerDuration, 1), 0) * spec.turnOnPeakPowerMultiplier, 1)
            end

            local neededPtoPower = 0
            if self.mrIsMrCombine then--mr combine
                neededPtoPower = Combine.mrGetActiveConsumedPtoPower(self)
            else
                local minPower = self.mrPtoPowerFx * spec.neededMinPtoPower
                neededPtoPower = minPower + consumingLoad * (spec.neededMaxPtoPower - spec.neededMinPtoPower)
            end

            --20250618 - add wood crusher
            if self.mrWoodCrusherPowerConsumption~=nil then
                neededPtoPower = neededPtoPower + self.mrWoodCrusherPowerConsumption
            end

            if neededPtoPower>1 and self:getDoConsumePtoPower() then
                --update current pto rpm
                local rootVehicle = self.rootVehicle
                if rootVehicle ~= nil and rootVehicle.getMotor ~= nil then
                    local rootMotor = rootVehicle:getMotor()
                    self.mrPtoCurrentRpm = rootMotor:getNonClampedMotorRpm()/rootMotor.ptoMotorRpmRatio
                    self.mrPtoCurrentRpmRatio = self.mrPtoCurrentRpm / rpm
                    if self.mrPowerConsumerForcePtoRpm then
                        rootVehicle.mrForcePtoRpm = true --tell the motorized vehicle to keep the pto rpm high, even at still/idle
                    end
                end
            end

            --MR = 2s to reach power needed
            if self.mrLastNeededPtoPower~=neededPtoPower then
                neededPtoPower = math.min(neededPtoPower, self.mrLastNeededPtoPower + neededPtoPower*g_physicsDtLastValidNonInterpolated/500)
                self.mrLastNeededPtoPower = neededPtoPower
            end

            return neededPtoPower / (rpm*math.pi/30), spec.virtualPowerMultiplicator * turnOnPeakPowerMultiplier
        end
    else
        --not turned on
        self.mrPtoCurrentRpm = 0
        self.mrPtoCurrentRpmRatio = 0
    end

    self.mrLastNeededPtoPower = 0
    self.mrCombineSpeedLimit = 999 --reset speed limit for combine

    return 0, 1
end
PowerConsumer.getConsumedPtoTorque = Utils.overwrittenFunction(PowerConsumer.getConsumedPtoTorque, PowerConsumer.mrGetConsumedPtoTorque)



