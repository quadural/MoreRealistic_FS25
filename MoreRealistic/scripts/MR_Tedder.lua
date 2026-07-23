Tedder.mrLoadMrValues = function(self, xmlFile)

    self.mrIsMrTedder = hasXMLProperty(xmlFile, "vehicle.mrTedder")
    if self.mrIsMrTedder then

        self.mrTedderWidth = getXMLFloat(xmlFile, "vehicle.mrTedder#teddingWidth") or 3 --default working width if not specified = 3m (but should be specified)
        self.mrTedderIdlePower = getXMLFloat(xmlFile, "vehicle.mrTedder#idlePower") or self.mrTedderWidth --default idle power = witdh in meters
        self.mrTedderPowerFx = getXMLFloat(xmlFile, "vehicle.mrTedder#powerFx") or 1 --efficiency affects the tedding power at work

        self.mrTedderSampleTime = 1000
        self.mrTedderLitersPerSecond = 0
        self.mrTedderLitersPerSecondS = 0
        self.mrTedderLitersPerSecondS2 = 0
        self.mrTedderLitersBuffer = 0
        self.mrTedderLastLitersTime = 0

        self.mrTedderLastNeededPower = 0
    end

end


Tedder.mrGetActiveConsumedPtoPower = function(self)

    local isTurnedOn = self:getIsTurnedOn()
    local neededPower = 0

    if isTurnedOn then

        neededPower = self.mrTedderIdlePower

        local sampleTime = g_time-self.mrTedderLastLitersTime
        if sampleTime>self.mrTedderSampleTime then
            if self.mrTedderLitersBuffer==0 then
                self.mrTedderLitersPerSecond = 0
                self.mrTedderLitersPerSecondS = 0.5*self.mrTedderLitersPerSecondS
            else
                self.mrTedderLitersPerSecond = 1000*self.mrTedderLitersBuffer/sampleTime --liters / second
                self.mrTedderLitersPerSecondS = 0.75*self.mrTedderLitersPerSecondS + 0.25*self.mrTedderLitersPerSecond
            end
            self.mrTedderLitersBuffer = 0
            self.mrTedderLastLitersTime = g_time
        end

        neededPower = neededPower + self.mrTedderPowerFx * self.mrTedderLitersPerSecondS/10

    else
        self.mrTedderLitersBuffer = 0
        self.mrTedderLitersPerSecond = 0
        self.mrTedderLitersPerSecondS = 0
    end

    self.mrTedderLastNeededPower = neededPower

    return neededPower

end

--we want to get an idea of the liters per second "tedded"
Tedder.mrOnEndWorkAreaProcessing = function(self, superFunc, dt, hasProcessed)

    superFunc(self, dt, hasProcessed)

    if self.mrIsMrTedder then
        self.mrTedderLitersBuffer = self.mrTedderLitersBuffer + self.spec_tedder.lastDroppedLiters
    end

end
Tedder.onEndWorkAreaProcessing = Utils.overwrittenFunction(Tedder.onEndWorkAreaProcessing, Tedder.mrOnEndWorkAreaProcessing)