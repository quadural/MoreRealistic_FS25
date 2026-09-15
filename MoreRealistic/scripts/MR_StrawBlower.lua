StrawBlower.mrLoadMrValues = function(self, xmlFile)

    self.mrIsMrStrawBlower = hasXMLProperty(xmlFile, "vehicle.mrStrawBlower")
    if self.mrIsMrStrawBlower then

        self.mrStrawBlowerIdlePower = getXMLFloat(xmlFile, "vehicle.mrStrawBlower#idlePower") or 1
        self.mrStrawBlowerActivePower = getXMLFloat(xmlFile, "vehicle.mrStrawBlower#activePower") or 1

        self.mrStrawBlowerCutterPosition = getXMLString(xmlFile, "vehicle.mrStrawBlower#cutterPosition")
        if self.mrStrawBlowerCutterPosition~=nil then
            self.mrStrawBlowerCutterDefined = true
            self.mrStrawBlowerCutterDirection = getXMLString(xmlFile, "vehicle.mrStrawBlower#cutterDirection") or "0 0 1"
        end

        self.mrStrawBlowerLastDischargedLiters = 0
        self.mrStrawBlowerCurrentActivePower = 0

    end

end


StrawBlower.mrGetActiveConsumedPtoPower = function(self)

    local neededPower = 0

    if self.spec_dischargeable.currentDischargeState ~= Dischargeable.DISCHARGE_STATE_OFF then

        neededPower = self.mrStrawBlowerIdlePower

        if self.mrStrawBlowerLastDischargedLiters>0 then
            self.mrStrawBlowerCurrentActivePower = self.mrStrawBlowerActivePower
            self.mrStrawBlowerLastDischargedLiters = 0
        elseif self.mrStrawBlowerCurrentActivePower>0 then
            self.mrStrawBlowerCurrentActivePower = math.max(0, self.mrStrawBlowerCurrentActivePower - self.mrStrawBlowerActivePower*g_physicsDtLastValidNonInterpolated/1000)
        end

        if self.mrStrawBlowerCurrentActivePower>0 then
            self.mrPowerConsumerForcePtoRpm = true
            neededPower = neededPower + self.mrStrawBlowerCurrentActivePower
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

        if self.mrStrawBlowerCuttingUnitNode==nil then
            --create a new transform group to locate the cutting unit node
            self.mrStrawBlowerCuttingUnitNode = createTransformGroup("mrCuttingUnit")
            link(self.components[1].node, self.mrStrawBlowerCuttingUnitNode)
            setTranslation(self.mrStrawBlowerCuttingUnitNode, unpack(string.getVector(self.mrStrawBlowerCutterPosition)))
            local dirX, dirY, dirZ = unpack(string.getVector(self.mrStrawBlowerCutterDirection))
            setDirection(self.mrStrawBlowerCuttingUnitNode, dirX, dirY, dirZ, 0, 1, 0)
        end

        local spec = self.spec_strawBlower
        if spec.currentBale == nil then
            StrawBlower.mrUpdateFirstBale(self)
        end

    else
        superFunc(self, dt, isActiveForInput, isActiveForInputIgnoreSelection, isSelected)
    end

end
StrawBlower.onUpdateTick = Utils.overwrittenFunction(StrawBlower.onUpdateTick, StrawBlower.mrOnUpdateTick)




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

            end
        end

    end

end

---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- MR : we want to know when the "dischargeable" vehicle is actually discharging (example : strawblower power consumption is increased when actually discharging)
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
StrawBlower.mrHandleDischarge = function(self, dischargeNode, dischargedLiters, minDropReached, hasMinDropFillLevel)
    if self.mrIsMrStrawBlower then
        self.mrStrawBlowerLastDischargedLiters = -dischargedLiters
    end
end
Dischargeable.handleDischarge = Utils.appendedFunction(Dischargeable.handleDischarge, StrawBlower.mrHandleDischarge)