Mower.mrLoadMrValues = function(self, xmlFile)

    self.mrIsMrMower = hasXMLProperty(xmlFile, "vehicle.mrMower")
    if self.mrIsMrMower then

        self.mrMowerCuttingWidth = getXMLFloat(xmlFile, "vehicle.mrMower#cuttingWidth") or 3 --default working width if not specified = 3m (but should be specified)
        self.mrMowerIdlePower = getXMLFloat(xmlFile, "vehicle.mrMower#idlePower") or self.mrMowerCuttingWidth --default idle power = witdh in meters
        self.mrMowerPowerFx = getXMLFloat(xmlFile, "vehicle.mrMower#powerFx") or 1 --efficiency affects the cutting power at work

        self.mrMowerSampleTime = 1000
        self.mrMowerLitersPerSecond = 0
        self.mrMowerLitersPerSecondS = 0
        self.mrMowerLitersPerSecondS2 = 0
        self.mrMowerLitersBuffer = 0
        self.mrMowerLastLitersTime = 0

        self.mrMowerLastNeededPower = 0
    end

end


Mower.mrGetActiveConsumedPtoPower = function(self)

    local isTurnedOn = self:getIsTurnedOn()
    local neededPower = 0

    if isTurnedOn then

        neededPower = self.mrMowerIdlePower

        local sampleTime = g_time-self.mrMowerLastLitersTime
        if sampleTime>self.mrMowerSampleTime then
            self.mrMowerLitersPerSecond = 1000*self.mrMowerLitersBuffer/sampleTime --liters / second
            self.mrMowerLitersPerSecondS = 0.75*self.mrMowerLitersPerSecondS + 0.25*self.mrMowerLitersPerSecond
            self.mrMowerLitersBuffer = 0
            self.mrMowerLastLitersTime = g_time
        end

        if self.spec_mower.isCutting then
            neededPower = neededPower + self.mrMowerPowerFx * 0.5 * (self.mrMowerCuttingWidth * (2 + 0.3*self.lastSpeedReal*3600) + self.mrMowerLitersPerSecondS/6.5)
        end

    end

    self.mrMowerLastNeededPower = neededPower

    return neededPower

end



--we want to get an idea of the liters per second "mowed"
Mower.mrProcessMowerArea = function(self, superFunc, workArea, dt)

    self.mrMowerProcessingMowerArea = true
    local workAreaChanged, workAreaTotal = superFunc(self, workArea, dt)
    self.mrMowerProcessingMowerArea = false

    return workAreaChanged, workAreaTotal
end
Mower.processMowerArea = Utils.overwrittenFunction(Mower.processMowerArea, Mower.mrProcessMowerArea)


--we want to get an idea of the liters per second "mowed"
Mower.mrGetDropArea = function(self, superFunc, workArea)

    if self.mrMowerProcessingMowerArea then
        self.mrMowerLitersBuffer = self.mrMowerLitersBuffer + workArea.lastPickupLiters
    end

    return superFunc(self, workArea)

end
Mower.getDropArea = Utils.overwrittenFunction(Mower.getDropArea, Mower.mrGetDropArea)