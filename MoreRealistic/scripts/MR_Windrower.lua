Windrower.mrLoadMrValues = function(self, xmlFile)

    self.mrIsMrWindrower = hasXMLProperty(xmlFile, "vehicle.mrWindrower")
    if self.mrIsMrWindrower then

        self.mrWindrowerWidth = getXMLFloat(xmlFile, "vehicle.mrWindrower#rakingWidth") or 3 --default working width if not specified = 3m (but should be specified)
        self.mrWindrowerIdlePower = getXMLFloat(xmlFile, "vehicle.mrWindrower#idlePower") or self.mrWindrowerWidth*1.5 --default idle power = witdh in meters
        self.mrWindrowerPowerFx = getXMLFloat(xmlFile, "vehicle.mrWindrower#powerFx") or 1 --efficiency affects the tedding power at work

        self.mrWindrowerSampleTime = 1000
        self.mrWindrowerLitersPerSecond = 0
        self.mrWindrowerLitersPerSecondS = 0
        self.mrWindrowerLitersPerSecondS2 = 0
        self.mrWindrowerLitersBuffer = 0
        self.mrWindrowerLastLitersTime = 0

        self.mrWindrowerLastNeededPower = 0
    end

end


Windrower.mrGetActiveConsumedPtoPower = function(self)

    local isTurnedOn = self:getIsTurnedOn()
    local neededPower = 0

    if isTurnedOn then

        neededPower = self.mrWindrowerIdlePower

        local sampleTime = g_time-self.mrWindrowerLastLitersTime
        if sampleTime>self.mrWindrowerSampleTime then
            if self.mrWindrowerLitersBuffer==0 then
                self.mrWindrowerLitersPerSecond = 0
                self.mrWindrowerLitersPerSecondS = 0.5*self.mrWindrowerLitersPerSecondS
            else
                self.mrWindrowerLitersPerSecond = 1000*self.mrWindrowerLitersBuffer/sampleTime --liters / second
                self.mrWindrowerLitersPerSecondS = 0.75*self.mrWindrowerLitersPerSecondS + 0.25*self.mrWindrowerLitersPerSecond
            end
            self.mrWindrowerLitersBuffer = 0
            self.mrWindrowerLastLitersTime = g_time
        end

        --the "liters per second" can return very funny values (windrower picking up the material it is currently dropping => big liters per second values)
        --so we can't rely on it
        if self.mrWindrowerLitersPerSecond>1 then
            neededPower = neededPower + self.mrWindrowerPowerFx * self.mrWindrowerWidth * self.lastSpeedReal * 900
        end

    else
        self.mrWindrowerLitersBuffer = 0
        self.mrWindrowerLitersPerSecond = 0
        self.mrWindrowerLitersPerSecondS = 0
    end

    self.mrWindrowerLastNeededPower = neededPower

    return neededPower

end

--we want to get an idea of the liters per second "tedded"
Windrower.mrOnEndWorkAreaProcessing = function(self, superFunc, dt, hasProcessed)

    superFunc(self, dt, hasProcessed)

    if hasProcessed and self.isServer and self.mrIsMrWindrower then
        for _, workArea in pairs(self.spec_workArea.workAreas) do
            self.mrWindrowerLitersBuffer = self.mrWindrowerLitersBuffer + workArea.lastPickupLiters
        end
    end

end
Windrower.onEndWorkAreaProcessing = Utils.overwrittenFunction(Windrower.onEndWorkAreaProcessing, Windrower.mrOnEndWorkAreaProcessing)