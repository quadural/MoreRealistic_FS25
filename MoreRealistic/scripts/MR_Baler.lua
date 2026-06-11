Baler.MR_MIN_SPEED_LIMIT = 5

Baler.mrLoadMrValues = function(self, xmlFile)

    self.mrIsMrBaler = hasXMLProperty(xmlFile, "vehicle.mrBaler")
    if self.mrIsMrBaler then

        self.mrBalerIdlePower = getXMLFloat(xmlFile, "vehicle.mrBaler#idlePower") or 10
        self.mrBalerPowerIncreaseWithFeedingKilosPerSecond = getXMLFloat(xmlFile, "vehicle.mrBaler#powerIncreaseWithFeedingKilosPerSecond") or 2
        self.mrBalerPowerIncreaseWithBaleMass = getXMLFloat(xmlFile, "vehicle.mrBaler#powerIncreaseWithBaleMass") or 0
        self.mrBalerMaxTonsPerHour = getXMLFloat(xmlFile, "vehicle.mrBaler#maxTonsPerHour") or 50
        self.mrBalerUnfinishedBaleThreshold = getXMLFloat(xmlFile, "vehicle.mrBaler#unfinishedBaleThreshold")

        if self.mrBalerUnfinishedBaleThreshold~=nil then
            self.mrBalerUnfinishedBaleThreshold = math.clamp(self.mrBalerUnfinishedBaleThreshold, 0.5, 0.99) --protection against bad values
        end

        self.mrBalerLastLitersPickedUp = 0
        self.mrBalerLitersBufferTime = 0
        self.mrBalerBufferStartTime = 0
        self.mrBalerLitersBuffer = 0
        self.mrBalerLitersPerSecond = 0
        self.mrBalerLitersPerSecondS = 0
        self.mrBalerLastTonsPerHour = 0
        self.mrBalerLastTonsPerHourAvg = 0
        self.mrBalerSpeedLimit = 999
    end

end



Baler.mrGetActiveConsumedPtoPower = function(self)
    local spec = self.spec_baler
    local isTurnedOn = self:getIsTurnedOn()
    local neededPower = self.mrBalerIdlePower

    if isTurnedOn then

        local desc = nil
        local fillUnit = self.spec_fillUnit.fillUnits[spec.fillUnitIndex]
        if fillUnit~=nil and fillUnit.fillLevel>0 and fillUnit.fillType~=FillType.UNKNOWN then
            desc = g_fillTypeManager:getFillTypeByIndex(fillUnit.fillType)
        end

        --power to "rotate" the bale
        if desc~=nil and self.mrBalerPowerIncreaseWithBaleMass>0 then
            local mass = fillUnit.fillLevel * desc.massPerLiter
            neededPower = neededPower + self.mrBalerPowerIncreaseWithBaleMass * mass
        end

        --update liters per second pickedup
        self.mrBalerLitersBuffer = self.mrBalerLitersBuffer + self.mrBalerLastLitersPickedUp
        self.mrBalerLastLitersPickedUp = 0

        if g_time>self.mrBalerLitersBufferTime then
            local maxTime = 500
            local totalTime = g_time - self.mrBalerBufferStartTime
            self.mrBalerLitersPerSecond = 1000*self.mrBalerLitersBuffer / totalTime
            if self.mrBalerLitersPerSecond>self.mrBalerLitersPerSecondS then
                self.mrBalerLitersPerSecondS = 0.5*self.mrBalerLitersPerSecondS + 0.5*self.mrBalerLitersPerSecond
            else
                self.mrBalerLitersPerSecondS = 0.95*self.mrBalerLitersPerSecondS + 0.05*self.mrBalerLitersPerSecond
            end
            self.mrBalerLitersBuffer = 0
            self.mrBalerBufferStartTime = g_time
            self.mrBalerLitersBufferTime = g_time + maxTime
        end

        local currentKilosPerSecond = 0
        local currentKilosPerSecondS = 0
        if desc~=nil then
            currentKilosPerSecond = self.mrBalerLitersPerSecond * desc.massPerLiter * 1000 -- 1000 => massPerLiter is in tons, we want kilos
            currentKilosPerSecondS = self.mrBalerLitersPerSecondS * desc.massPerLiter * 1000
        end

        self.mrBalerLastTonsPerHour = currentKilosPerSecond * 3.6  --3.6 = kilos per seconds to tons per hour
        self.mrBalerLastTonsPerHourAvg = 0.99*self.mrBalerLastTonsPerHourAvg + 0.01*self.mrBalerLastTonsPerHour

        --power of the feeding system
        if desc~=nil and self.mrBalerPowerIncreaseWithFeedingKilosPerSecond>0 then
            neededPower = neededPower + currentKilosPerSecondS * self.mrBalerPowerIncreaseWithFeedingKilosPerSecond
        end

        if self.mrBalerSpeedLimit==999 then
            self.mrBalerSpeedLimit = self.speedLimit
        end

        if self.mrBalerLastTonsPerHour>self.mrBalerMaxTonsPerHour then
            self.mrBalerSpeedLimit = math.max(self.mrBalerSpeedLimit - g_physicsDtLastValidNonInterpolated/500, Baler.MR_MIN_SPEED_LIMIT) --2kph per second
        else
            self.mrBalerSpeedLimit = math.min(self.mrBalerSpeedLimit + g_physicsDtLastValidNonInterpolated/500, self.speedLimit) --2kph per second
        end

    else -- not turned on

        self.mrBalerLastLitersPickedUp = 0
        self.mrBalerLitersPerSecond = 0
        self.mrBalerLitersPerSecondS = 0
        self.mrBalerLitersBuffer = 0
        self.mrBalerLastTonsPerHour = 0
        self.mrBalerLastTonsPerHourAvg = 0
        self.mrBalerSpeedLimit = 999

    end

    return neededPower

end


--update mrBalerLastLitersPickedUp
Baler.mrProcessBalerArea = function(self, superFunc, workArea, dt)

    local liters1, liters2 = superFunc(self, workArea, dt)

    if self.isServer and self.mrIsMrBaler then
        --we want to store the number of liters pickedup by "frame"
        self.mrBalerLastLitersPickedUp = self.mrBalerLastLitersPickedUp + liters1
    end

    return liters1, liters2

end
Baler.processBalerArea = Utils.overwrittenFunction(Baler.processBalerArea, Baler.mrProcessBalerArea)



--update unfinishedBaleThreshold if needed
Baler.mrGetCanUnloadUnfinishedBale = function(self, superFunc)
    Baler.mrUpdateUnfinishedBaleThresholdCapacity(self)
    return superFunc(self)
end
Baler.getCanUnloadUnfinishedBale = Utils.overwrittenFunction(Baler.getCanUnloadUnfinishedBale, Baler.mrGetCanUnloadUnfinishedBale)

--update unfinishedBaleThreshold if needed
Baler.mrSetIsUnloadingBale = function(self, superFunc, isUnloadingBale, noEventSend)
    Baler.mrUpdateUnfinishedBaleThresholdCapacity(self)
    return superFunc(self, isUnloadingBale, noEventSend)
end
Baler.setIsUnloadingBale = Utils.overwrittenFunction(Baler.setIsUnloadingBale, Baler.mrSetIsUnloadingBale)


Baler.mrUpdateUnfinishedBaleThresholdCapacity = function(self)
    if self.mrBalerUnfinishedBaleThreshold~=nil then
        self.spec_baler.canUnloadUnfinishedBale = true
        self.spec_baler.unfinishedBaleThreshold = self:getFillUnitCapacity(self.spec_baler.fillUnitIndex) * self.mrBalerUnfinishedBaleThreshold
    end
end




