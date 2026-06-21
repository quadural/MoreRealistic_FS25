Baler.MR_MIN_SPEED_LIMIT = 5

Baler.mrLoadMrValues = function(self, xmlFile)

    self.mrIsMrBaler = hasXMLProperty(xmlFile, "vehicle.mrBaler")
    if self.mrIsMrBaler then

        self.mrBalerIdlePower = getXMLFloat(xmlFile, "vehicle.mrBaler#idlePower") or 10
        self.mrBalerPowerIncreaseWithFeedingKilosPerSecond = getXMLFloat(xmlFile, "vehicle.mrBaler#powerIncreaseWithFeedingKilosPerSecond") or 2
        self.mrBalerPowerIncreaseWithBaleMass = getXMLFloat(xmlFile, "vehicle.mrBaler#powerIncreaseWithBaleMass") or 0
        self.mrBalerMaxTonsPerHour = getXMLFloat(xmlFile, "vehicle.mrBaler#maxTonsPerHour") or 50
        self.mrBalerGrassCapacityFx = getXMLFloat(xmlFile, "vehicle.mrBaler#grassCapacityFx") or 1.5
        self.mrBalerUnfinishedBaleThreshold = getXMLFloat(xmlFile, "vehicle.mrBaler#unfinishedBaleThreshold")
        self.mrBalerDensityFactor = getXMLFloat(xmlFile, "vehicle.mrBaler#densityFactor") or 1

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
        self.mrBalerLastNeededPower = 0
        self.mrBalerSpeedLimit = 999


        self.mrBalerNettingTimer = 0
        self.mrBalerNettingDuration = 1000 * (getXMLFloat(xmlFile, "vehicle.mrBaler#nettingDuration") or 0) --seconds to milliseconds
        self.mrBalerHasNettingDuration = self.mrBalerNettingDuration>0

    end

end



Baler.mrGetActiveConsumedPtoPower = function(self)
    local spec = self.spec_baler
    local isTurnedOn = self:getIsTurnedOn()
    local neededPower = 0

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
            local maxTime = 1000
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

        local currentMaxBalerTonsPerHour = self.mrBalerMaxTonsPerHour
        local powerFx = 1
        local currentKilosPerSecond = 0
        --local currentKilosPerSecondS = 0
        if desc~=nil then
            currentKilosPerSecond = self.mrBalerLitersPerSecond * desc.massPerLiter * 1000 -- 1000 => massPerLiter is in tons, we want kilos
            if desc.name=="GRASS_WINDROW" or desc.name=="GRASS" then
                currentKilosPerSecond = currentKilosPerSecond * RealisticMain.BALER_GRASS_MASS_FX
                currentMaxBalerTonsPerHour = currentMaxBalerTonsPerHour * self.mrBalerGrassCapacityFx
                powerFx = math.sqrt(1 / self.mrBalerGrassCapacityFx)
            end
        end

        self.mrBalerLastTonsPerHour = currentKilosPerSecond * 3.6  --3.6 = kilos per seconds to tons per hour
        self.mrBalerLastTonsPerHourAvg = 0.995*self.mrBalerLastTonsPerHourAvg + 0.005*self.mrBalerLastTonsPerHour

        --power of the feeding system
        if desc~=nil and self.mrBalerPowerIncreaseWithFeedingKilosPerSecond>0 then
            neededPower = neededPower + currentKilosPerSecond * self.mrBalerPowerIncreaseWithFeedingKilosPerSecond * powerFx
        end

        --idle power
        neededPower = neededPower + self.mrBalerIdlePower

        if self.mrBalerSpeedLimit==999 then
            self.mrBalerSpeedLimit = self.speedLimit
        end

        --0.9 factor to prevent going above "mrBalerMaxTonsPerHour" most of the time. "mrBalerMaxTonsPerHour" should really be a "high" limit.


        local invCapacityFx = 0.9*currentMaxBalerTonsPerHour/math.max(1, math.max(self.mrBalerLastTonsPerHour,self.mrBalerLastTonsPerHourAvg))

        --**************
        --PROBLEM : when using the "lastSpeedReal" = if we are not working, but pto is on, when making a turn, the baler "lastSpeedReal" is lower than the tractor speed = we limit the tractor speed for nothing
        --local currentSpd = self.lastSpeedReal*3600--math.min(self.mrBalerSpeedLimit, self.lastSpeedReal*3600+1)

        --PROBLEM : when using the self.mrBalerSpeedLimit, the response time is "horrible" (ping-pong effect)
        --local currentSpd = self.mrBalerSpeedLimit

        --using the rootvehicle speed
        local rootAttacherVehicle = self.rootVehicle --return self when there is only one vehicle
        local currentSpd = rootAttacherVehicle.lastSpeedReal*3600


        local powFx = 1
        if invCapacityFx<1 then --too much material
            powFx = 0.2
        elseif currentSpd>10 then
            powFx = 0.05
        elseif currentSpd>7 then
            powFx = 0.1
        else
            powFx = 0.2
        end
        self.mrBalerSpeedLimit = currentSpd * math.pow(invCapacityFx, powFx) --flatten the response
        self.mrBalerSpeedLimit = math.clamp(self.mrBalerSpeedLimit, Baler.MR_MIN_SPEED_LIMIT, self.speedLimit)

    else -- not turned on

        self.mrBalerLastLitersPickedUp = 0
        self.mrBalerLitersPerSecond = 0
        self.mrBalerLitersPerSecondS = 0
        self.mrBalerLitersBuffer = 0
        self.mrBalerLastTonsPerHour = 0
        self.mrBalerLastTonsPerHourAvg = 0
        self.mrBalerSpeedLimit = 999
        self.mrBalerLastNeededPower = 0

    end

    if self.mrBalerLastNeededPower==0 then
        self.mrBalerLastNeededPower = neededPower
    else
        self.mrBalerLastNeededPower = 0.99*self.mrBalerLastNeededPower + 0.01*neededPower
    end

    return self.mrBalerLastNeededPower

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


--manage netting timer
Baler.mrOnUpdateTick = function(self, superFunc, dt, isActiveForInput, isActiveForInputIgnoreSelection, isSelected)

    if self.mrBalerHasNettingDuration and self:getIsTurnedOn() then
        if self.mrBalerNettingTimer>0 then
            self.mrBalerNettingTimer = self.mrBalerNettingTimer - dt
            if self.mrBalerNettingTimer<=0 then
                self.mrBalerNettingTimer = -1
                self:setIsUnloadingBale(true)
                self.mrBalerNettingTimer = 0
            end
        end
    end

    superFunc(self, dt, isActiveForInput, isActiveForInputIgnoreSelection, isSelected)

end
Baler.onUpdateTick = Utils.overwrittenFunction(Baler.onUpdateTick, Baler.mrOnUpdateTick)

--do not allow unloading during the netting time
Baler.mrIsUnloadingAllowed = function(self, superFunc)
    if self.mrBalerHasNettingDuration and self.mrBalerNettingTimer>0 then
        return false
    else
        return superFunc(self)
    end
end
Baler.isUnloadingAllowed = Utils.overwrittenFunction(Baler.isUnloadingAllowed, Baler.mrIsUnloadingAllowed)


--wait for the netting time before actually unloading the bale
Baler.mrSetIsUnloadingBale = function(self, superFunc, isUnloadingBale, noEventSend)

    if self.mrBalerHasNettingDuration and isUnloadingBale and self.mrBalerNettingTimer==0 and not noEventSend then
        self.mrBalerNettingTimer = self.mrBalerNettingDuration
    else
        superFunc(self, isUnloadingBale, noEventSend)
    end

end
Baler.setIsUnloadingBale = Utils.overwrittenFunction(Baler.setIsUnloadingBale, Baler.mrSetIsUnloadingBale)



