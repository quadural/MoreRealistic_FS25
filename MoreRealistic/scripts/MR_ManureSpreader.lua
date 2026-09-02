MR_ManureSpreader = {}

MR_ManureSpreader.MAX_LITERS_PER_SECOND_FX = 1.1 --little bonus because IRL, we can spread manure at very low speed. We don't want players to get "bored"

MR_ManureSpreader.mrLoadMrValues = function(self, xmlFile)

    self.mrIsMrManureSpreader = hasXMLProperty(xmlFile, "vehicle.mrManureSpreader")
    if self.mrIsMrManureSpreader then

        self.mrManureSpreaderIdlePower = getXMLFloat(xmlFile, "vehicle.mrManureSpreader#idlePower") or 1
        self.mrManureSpreaderPowerFx = getXMLFloat(xmlFile, "vehicle.mrManureSpreader#powerFx") or 1 --powerFx = 1 when no spread unit cover, powerFx = 1.4 when cover + discs
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

        self.mrManureSpreaderSpeedLimit = 999

    end

end


MR_ManureSpreader.mrGetActiveConsumedPtoPower = function(self)

    local isTurnedOn = self:getIsTurnedOn()
    local neededPower = 0

    self.mrManureSpreaderSpeedLimit = 999

    if isTurnedOn then

        neededPower = self.mrManureSpreaderIdlePower

        if self.mrSprayerLastLitersPerSecond~=nil and self.mrSprayerLastLitersPerSecond>0 then
            local fillUnitIndex = self:getSprayerFillUnitIndex()
            local fillType = self:getFillUnitFillType(fillUnitIndex)
            local fillTypeDesc = g_fillTypeManager:getFillTypeByIndex(fillType)
            if fillTypeDesc ~= nil and fillTypeDesc.massPerLiter ~= 0 then
                local currentLoadInTons = self:getFillUnitCapacity(fillUnitIndex)*fillTypeDesc.massPerLiter
                local currentTonsPerMinute = self.mrSprayerLastLitersPerSecond * 60 * fillTypeDesc.massPerLiter
                --power to move the floor
                neededPower = neededPower + currentLoadInTons * currentTonsPerMinute / 11
                --spreading unit power
                neededPower = neededPower + currentTonsPerMinute * 4 * self.mrManureSpreaderPowerFx

                --speed limit
                if self.mrSprayerLastLitersPerSecondAtSpeedLimit~=nil and self.mrSprayerLastLitersPerSecondAtSpeedLimit>0 then
                    self.mrManureSpreaderSpeedLimit = MR_ManureSpreader.MAX_LITERS_PER_SECOND_FX * self.speedLimit * self.mrManureSpreaderMaxLiterPerSecond / self.mrSprayerLastLitersPerSecondAtSpeedLimit
                end
            end
        end

    end

    return neededPower

end