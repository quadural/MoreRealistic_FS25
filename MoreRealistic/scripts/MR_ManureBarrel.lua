
ManureBarrel.MAX_LITERS_PER_SECOND_FX = 1.1 --little bonus because IRL, we can spread manure at very low speed. We don't want players to get "bored"

ManureBarrel.mrLoadMrValues = function(self, xmlFile)

    self.mrIsMrManureBarrel = hasXMLProperty(xmlFile, "vehicle.mrManureBarrel")
    if self.mrIsMrManureBarrel then

        self.mrManureBarrelPumpingPower = getXMLFloat(xmlFile, "vehicle.mrManureBarrel#pumpingPower") or 1
        self.mrManureBarrelPumpingLitersPerSecond = getXMLFloat(xmlFile, "vehicle.mrManureBarrel#pumpingLitersPerMinute") or 99999
        self.mrManureBarrelPumpingLitersPerSecond = self.mrManureBarrelPumpingLitersPerSecond / 60 --min to second
        self.mrManureBarrelWorkingPower = getXMLFloat(xmlFile, "vehicle.mrManureBarrel#workingPower") or 1
        self.mrManureBarrelWorkingMaxLitersPerSecond = getXMLFloat(xmlFile, "vehicle.mrManureBarrel#workingMaxLitersPerMinute") or 10000 --limited by the unloading pump or the rear tool
        self.mrManureBarrelWorkingMaxLitersPerSecond = self.mrManureBarrelWorkingMaxLitersPerSecond / 60 --min to second
        self.mrManureBarrelWorkingPumpIsVacuum = getXMLBool(xmlFile, "vehicle.mrManureBarrel#workingPumpIsVacuum") or false
        self.mrManureBarrelNoRegulation = getXMLBool(xmlFile, "vehicle.mrManureBarrel#noRegulation") or false
        self.mrManureBarrelPumpingPtoRpm = getXMLFloat(xmlFile, "vehicle.mrManureBarrel#pumpingPtoRpm") or 540
        self.mrManureBarrelWorkingPtoRpm = getXMLFloat(xmlFile, "vehicle.mrManureBarrel#workingPtoRpm") or 400

        self.mrManureBarrelSpeedLimit = 999
        self.mrManureBarrelIsPumping = false

    end

end


ManureBarrel.mrGetActiveConsumedPtoPower = function(self)

    local isTurnedOn = self:getIsTurnedOn()
    local neededPower = 0

    self.mrManureBarrelSpeedLimit = 999

    if isTurnedOn then

        self.spec_powerConsumer.ptoRpm = self.mrManureBarrelWorkingPtoRpm

        neededPower = self.mrManureBarrelWorkingPower

        local fillUnitIndex = self:getSprayerFillUnitIndex()
        local fillType = self:getFillUnitFillType(fillUnitIndex)
        local fillTypeDesc = g_fillTypeManager:getFillTypeByIndex(fillType)
        if fillTypeDesc ~= nil and fillTypeDesc.massPerLiter ~= 0 then
            local maxLiterPerSecondFx = 1
            if self.mrManureBarrelWorkingPumpIsVacuum then
                --update max flow rate
                local currentFillLevel = self:getFillUnitFillLevel(fillUnitIndex)
                local fillcapacity = self:getFillUnitCapacity(fillUnitIndex)
                if fillcapacity>0 then
                    maxLiterPerSecondFx = math.sqrt(0.75 + 0.35*currentFillLevel/fillcapacity)
                end
            end


            local currentLitersPerSecondPerKph = ManureBarrel.mrGetLitersPerSecondPerKph(self, fillType)
            if currentLitersPerSecondPerKph>0 then
                --update speed limit
                self.mrManureBarrelSpeedLimit = maxLiterPerSecondFx * ManureBarrel.MAX_LITERS_PER_SECOND_FX * self.mrManureBarrelWorkingMaxLitersPerSecond / currentLitersPerSecondPerKph
            end
        end
    end

    if self.mrManureBarrelIsPumping then
        neededPower = math.max(neededPower, self.mrManureBarrelPumpingPower)
    end

    return neededPower

end


ManureBarrel.mrGetLitersPerSecondPerKph = function(self, fillType)

    if fillType == FillType.UNKNOWN then
        return 0
    end

    local spec = self.spec_sprayer
    local litersPerSecondPerKph = 0

    local scale = Utils.getNoNil(spec.usageScale.fillTypeScales[fillType], spec.usageScale.default)
    if scale==0 then return litersPerSecondPerKph end

    local litersPerSecond = 1

    local sprayType = g_sprayTypeManager:getSprayTypeByFillTypeIndex(fillType)
    if sprayType ~= nil then
        litersPerSecond = sprayType.litersPerSecond
        if litersPerSecond==0 then return litersPerSecondPerKph end
    end

    local workWidth = ManureBarrel.mrGetCurrentWorkingWidth(self)
    if workWidth==0 then return litersPerSecondPerKph end

    litersPerSecondPerKph = scale * litersPerSecond * workWidth

    if spec.doubledAmountIsActive then
        litersPerSecondPerKph = 2 * litersPerSecondPerKph
    end

    return litersPerSecondPerKph

end


--more than one workarea can be active for the same spraytype at once (Example : Farmtech variofex750)
ManureBarrel.mrGetCurrentWorkingWidth = function(self)

    local usageScale = self.spec_sprayer.usageScale
    local activeSprayType = self:getActiveSprayType()
    if activeSprayType ~= nil then
        usageScale = activeSprayType.usageScale
    end

    local workWidth
    if usageScale.workAreaIndex ~= nil then
        workWidth = self:getWorkAreaWidth(usageScale.workAreaIndex)
    else
        workWidth = usageScale.workingWidth
    end

    return workWidth

end

ManureBarrel.registerFunctions = function(vehicleType)
    SpecializationUtil.registerFunction(vehicleType, "getLoadTriggerMaxFillSpeed", ManureBarrel.mrGetLoadTriggerMaxFillSpeed)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getDoConsumePtoPower", ManureBarrel.mrGetDoConsumePtoPower)
end


---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- MR : limit the filling speed. Assuming we are using the manure barrel own filling pump to fill the tank
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
ManureBarrel.mrGetLoadTriggerMaxFillSpeed = function(self)
    local maxSpeed = math.huge
    if self.mrIsMrManureBarrel then
        maxSpeed = self.mrManureBarrelPumpingLitersPerSecond/1000 --liters per ms
    end

    return maxSpeed
end


---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- MR : consume pto power when "pumping" from the pit
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
ManureBarrel.mrGetDoConsumePtoPower = function(self, superFunc)

    local doConsume = superFunc(self)

    if self.mrIsMrManureBarrel then
        if self.mrManureBarrelIsPumping then
            doConsume = true
            self.spec_powerConsumer.ptoRpm = self.mrManureBarrelPumpingPtoRpm
            self.mrPowerConsumerForcePtoRpm = true
        else
            self.spec_powerConsumer.ptoRpm = self.mrManureBarrelWorkingPtoRpm
            self.mrPowerConsumerForcePtoRpm = false
        end
    end

    return doConsume

end



