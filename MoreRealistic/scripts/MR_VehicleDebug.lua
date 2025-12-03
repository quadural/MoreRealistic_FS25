VehicleDebug.mrDrawBaseDebugRendering = function(self, superFunc, x, y)

    --Fix BUG when selectin a bigbag attached to a frontloader attachment
    local tempSpec = self.spec_attachable
    if self.spec_attachable~=nil and self.getBrakeForce==nil then
        self.spec_attachable=nil
    end
    local ret = superFunc(self, x, y)
    self.spec_attachable = tempSpec

    local textSize = getCorrectTextSize(0.02)

    if self.spec_motorized then

        if not VehicleDebug.mrDebugChronoInitialized then
            VehicleDebug.mrDebugChrono1State=0
            VehicleDebug.mrDebugChrono2State=1
            VehicleDebug.mrDebugChrono1Time=0
            VehicleDebug.mrDebugChrono2Time=0
            VehicleDebug.mrDebugChrono1Timer=0
            VehicleDebug.mrDebugChrono2Timer=0
            VehicleDebug.mrDebugChronoInitialized = true
        end

        if self.spec_drivable.axisForward == 1 then
            VehicleDebug.mrDebugChrono1State = 1
            VehicleDebug.mrDebugChrono1Time = 0
            if VehicleDebug.mrDebugChrono2State==1 then
                VehicleDebug.mrDebugChrono2State=2
                VehicleDebug.mrDebugChrono2Time = 0
                VehicleDebug.mrDebugChrono2Timer = g_time
            end
            VehicleDebug.mrDebugChrono2Time = g_time - VehicleDebug.mrDebugChrono2Timer
        elseif VehicleDebug.mrDebugChrono2State==2 then
            VehicleDebug.mrDebugChrono2State=0
        end
        --display time and distance when acc is released and we reach 0 speed (braking time or engine brakingtime)
        if self.spec_drivable.axisForward==0 then
            VehicleDebug.mrDebugChrono2State = 1
            if VehicleDebug.mrDebugChrono1State==1 then
                --start counting
                VehicleDebug.mrDebugChrono1State = 2
                VehicleDebug.mrDebugChrono1Timer = g_time
            end
        end

        if VehicleDebug.mrDebugChrono1State==2 then
            VehicleDebug.mrDebugChrono1Time = g_time - VehicleDebug.mrDebugChrono1Timer
        end

        if self.lastSpeedReal<0.0001 then
            VehicleDebug.mrDebugChrono1State=0
            VehicleDebug.mrDebugChrono2State=1
        end

        --display time and distance after acc is fully depressed and then released
        local str1 = "Braking time:\n"
        local str2 = string.format("%1.2fs\n", (VehicleDebug.mrDebugChrono1Time or 0)/1000)

        str1 = str1.."Acc time:\n"
        str2 = str2..string.format("%1.2fs\n", (VehicleDebug.mrDebugChrono2Time or 0)/1000)

        Utils.renderMultiColumnText(0.65, 0.70, textSize, {str1,str2}, 0.008, {RenderText.ALIGN_RIGHT,RenderText.ALIGN_LEFT})


        --20250603 - display acc pedal / brake pedal
        --20241230 - display slip smoothed (vanilla slip is illegible, change too often)
        --20241230 - display dynamic mass on the wheels

        local totalDynamicMass = 0
        local totalWheelsSpeed = 0
        local nbWheels = 0
        if self.spec_wheels ~= nil then
            for i, wheel in ipairs(self.spec_wheels.wheels) do
                totalDynamicMass = totalDynamicMass + wheel.physics.mrLastTireLoad/9.81 --KN to metric tons
                totalWheelsSpeed = totalWheelsSpeed + wheel.physics.mrLastWheelSpeed --m/s
                nbWheels = nbWheels + 1
            end
        end

--         local slip = 0
--         local lastSpeedReal = self.lastSpeedReal * 1000 --m/s
--         if nbWheels>0 and lastSpeedReal > 0.01 then
--             slip = (math.abs(totalWheelsSpeed)/nbWheels)/lastSpeedReal - 1
--         end
--         self.mrSlipSmoothed = self.mrSlipSmoothed==nil and 0 or (0.99*self.mrSlipSmoothed + slip) --0.01*slip*100

        local str3 = "Acc pedal:\nBrake pedal:\nEngine braking:\nSlipS:\nDyn Mass:\nSlope:\n"

        local accPedal = self.wheelsUtilSmoothedAcceleratorPedal or 0
        local brakePedal = self.wheelsUtilSmoothedBrakePedal or 0



        local posX1, posY1, posZ1 = localToWorld(self.components[1].node, 0, 0, 2) --5m in front component 0
        local y1 = getTerrainHeightAtWorldPos(g_terrainNode, posX1, posY1, posZ1)
        local posX2, posY2, posZ2 = localToWorld(self.components[1].node, 0, 0, -2) --5m behind component 0
        local y2 = getTerrainHeightAtWorldPos(g_terrainNode, posX2, posY2, posZ2)

        local horizontalDist = MathUtil.vector2Length(posX2-posX1, posZ2-posZ1)
        local verticalDist = y1-y2
        local slopePercent = 0
        if horizontalDist>0 then
            slopePercent = 100 * verticalDist / horizontalDist
        end

        local str4 = string.format("%1.2f\n", accPedal) .. string.format("%1.2f\n", brakePedal) .. string.format("%s\n",self.spec_motorized.mrLastEngineIsBraking) .. string.format("%1.1f%%\n", 100*self.spec_wheels.mrAvgDrivenWheelsSlip) .. string.format("%1.1fT\n", totalDynamicMass) .. string.format("%1.1f%%\n", slopePercent)
        Utils.renderMultiColumnText(0.17, 0.574, textSize, {str3,str4}, 0.008, {RenderText.ALIGN_RIGHT,RenderText.ALIGN_LEFT})

        --20250222 - display fuel liter per hour smoothed
        self.spec_motorized.mrLastFuelUsageS = 0.99*self.spec_motorized.mrLastFuelUsageS + 0.01*self.spec_motorized.lastFuelUsage
        setTextAlignment(RenderText.ALIGN_LEFT)
        renderText(0.45, 0.562, textSize, string.format("%1.1f",self.spec_motorized.mrLastFuelUsageS))

        --20250318 - display "true" engine object current rotation speed
        setTextAlignment(RenderText.ALIGN_LEFT)
        renderText(0.45, 0.6, textSize, string.format("%1.0f", self.spec_motorized.motor.mrLastMotorObjectRotSpeed*9.5493))

    end

    --20250331 - display combine auto speed limit
    if self.mrIsMrCombine then
        setTextAlignment(RenderText.ALIGN_LEFT)
        renderText(0.8, 0.5, textSize, string.format("Spd=%1.2f", self.mrCombineSpeedLimit))
        renderText(0.8, 0.52, textSize, string.format("T/h=%1.2f", self.mrCombineLastTonsPerHour))
    end

    if self.spec_woodCrusher then
        --20250619 - display woodcrusher power consumption
        if self.mrWoodCrusherPowerConsumption~=nil then
            setTextAlignment(RenderText.ALIGN_LEFT)
            renderText(0.8, 0.7, textSize, string.format("WoodCrusher KW=%1.2f", self.mrWoodCrusherPowerConsumption))
        end
    end

    return ret

end
VehicleDebug.drawBaseDebugRendering = Utils.overwrittenFunction(VehicleDebug.drawBaseDebugRendering, VehicleDebug.mrDrawBaseDebugRendering)



---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- 20250725 : wheelshape mass is not taken into for physics.
-- Example : tractor with frontloader and masses in the rear wheels are tipping the same as the version without masses in the wheels
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
VehicleDebug.mrConsoleCommandAnalyze = function(unusedSelf, superFunc)
    if g_currentMission ~= nil and g_localPlayer:getCurrentVehicle() ~= nil and g_localPlayer:getCurrentVehicle().isServer then

        local self = g_localPlayer:getCurrentVehicle():getSelectedVehicle()
        if self == nil then
            self = g_localPlayer:getCurrentVehicle()
        end

        print("Analyzing vehicle '"..self.configFileName.."'. Make sure vehicle is standing on a flat plane parallel to xz-plane")

        local groundRaycastResult = {
            raycastCallback = function (self, transformId, x, y, z, distance, nx, ny, nz)
                if self.vehicle.vehicleNodes[transformId] ~= nil then
                    return true
                end
                if self.vehicle.aiTrafficCollisionTrigger == transformId then
                    return true
                end

                if transformId ~= g_terrainNode then
                    printWarning("Warning: Vehicle is not standing on ground! " .. getName(transformId))
                end

                self.groundDistance = distance
                return false
            end
        }
        if self.spec_attacherJoints ~= nil then
            for i, attacherJoint in ipairs(self.spec_attacherJoints.attacherJoints) do
                local trx, try, trz = getRotation(attacherJoint.jointTransform)
                setRotation(attacherJoint.jointTransform, unpack(attacherJoint.jointOrigRot))
                if attacherJoint.rotationNode ~= nil or attacherJoint.rotationNode2 ~= nil then
                    local rx,ry,rz
                    if attacherJoint.rotationNode ~= nil then
                        rx,ry,rz = getRotation(attacherJoint.rotationNode)
                    end
                    local rx2,ry2,rz2
                    if attacherJoint.rotationNode2 ~= nil then
                        rx2,ry2,rz2 = getRotation(attacherJoint.rotationNode2)
                    end

                    -- test max rot
                    if attacherJoint.rotationNode ~= nil then
                        setRotation(attacherJoint.rotationNode, unpack(attacherJoint.lowerRotation))
                    end
                    if attacherJoint.rotationNode2 ~= nil then
                        setRotation(attacherJoint.rotationNode2, unpack(attacherJoint.lowerRotation2))
                    end
                    local x,y,z = getWorldTranslation(attacherJoint.jointTransform)
                    groundRaycastResult.groundDistance = 0
                    groundRaycastResult.vehicle = self
                    raycastAll(x, y, z, 0, -1, 0, 4, "raycastCallback", groundRaycastResult, 0xFFFF_FFFF)
                    if math.abs(groundRaycastResult.groundDistance - attacherJoint.lowerDistanceToGround) > 0.01 then
                        print(string.format(" Issue found: Attacher joint %d has invalid lowerDistanceToGround. True value is: %.3f (Value in xml: %.3f)", i, MathUtil.round(groundRaycastResult.groundDistance, 3), attacherJoint.lowerDistanceToGround))
                    end
                    if attacherJoint.rotationNode ~= nil and attacherJoint.rotationNode2 ~= nil then
                        local _,dy,_ = localDirectionToWorld(attacherJoint.jointTransform, 0, 1, 0)
                        local angle = math.deg(math.acos(math.clamp(dy, -1, 1)))
                        local _,dxy,_ = localDirectionToWorld(attacherJoint.jointTransform, 1, 0, 0)
                        if dxy < 0 then
                            angle = -angle
                        end
                        if math.abs(angle-math.deg(attacherJoint.lowerRotationOffset)) > 0.1 then
                            print(string.format(" Issue found: Attacher joint %d has invalid lowerRotationOffset. True value is: %.2f° (Value in xml: %.2f°)", i, angle, math.deg(attacherJoint.lowerRotationOffset)))
                        end
                    end

                    -- test min rot
                    if attacherJoint.rotationNode ~= nil then
                        setRotation(attacherJoint.rotationNode, unpack(attacherJoint.upperRotation))
                    end
                    if attacherJoint.rotationNode2 ~= nil then
                        setRotation(attacherJoint.rotationNode2, unpack(attacherJoint.upperRotation2))
                    end
                    x,y,z = getWorldTranslation(attacherJoint.jointTransform)
                    groundRaycastResult.groundDistance = 0
                    raycastAll(x, y, z, 0, -1, 0, 4, "raycastCallback", groundRaycastResult, 0xFFFF_FFFF)
                    if math.abs(groundRaycastResult.groundDistance - attacherJoint.upperDistanceToGround) > 0.01 then
                        print(string.format(" Issue found: Attacher joint %d has invalid upperDistanceToGround. True value is: %.3f (Value in xml: %.3f)", i, MathUtil.round(groundRaycastResult.groundDistance, 3), attacherJoint.upperDistanceToGround))
                    end
                    if attacherJoint.rotationNode ~= nil and attacherJoint.rotationNode2 ~= nil then
                        local _,dy,_ = localDirectionToWorld(attacherJoint.jointTransform, 0, 1, 0)
                        local angle = math.deg(math.acos(math.clamp(dy, -1, 1)))
                        local _,dxy,_ = localDirectionToWorld(attacherJoint.jointTransform, 1, 0, 0)
                        if dxy < 0 then
                            angle = -angle
                        end
                        if math.abs(angle-math.deg(attacherJoint.upperRotationOffset)) > 0.1 then
                            print(string.format(" Issue found: Attacher joint %d has invalid upperRotationOffset. True value is: %.2f° (Value in xml: %.2f°)", i, angle, math.deg(attacherJoint.upperRotationOffset)))
                        end
                    end

                    -- reset rotations
                    if attacherJoint.rotationNode ~= nil then
                        setRotation(attacherJoint.rotationNode, rx,ry,rz)
                    end
                    if attacherJoint.rotationNode2 ~= nil then
                        setRotation(attacherJoint.rotationNode2, rx2,ry2,rz2)
                    end
                end
                setRotation(attacherJoint.jointTransform, trx, try, trz)

                if attacherJoint.transNode ~= nil then
                    local sx,sy,sz = getTranslation(attacherJoint.transNode)

                    local _, y, _ = localToLocal(self.rootNode, getParent(attacherJoint.transNode), 0, attacherJoint.transNodeMinY, 0)
                    setTranslation(attacherJoint.transNode, sx,y,sz)

                    groundRaycastResult.groundDistance = 0
                    groundRaycastResult.vehicle = self
                    local wx,wy,wz = getWorldTranslation(attacherJoint.transNode)
                    raycastAll(wx,wy,wz, 0, -1, 0, 4, "raycastCallback", groundRaycastResult, 0xFFFF_FFFF)
                    if math.abs(groundRaycastResult.groundDistance - attacherJoint.lowerDistanceToGround) > 0.02 then
                        print(string.format(" Issue found: Attacher joint %d has invalid lowerDistanceToGround. True value is: %.3f (Value in xml: %.3f)", i, MathUtil.round(groundRaycastResult.groundDistance, 3), attacherJoint.lowerDistanceToGround))
                    end

                    _, y, _ = localToLocal(self.rootNode, getParent(attacherJoint.transNode), 0, attacherJoint.transNodeMaxY, 0)
                    setTranslation(attacherJoint.transNode, sx,y,sz)

                    groundRaycastResult.groundDistance = 0
                    wx,wy,wz = getWorldTranslation(attacherJoint.transNode)
                    raycastAll(wx,wy,wz, 0, -1, 0, 4, "raycastCallback", groundRaycastResult, 0xFFFF_FFFF)
                    if math.abs(groundRaycastResult.groundDistance - attacherJoint.upperDistanceToGround) > 0.02 then
                        print(string.format(" Issue found: Attacher joint %d has invalid upperDistanceToGround. True value is: %.3f (Value in xml: %.3f)", i, MathUtil.round(groundRaycastResult.groundDistance, 3), attacherJoint.upperDistanceToGround))
                    end

                    setTranslation(attacherJoint.transNode, sx,sy,sz)
                end
            end
        end

        if self.spec_wheels ~= nil then
            for i, wheel in ipairs(self.spec_wheels.wheels) do
                if wheel.physics.wheelShapeCreated then
                    local _,comY,_ = getCenterOfMass(wheel.node)

                    local forcePointY = wheel.physics.positionY + wheel.physics.deltaY - wheel.physics.radius * wheel.physics.forcePointRatio
                    if forcePointY > comY then
                        print(string.format(" Issue found: Wheel %d has force point higher than center of mass. %.2f > %.2f. This can lead to undesired driving behavior (inward-leaning).", i, forcePointY, comY))
                    end

                    local tireLoad = getWheelShapeContactForce(wheel.node, wheel.physics.wheelShape)
                    if tireLoad ~= nil then
--                         local nx,ny,nz = getWheelShapeContactNormal(wheel.node, wheel.physics.wheelShape)
--                         local dx,dy,dz = localDirectionToWorld(wheel.node, 0,-1,0)
--                         tireLoad = -tireLoad*MathUtil.dotProduct(dx,dy,dz, nx,ny,nz)

--                         local gravity = 9.81
--                         tireLoad = tireLoad + math.max(ny*gravity, 0.0) * wheel:getMass() -- add gravity force of tire

                        tireLoad = tireLoad / 9.81

                        if math.abs(tireLoad - wheel.physics.restLoad) > 0.2 then
                            print(string.format(" Issue found: Wheel %d has wrong restLoad. %.2f vs. %.2f in XML. Verify that this leads to the desired behavior.", i, tireLoad, wheel.physics.restLoad))
                        end
                    end
                end
            end
        end

        return "Analyzed vehicle"
    end

    return "Failed to analyze vehicle. Invalid controlled vehicle"
end
VehicleDebug.consoleCommandAnalyze = Utils.overwrittenFunction(VehicleDebug.consoleCommandAnalyze, VehicleDebug.mrConsoleCommandAnalyze)