ForageWagon.mrLoadMrValues = function(self, xmlFile)

    self.mrIsMrForageWagon = hasXMLProperty(xmlFile, "vehicle.mrForageWagon")
    if self.mrIsMrForageWagon then

        self.mrForageWagonIdlePower = getXMLFloat(xmlFile, "vehicle.mrForageWagon#idlePower") or 2 --default idle power = 2KW
        self.mrForageWagonPowerFx = getXMLFloat(xmlFile, "vehicle.mrForageWagon#powerFx") or 1 --efficiency affects the power at work
        self.mrForageWagonUnloadingPower = getXMLFloat(xmlFile, "vehicle.mrForageWagon#unloadingPower") or 5 --default unloading power = 5KW

        self.mrForageWagonSampleTime = 1000
        self.mrForageWagonLitersPerSecond = 0
        self.mrForageWagonLitersPerSecondS = 0
        self.mrForageWagonLitersPerSecondS2 = 0
        self.mrForageWagonLitersBuffer = 0
        self.mrForageWagonLastLitersTime = 0

        self.mrForageWagonLastNeededPower = 0
    end

end


ForageWagon.mrGetActiveConsumedPtoPower = function(self)

    local isTurnedOn = self:getIsTurnedOn()
    local neededPower = 0

    --unloading power
    if not self.spec_forageWagon.isFilling then
        if self:getDischargeState() ~= Dischargeable.DISCHARGE_STATE_OFF then
            neededPower = neededPower + self.mrForageWagonUnloadingPower
        end
    end

    if isTurnedOn then

        neededPower = neededPower + self.mrForageWagonIdlePower

        local sampleTime = g_time-self.mrForageWagonLastLitersTime
        if sampleTime>self.mrForageWagonSampleTime then
            if self.mrForageWagonLitersBuffer==0 then
                self.mrForageWagonLitersPerSecond = 0
                self.mrForageWagonLitersPerSecondS = 0.5*self.mrForageWagonLitersPerSecondS
            else
                self.mrForageWagonLitersPerSecond = 1000*self.mrForageWagonLitersBuffer/sampleTime --liters / second
                self.mrForageWagonLitersPerSecondS = 0.75*self.mrForageWagonLitersPerSecondS + 0.25*self.mrForageWagonLitersPerSecond
            end
            self.mrForageWagonLitersBuffer = 0
            self.mrForageWagonLastLitersTime = g_time
        end

        local spdFx = math.sqrt(self.lastSpeedReal*360) --speed in kph divide by 10 => then squaroot
        neededPower = neededPower + self.mrForageWagonPowerFx * spdFx * 1.25 * math.pow(self.mrForageWagonLitersPerSecondS, 0.9)

    else
        self.mrForageWagonLitersBuffer = 0
        self.mrForageWagonLitersPerSecond = 0
        self.mrForageWagonLitersPerSecondS = 0
    end

    self.mrForageWagonLastNeededPower = neededPower

    return neededPower

end

--we want to get an idea of the liters per second "tedded"
ForageWagon.mrOnEndWorkAreaProcessing = function(self, superFunc, dt, hasProcessed)

    superFunc(self, dt, hasProcessed)

    if hasProcessed and self.isServer and self.mrIsMrForageWagon then
        self.mrForageWagonLitersBuffer = self.mrForageWagonLitersBuffer + self.spec_forageWagon.workAreaParameters.lastPickupLiters
    end

end
ForageWagon.onEndWorkAreaProcessing = Utils.overwrittenFunction(ForageWagon.onEndWorkAreaProcessing, ForageWagon.mrOnEndWorkAreaProcessing)