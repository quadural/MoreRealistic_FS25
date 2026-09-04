MR_ManureSpreader = {}

MR_ManureSpreader.MAX_LITERS_PER_SECOND_FX = 1.1 --little bonus because IRL, we can spread manure at very low speed. We don't want players to get "bored"

MR_ManureSpreader.mrLoadMrValues = function(self, xmlFile)

    self.mrIsMrManureSpreader = hasXMLProperty(xmlFile, "vehicle.mrManureSpreader")
    if self.mrIsMrManureSpreader then

        self.mrManureSpreaderIdlePower = getXMLFloat(xmlFile, "vehicle.mrManureSpreader#idlePower") or 1
        self.mrManureSpreaderPowerFx = getXMLFloat(xmlFile, "vehicle.mrManureSpreader#powerFx") or 1 --powerFx (simplfied formula to take into account spreading technology) = (width/3)^0.6
        self.mrManureSpreaderMaxLiterPerSecond = getXMLFloat(xmlFile, "vehicle.mrManureSpreader#maxLiterPerSecond") or 100 --maxLiterPerSecond = spread unit passage clearance width x height * 1.6 * FX (FX = 1 when no spread unit cover, FX = 0.75 when cover + discs)

        --Brantner TA 12050 = 2 configurations with different spreading unit
        if self.configurations~=nil and self.configurations.workArea~=nil then
            local workAreaIndexWanted = self.configurations.workArea
            local i = 0
            local xmlKey = ""
            while true do
                xmlKey = string.format("vehicle.mrManureSpreader.config(%d)", i)
                if not hasXMLProperty(xmlFile, xmlKey) then
                    break
                end

                local configWorkAreaIndex = getXMLFloat(xmlFile, xmlKey .. "#workareaIndex")
                if configWorkAreaIndex~=nil and configWorkAreaIndex==workAreaIndexWanted then
                    self.mrManureSpreaderIdlePower = getXMLFloat(xmlFile, xmlKey .. "#idlePower") or 1
                    self.mrManureSpreaderPowerFx = getXMLFloat(xmlFile, xmlKey .. "#powerFx") or 1
                    self.mrManureSpreaderMaxLiterPerSecond = getXMLFloat(xmlFile, xmlKey .. "#maxLiterPerSecond") or 100
                    break
                end

                i = i + 1
            end
        end

        if self.spec_workMode~=nil then
            local i = 0
            local xmlKey = ""
            while true do
                xmlKey = string.format("vehicle.mrManureSpreader.workMode(%d)", i)
                if not hasXMLProperty(xmlFile, xmlKey) then
                    break
                end

                if self.mrManureSpreaderWorkModes==nil then
                    self.mrManureSpreaderWorkModes = {}
                end

                local index = getXMLFloat(xmlFile, xmlKey .. "#index") or i+1
                self.mrManureSpreaderWorkModes[index] = {}
                self.mrManureSpreaderWorkModes[index].maxLiterPerSecondFx = getXMLFloat(xmlFile, xmlKey .. "#maxLiterPerSecondFx") or 1

                i = i + 1
            end
        end

        self.mrManureSpreaderSpeedLimit = 999

    end

end


MR_ManureSpreader.mrGetActiveConsumedPtoPower = function(self)

    local isTurnedOn = self:getIsTurnedOn()
    local neededPower = 0

    self.mrManureSpreaderSpeedLimit = 999

    if isTurnedOn then

        neededPower = self.mrManureSpreaderIdlePower

        local fillUnitIndex = self:getSprayerFillUnitIndex()
        local fillType = self:getFillUnitFillType(fillUnitIndex)
        local fillTypeDesc = g_fillTypeManager:getFillTypeByIndex(fillType)
        if fillTypeDesc ~= nil and fillTypeDesc.massPerLiter ~= 0 then
            local currentFillLevel = self:getFillUnitFillLevel(fillUnitIndex)
            local currentLoadInTons = currentFillLevel*fillTypeDesc.massPerLiter
            local currentLitersPerSecondPerKph = MR_ManureSpreader.mrGetLitersPerSecondPerKph(self, fillType)
            if currentLitersPerSecondPerKph>0 then

                --check if there is a special param for the current workMode (Example : Farmtech VarioFex750)
                local maxLiterPerSecondFx = 1
                if self.mrManureSpreaderWorkModes~=nil and self.mrManureSpreaderWorkModes[self.spec_workMode.state]~=nil then
                    --get current workmode
                    maxLiterPerSecondFx = self.mrManureSpreaderWorkModes[self.spec_workMode.state].maxLiterPerSecondFx
                end

                --update speed limit
                self.mrManureSpreaderSpeedLimit = maxLiterPerSecondFx * MR_ManureSpreader.MAX_LITERS_PER_SECOND_FX * self.mrManureSpreaderMaxLiterPerSecond / currentLitersPerSecondPerKph
                local currentTonsPerMinute = currentLitersPerSecondPerKph * self:getLastSpeed() * 60 * fillTypeDesc.massPerLiter
                --power to move the floor
                neededPower = neededPower + currentLoadInTons * currentTonsPerMinute / 10
                --spreading unit power
                neededPower = neededPower + currentTonsPerMinute * 4 * self.mrManureSpreaderPowerFx
            end
        end

    end

    return neededPower

end


MR_ManureSpreader.mrGetLitersPerSecondPerKph = function(self, fillType)

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

    local workWidth = MR_ManureSpreader.mrGetCurrentWorkingWidth(self)
    if workWidth==0 then return litersPerSecondPerKph end

    litersPerSecondPerKph = scale * litersPerSecond * workWidth

    if spec.doubledAmountIsActive then
        litersPerSecondPerKph = 2 * litersPerSecondPerKph
    end

    return litersPerSecondPerKph

end


--more than one workarea can be active for the same spraytype at once (Example : Farmtech variofex750)
MR_ManureSpreader.mrGetCurrentWorkingWidth = function(self)

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

--     if activeSprayType ~= nil then
--         local totalWorkWidth = 0
--         for _, workArea in pairs(self.spec_workArea.workAreas) do
--             if workArea.sprayType==activeSprayType.index then
--                 totalWorkWidth = totalWorkWidth + workWidth
--             end
--         end

--         return totalWorkWidth
--     end

    return workWidth

end