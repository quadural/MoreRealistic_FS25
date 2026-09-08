StrawBlower.mrLoadMrValues = function(self, xmlFile)

    self.mrIsMrStrawBlower = hasXMLProperty(xmlFile, "vehicle.mrStrawBlower")
    if self.mrIsMrStrawBlower then

        self.mrStrawBlowerIdlePower = getXMLFloat(xmlFile, "vehicle.mrStrawBlower#idlePower") or 1
        self.mrStrawBlowerActivePower = getXMLFloat(xmlFile, "vehicle.mrStrawBlower#activePower") or 1

        self.mrStrawBlowerCutterPosition = getXMLString(xmlFile, "vehicle.mrStrawBlower#cutterPosition")
        if self.mrStrawBlowerCutterPosition~=nil then
            self.mrStrawBlowerCutterDefined = true
            self.mrStrawBlowerCutterDirection = getXMLString(xmlFile, "vehicle.mrStrawBlower#cutterDirection") or "0 0 1"
            self.mrStrawBlowerMaxBaleDistanceToCutterUnit = getXMLFloat(xmlFile, "vehicle.mrStrawBlower#maxBaleDistanceToCutterUnit") or 0.5
            self.mrStrawBlowerBaleDistanceToCutterUnit = 0
            self.mrStrawBlowerRefreshTimer = 9999
            self.mrStrawBlowerRefreshTimerMaxTime = 2000
            self.mrStrawBlowerTractiveJoint = {}
        end

    end

end


StrawBlower.mrGetActiveConsumedPtoPower = function(self)

    local neededPower = 0

    if self.spec_dischargeable.currentDischargeState ~= Dischargeable.DISCHARGE_STATE_OFF then

        neededPower = self.mrStrawBlowerIdlePower

        local fillLevel = self:getFillUnitFillLevel(self.spec_strawBlower.fillUnitIndex)
        if fillLevel>0 then
            if self.mrStrawBlowerCutterDefined then
                if self.mrStrawBlowerBaleDistanceToCutterUnit <= self.mrStrawBlowerMaxBaleDistanceToCutterUnit then
                    neededPower = neededPower + self.mrStrawBlowerActivePower
                end
            else
                neededPower = neededPower + self.mrStrawBlowerActivePower
            end
            self.mrPowerConsumerForcePtoRpm = true
        end

    end

    return neededPower

end

---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- MR : select the righ bale when more than one bales present (we want to "crush" the bale that is closer to the cutter unit first
-- sometimes, the bale "order" can change (depending on how bales are "stacked" into the strawbaler)
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
StrawBlower.mrOnUpdateTick = function(self, superFunc, dt, isActiveForInput, isActiveForInputIgnoreSelection, isSelected)

    --only run on server side since the listener is removed for clients
    if self.mrIsMrStrawBlower and self.mrStrawBlowerCutterDefined then

        local spec = self.spec_strawBlower
        if spec.currentBale == nil then
            StrawBlower.mrUpdateFirstBale(self)
        elseif self.spec_dischargeable.currentDischargeState ~= Dischargeable.DISCHARGE_STATE_OFF then
            if spec.currentBale ~= nil then --while blowing straw, update the distance between the active bale and the cutting unit
                local baleX, baleY, baleZ = localToLocal(spec.currentBale.nodeId, self.mrStrawBlowerCuttingUnitNode, 0, 0, 0)
                local distance = MathUtil.vector3Length(baleX, baleY, baleZ)
                StrawBlower.mrUpdateBaleDistanceWithCuttingUnit(self, distance)

                if self.mrStrawBlowerBaleDistanceToCutterUnit > self.mrStrawBlowerMaxBaleDistanceToCutterUnit then
                    self.mrStrawBlowerRefreshTimer = math.max(0, self.mrStrawBlowerRefreshTimer - dt)
                    if self.mrStrawBlowerRefreshTimer<=0 then
                        StrawBlower.mrUpdateFirstBale(self)
                    end
                end

            end
        else --not active
            StrawBlower.mrRemoveTractionJoint(self)
        end

    else
        superFunc(self, dt, isActiveForInput, isActiveForInputIgnoreSelection, isSelected)
    end

end
StrawBlower.onUpdateTick = Utils.overwrittenFunction(StrawBlower.onUpdateTick, StrawBlower.mrOnUpdateTick)



---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- MR : add some forces to pull the bale being crushed toward the cutter unit
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
StrawBlower.mrOnUpdate = function(self, superFunc, dt)

    if self.isServer and self.mrIsMrStrawBlower and self.mrStrawBlowerCutterDefined then

        if self.mrStrawBlowerCuttingUnitNode==nil then
            --create a new transform group to locate the cutting unit node
            self.mrStrawBlowerCuttingUnitNode = createTransformGroup("mrCuttingUnit")
            link(self.components[1].node, self.mrStrawBlowerCuttingUnitNode)
            setTranslation(self.mrStrawBlowerCuttingUnitNode, unpack(string.getVector(self.mrStrawBlowerCutterPosition)))
            local dirX, dirY, dirZ = unpack(string.getVector(self.mrStrawBlowerCutterDirection))
            setDirection(self.mrStrawBlowerCuttingUnitNode, dirX, dirY, dirZ, 0, 1, 0)
        end

        local spec = self.spec_strawBlower

        if spec.currentBale~=nil and self.spec_dischargeable.currentDischargeState ~= Dischargeable.DISCHARGE_STATE_OFF and entityExists(spec.currentBale.nodeId) then
            --try to find the bale point that is closer to the ground
--             local forceFactor = 0
--             local baleX, baleY, baleZ
--             if spec.currentBale.isRoundbale then
--                 local _, baleY1, _ = localToWorld(spec.currentBale.nodeId, 0, -0.25*spec.currentBale.diameter, 0)
--                 local _, baleY2, _ = localToWorld(spec.currentBale.nodeId, 0, 0.25*spec.currentBale.diameter, 0)
--                 local _, baleY3, _ = localToWorld(spec.currentBale.nodeId, 0.25*spec.currentBale.diameter, 0, 0)
--                 local _, baleY4, _ = localToWorld(spec.currentBale.nodeId, -0.25*spec.currentBale.diameter, 0, 0)

--                 local minDist = math.min(baleY1, baleY2, baleY3, baleY4)

--                 if baleY1==minDist then
--                     baleX, baleY, baleZ = 0, -0.25*spec.currentBale.diameter, 0
--                 elseif baleY2==minDist then
--                     baleX, baleY, baleZ = 0, 0.25*spec.currentBale.diameter, 0
--                 elseif baleY3==minDist then
--                     baleX, baleY, baleZ = 0.25*spec.currentBale.diameter, 0, 0
--                 elseif baleY4==minDist then
--                     baleX, baleY, baleZ = -0.25*spec.currentBale.diameter, 0, 0
--                 end

--                 if self.mrStrawBlowerBaleDistanceToCutterUnit <= self.mrStrawBlowerMaxBaleDistanceToCutterUnit then
--                     forceFactor = 5 --already near the cutting unit, no need to try moving the bale
--                 else
--                     --compare bale velocity to strawblower velocity
--                     local bvX, bvY, bvZ = getLinearVelocity(spec.currentBale.nodeId)
--                     local svX, svY, svZ = getLinearVelocity(self.components[1].node)

--                     local _, _, dz = worldDirectionToLocal(self.mrStrawBlowerCuttingUnitNode, bvX-svX, bvY-svY, bvZ-svZ)
--                     if dz<=0 then
--                         forceFactor = 10
--                     else
--                         forceFactor = math.max(0, 10 - 5*(dz/0.25)^2) --0.25 = 0.9kph
--                     end

--                 end

--             else
--                 --square bales
--                 local bx, by, bz = localToLocal(spec.currentBale.nodeId, self.mrStrawBlowerCuttingUnitNode, 0, 0, 0.5*spec.currentBale.length)
--                 local distance1 = MathUtil.vector3Length(bx, by, bz)

--                 bx, by, bz = localToLocal(spec.currentBale.nodeId, self.mrStrawBlowerCuttingUnitNode, 0, 0, -0.5*spec.currentBale.length)
--                 local distance2 = MathUtil.vector3Length(bx, by, bz)


--                 if distance1<distance2 then
--                     baleX, baleY, baleZ = 0, 0, 0.5*spec.currentBale.length
--                 else
--                     baleX, baleY, baleZ = 0, 0, -0.5*spec.currentBale.length
--                 end

--                 if self.mrStrawBlowerBaleDistanceToCutterUnit <= self.mrStrawBlowerMaxBaleDistanceToCutterUnit then
--                     forceFactor = 5 --already near the cutting unit, no need to try moving the bale
--                 else
--                     --compare bale velocity to strawblower velocity
--                     local bvX, bvY, bvZ = getLinearVelocity(spec.currentBale.nodeId)
--                     local svX, svY, svZ = getLinearVelocity(self.components[1].node)

--                     local _, _, dz = worldDirectionToLocal(self.mrStrawBlowerCuttingUnitNode, bvX-svX, bvY-svY, bvZ-svZ)
--                     if dz<=0 then
--                         forceFactor = 20
--                     else
--                         forceFactor = math.max(5, 20 - 10*(dz/0.25)^2) --0.25 = 0.9kph
--                     end

--                 end

--             end

--             if spec.currentBale.width<0.5 then
--                 --small square bales : lot of "glue" in the game
--                 forceFactor = 1.5*forceFactor
--             end

            --local force = forceFactor*spec.currentBale:getMass()
            --local bx, by, bz = localToLocal(spec.currentBale.nodeId, self.mrStrawBlowerCuttingUnitNode, baleX, baleY, baleZ) -- bale "tractive point" in the strawblower coordinate system
            --if by>0 then by = 0 end --if bale position = "above" cutting unit, we don't want to pull the bale toward the ground
            --local fx, fy, fz = MathUtil.vector3SetLength(bx, by, bz, -force)
            --local dx,dy,dz = localDirectionToWorld(self.mrStrawBlowerCuttingUnitNode, fx, fy, fz)

            --addForce(spec.currentBale.nodeId, dx, dy, dz, baleX, baleY, baleZ, true)

            --too much problem with "forces" (the strawblower can push the tractor if the bales are heavy and the tractor quite small)
            --trying with "joints" like I did with woodcrusher



            --MR : display force point position
--             local x, y, z = localToWorld(spec.currentBale.nodeId, baleX, baleY, baleZ)
--             local dirX, dirY, dirZ = localDirectionToWorld(self.mrStrawBlowerCuttingUnitNode, fx, fy, fz)
--             local upX, upY, upZ = localDirectionToWorld(self.mrStrawBlowerCuttingUnitNode, 0, 1, 0)
--             DebugGizmo.renderAtPosition(x, y, z, dirX, dirY, dirZ, upX, upY, upZ, "Force Point", false, 0.7)


        end

    end

end
StrawBlower.onUpdate = Utils.overwrittenFunction(StrawBlower.onUpdate, StrawBlower.mrOnUpdate)


-- ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- --
-- --MR : add new listener for "onSetLowered"
-- --
-- ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
StrawBlower.mrRegisterEventListeners = function(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onUpdate", StrawBlower)
end
 StrawBlower.registerEventListeners = Utils.appendedFunction(StrawBlower.registerEventListeners, StrawBlower.mrRegisterEventListeners)


 -- --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- --
-- --MR : add new overwritten function
-- --
-- ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
StrawBlower.mrRegisterOverwrittenFunctions = function(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getDischargeNodeEmptyFactor", StrawBlower.mrGetDischargeNodeEmptyFactor)
end
 StrawBlower.registerOverwrittenFunctions = Utils.appendedFunction(StrawBlower.registerOverwrittenFunctions, StrawBlower.mrRegisterOverwrittenFunctions)


 --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- MR : prevent blowing straw when ther is no bale close to the cutting unit
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
StrawBlower.mrGetDischargeNodeEmptyFactor = function(self, superFunc, dischargeNode)

    if self.mrIsMrStrawBlower and self.mrStrawBlowerCutterDefined and self.mrStrawBlowerBaleDistanceToCutterUnit > self.mrStrawBlowerMaxBaleDistanceToCutterUnit then
        return 0
    end

    return superFunc(self, dischargeNode)

end
StrawBlower.getDischargeNodeEmptyFactor = Utils.overwrittenFunction(StrawBlower.getDischargeNodeEmptyFactor, StrawBlower.mrGetDischargeNodeEmptyFactor)

 --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- MR : get the distance from the bale to the cutter unit (we want to know if the cutter can feed the blower or not)
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
StrawBlower.mrUpdateBaleDistanceWithCuttingUnit = function(self, distanceFromCenterOfBale)

    self.mrStrawBlowerBaleDistanceToCutterUnit = 0
    local spec = self.spec_strawBlower
    if spec.currentBale~=nil and entityExists(spec.currentBale.nodeId) then
        if spec.currentBale.isRoundbale then
            self.mrStrawBlowerBaleDistanceToCutterUnit = distanceFromCenterOfBale - 0.5*spec.currentBale.diameter
        else
            self.mrStrawBlowerBaleDistanceToCutterUnit = distanceFromCenterOfBale - 0.5*spec.currentBale.length
        end
    end

end


---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- MR : select the bale closer to the cutting unit
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
StrawBlower.mrUpdateFirstBale = function(self)

    local spec = self.spec_strawBlower

    if self.mrStrawBlowerCuttingUnitNode~=nil and self:getFillUnitSupportsToolType(spec.fillUnitIndex, ToolType.BALE)  then

        self.mrStrawBlowerRefreshTimer = self.mrStrawBlowerRefreshTimerMaxTime

        local firstBale
        local shorterDistance = 99

        for bale, _ in pairs(spec.triggeredBales) do
            if bale~=nil then
                --check distance
                local baleX, baleY, baleZ = localToLocal(bale.nodeId, self.mrStrawBlowerCuttingUnitNode, 0, 0, 0)
                local distance = MathUtil.vector3Length(baleX, baleY, baleZ)
                distance = distance + baleY --better (lower) score when the bale is toward the floor
                if distance<shorterDistance then
                    shorterDistance = distance
                    firstBale = bale
                end
            end
        end

        if firstBale~=nil then
            StrawBlower.mrCreateTractionJoint(self, firstBale.nodeId, firstBale:getMass())
            if spec.currentBale==nil or firstBale~=spec.currentBale then
                if spec.currentBale~=nil then
                    spec.currentBale = nil
                    --important to let 0.1 Liters so that the discharge state is not changed to OFF
                    self:addFillUnitFillLevel(self:getOwnerFarmId(), spec.fillUnitIndex, 0.1-self:getFillUnitFillLevel(spec.fillUnitIndex), self:getFillUnitFillType(spec.fillUnitIndex), ToolType.UNDEFINED)
                end

                self:setFillUnitCapacity(spec.fillUnitIndex, firstBale:getFillLevel())
                self:addFillUnitFillLevel(self:getOwnerFarmId(), spec.fillUnitIndex, -math.huge, FillType.UNKNOWN, ToolType.UNDEFINED)
                self:addFillUnitFillLevel(self:getOwnerFarmId(), spec.fillUnitIndex, firstBale:getFillLevel(), firstBale:getFillType(), ToolType.BALE)
                spec.currentBale = firstBale
                StrawBlower.mrUpdateBaleDistanceWithCuttingUnit(self, shorterDistance)
            end
        end

    end

end

---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- MR : we can't use # to get the number of elements
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- StrawBlower.mrGetTriggeredBalesCount = function(self)
--     local numBales = 0
--     for _, _ in pairs(self.spec_strawBlower.triggeredBales) do
--         numBales = numBales + 1
--     end
--     return numBales
-- end


---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
--MR : use joint instead of applying force to move bales when they are dragged by the floor
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
StrawBlower.mrCreateTractionJoint = function(self, baleId, baleMass)

    if self.mrStrawBlowerTractiveJoint.baleId~=nil and self.mrStrawBlowerTractiveJoint.baleId==baleId then
        return --no need to create joint, already exists
    end
    StrawBlower.mrRemoveTractionJoint(self)

    -- Create the joint between the crusher and the log
    local joint = JointConstructor.new()
    joint:setActors(self.components[1].node, baleId)

    local tx, ty, tz = localToWorld(self.mrStrawBlowerCuttingUnitNode, 0, 0, 0) --world point we want to reach to be crushed = traction target point
    --local x,y,z = self.mrTractionNodes[baleId].forcePointX, self.mrTractionNodes[baleId].forcePointY, self.mrTractionNodes[baleId].forcePointZ --this is the force point in the shape coordinate system

    local wx,wy,wz = localToWorld(baleId, 0, 0, 0) --this is the world point where to apply the force to the log

    joint:setJointWorldPositions(tx, ty, tz, wx, wy, wz)

    -- Set the axes and normals.
    local targetLeftX, targetLeftY, targetLeftZ = localDirectionToWorld(self.mrStrawBlowerCuttingUnitNode, 0, 0, 1)
    joint:setJointWorldAxes(targetLeftX, targetLeftY, targetLeftZ, targetLeftX, targetLeftY, targetLeftZ)

    local targetUpX, targetUpY, targetUpZ = localDirectionToWorld(self.mrStrawBlowerCuttingUnitNode, 0, 1, 0)
    joint:setJointWorldNormals(targetUpX, targetUpY, targetUpZ, targetUpX, targetUpY, targetUpZ)

    local jointLimitX = 0.5
    local jointLimitY = 0.5
    local jointLimitZ = 0.2

    -- Set the limits.
    joint:setTranslationLimit(0, true, -jointLimitX, jointLimitX)
    joint:setTranslationLimit(1, true, -jointLimitY, jointLimitY)
    joint:setTranslationLimit(2, true, -jointLimitZ, jointLimitZ)

    joint:setRotationLimit(0, -math.huge, math.huge)
    joint:setRotationLimit(1, -math.huge, math.huge)
    joint:setRotationLimit(2, -math.huge, math.huge)

    joint:setEnableCollision(true)

    joint:setRotationLimitSpring(1,1,1,1,1,1)

     local mass =  0.5
--      local spring = math.max(10, 500*mass)
--      local damping = math.max(1, 50*mass)
--      local maxForce = 15*mass

    --more spring/force for the z axis
    --joint:setTranslationLimitSpring(0.1*spring, damping, 0.5*spring, damping, spring, damping)
    --joint:setTranslationLimitForceLimit(0.5*maxForce, 0.5*maxForce, maxForce)

    joint:setTranslationLimitSpring(1,1,1,1,1,1)



    self.mrStrawBlowerTractiveJoint.baleId = baleId
    self.mrStrawBlowerTractiveJoint.joint = joint:finalize()

    setJointLinearDrive(self.mrStrawBlowerTractiveJoint.joint, 2, true, true, 0, 1, 1000, 50, mass*25)

end

---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
--MR : use joint instead of applying force to move bales when they are dragged by the floor
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
StrawBlower.mrRemoveTractionJoint = function(self)
    --remove existing joint if present
    if self.mrStrawBlowerTractiveJoint.baleId~=nil then
        if entityExists(self.mrStrawBlowerTractiveJoint.baleId) then
            removeJoint(self.mrStrawBlowerTractiveJoint.joint)
        end
        self.mrStrawBlowerTractiveJoint.baleId = nil
    end
end
