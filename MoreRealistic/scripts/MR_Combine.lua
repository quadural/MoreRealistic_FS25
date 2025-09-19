Combine.mrLoadMrValues = function(self, xmlFile)

    self.mrIsMrCombine = hasXMLProperty(xmlFile, "vehicle.mrCombine")
    if self.mrIsMrCombine then
        self.mrCombineChopperIdlePower = getXMLFloat(xmlFile, "vehicle.mrCombine#chopperIdlePower") or 0
        self.mrCombineChopperPowerFx = getXMLFloat(xmlFile, "vehicle.mrCombine#chopperPowerFx") or 1
        self.mrCombineUnloadingPower = getXMLFloat(xmlFile, "vehicle.mrCombine#unloadingPower") or 0
        self.mrCombineThreshingIdlePower = getXMLFloat(xmlFile, "vehicle.mrCombine#threshingIdlePower") or 0
        self.mrCombineThreshingPowerFx = getXMLFloat(xmlFile, "vehicle.mrCombine#threshingPowerFx") or 1
        self.mrCombineSpotRate = getXMLFloat(xmlFile, "vehicle.mrCombine#irlSpotTonPerHour") or 0 --autocomputed from motor peakPower in "vehicleMotor if 0"
        self.mrCombineSpeedLimitMax = getXMLFloat(xmlFile, "vehicle.mrCombine#maxFieldThreshingSpeed") or 15
        self.mrCombineSpeedLimit = 999
        self.mrCombineLastTonsPerHour = 0
        self.mrCombineLastLitersThreshed = 0
        self.mrCombineLitersPerSecond = 0
        self.mrCombineLitersPerSecondS1 = 0
        self.mrCombineLitersPerSecondS2 = 0
        self.mrCombineLitersBuffer = 0
        self.mrCombineLitersBufferTime = 0
        self.mrCombineLastValidFruitTypeDesc = nil
    end

end

---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- apply RealisticMain.COMBINE_CAPACITY_FX factor to combine harvester pipe discharge speed
-- otherwise, in high yeld crops, the grain tank is filling "faster" than the pipe unloading rate (not true, but we could gain 20-25% more than the full grain tank until the pipe has finished unloading
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
Combine.mrOnPostLoad = function(self, superFunc, savegame)

    superFunc(self, savegame)

    if self.mrIsMrCombine and self.spec_dischargeable~=nil then
        for i=1, #self.spec_dischargeable.dischargeNodes do
            self.spec_dischargeable.dischargeNodes[i].emptySpeed = self.spec_dischargeable.dischargeNodes[i].emptySpeed * RealisticMain.COMBINE_CAPACITY_FX
        end
    end

end
Combine.onPostLoad = Utils.overwrittenFunction(Combine.onPostLoad, Combine.mrOnPostLoad)

---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- apply power consumption function of Ton per hour
-- try to set the best speed limit (near the limit of the combine with the current header and crop)
-- take into account the yield => poor yield = high harvesting speed / best yield = lower harvesting speed)
--
-- 20250831 - new way of limiting combine harvester speed
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
Combine.mrGetActiveConsumedPtoPower = function(self)
    local spec = self.spec_combine
    local isTurnedOn = self:getIsTurnedOn()
    local neededPower = 0

    --pipe
    if self.spec_dischargeable.currentDischargeState~=Dischargeable.DISCHARGE_STATE_OFF then
        neededPower = neededPower + self.mrCombineUnloadingPower
    end

    if isTurnedOn then

        local fruitCapacityFx = 1
        local fruitThreshingFx = 1
        local fruitChopperFx = 1

        local fruitTypeDesc = nil

        --get fruit capacityFx, ThreshingFx and ChopperFx from FruitTypeDesc
        if spec.lastCuttersInputFruitType~=nil then
            fruitTypeDesc = g_fruitTypeManager:getFruitTypeByIndex(spec.lastCuttersInputFruitType)
            if fruitTypeDesc~=nil then
                self.mrCombineLastValidFruitTypeDesc = fruitTypeDesc
            end
        end
        if fruitTypeDesc==nil then
            fruitTypeDesc = self.mrCombineLastValidFruitTypeDesc
        end
        if fruitTypeDesc~=nil then
            fruitCapacityFx = fruitTypeDesc.mrCapacityFx or 1
            fruitThreshingFx = fruitTypeDesc.mrThreshingFx or 1
            fruitChopperFx = fruitTypeDesc.mrChopperFx or 1
        end

        self.mrCombineLitersBuffer = self.mrCombineLitersBuffer + self.mrCombineLastLitersThreshed
        self.mrCombineLastLitersThreshed = 0
        --sample every 750 millisecond
        if g_time>self.mrCombineLitersBufferTime then
            local maxTime = 750
            local totalTime = maxTime + g_time - self.mrCombineLitersBufferTime
            self.mrCombineLitersPerSecond = 1000*self.mrCombineLitersBuffer / totalTime
            self.mrCombineLitersPerSecondS1 = 0.5*self.mrCombineLitersPerSecondS1 + 0.5*self.mrCombineLitersPerSecond --smooth1
            self.mrCombineLitersPerSecondS2 = 0.8*self.mrCombineLitersPerSecondS2 + 0.2*self.mrCombineLitersPerSecond --smooth2
            self.mrCombineLitersBuffer = 0
            self.mrCombineLitersBufferTime = g_time + maxTime
        end

        --threshingSystem
        neededPower = neededPower + self.mrCombineThreshingIdlePower
        if self.mrCombineLitersPerSecondS2>0.1 then
            neededPower = neededPower + self.mrCombineThreshingPowerFx * self.mrCombineLitersPerSecondS2 * 6 * fruitThreshingFx / RealisticMain.COMBINE_CAPACITY_FX
        end

        --chopper
        if spec.isSwathActive==false then
            neededPower = neededPower + self.mrCombineChopperIdlePower
            if self.mrCombineLitersPerSecondS2>0.1 then
                neededPower = neededPower + self.mrCombineChopperPowerFx * self.mrCombineLitersPerSecondS2 * 2.85 * fruitChopperFx / RealisticMain.COMBINE_CAPACITY_FX --about 1KW per ton per hour for wheat (fruitChopperFx==1). 1ton per hour for Wheat = 0.35 liters per second => factor 2.85 to get 1KW
            end
        end

        --update mrCombineSpeedLimit
        --conversion : tons per hour to liter per second
        local maxCapacity = self.mrCombineSpotRate*0.35*RealisticMain.COMBINE_CAPACITY_FX*fruitCapacityFx --Metric Ton per hour to Liters per second. Base "fruit" = wheat // 1000/0.79/3600 liters for wheat = 0.35

        local peakWantedPower = 0.8*self.spec_powerConsumer.sourceMotorPeakPower
        local overloadedFx = 0

        local minSpeedLimit = 2
        local maxSpeedLimit = self.mrCombineSpeedLimitMax




        --check needed power not too high
        overloadedFx = math.sqrt(neededPower/peakWantedPower)

        --check max capacity
        overloadedFx = math.max(overloadedFx, self.mrCombineLitersPerSecondS1/maxCapacity)

        if overloadedFx>1.02 then
            --decrease speed
            --the higher the overloadedFx, the faster the decrease speed
            --up to 1.1 => very slow adjustment
            if overloadedFx<1.1 then
                self.mrCombineSpeedLimit = math.max(minSpeedLimit, self.mrCombineSpeedLimit-g_physicsDtLastValidNonInterpolated/20000) --0.05 per second
            else
                self.mrCombineSpeedLimit = math.max(minSpeedLimit, self.mrCombineSpeedLimit-(overloadedFx^4)*g_physicsDtLastValidNonInterpolated/10000) --0.146 per second when overloadedFx=1.1
            end
        elseif overloadedFx<1 then
            --increase speed
            --the lower the overloadedFx, the faster the increase speed
            self.mrCombineSpeedLimit = math.min(maxSpeedLimit, self.mrCombineSpeedLimit+(1-overloadedFx)*g_physicsDtLastValidNonInterpolated/800)
        end

        --update last ton per hour rate
        if spec.lastCuttersOutputFillType~=nil and spec.lastCuttersOutputFillType~=FillType.UNKNOWN then
            local fillTypeDesc = g_fillTypeManager:getFillTypeByIndex(spec.lastCuttersOutputFillType)
            self.mrCombineLastTonsPerHour = fillTypeDesc.massPerLiter * self.mrCombineLitersPerSecondS2 * 3600
        end

    else
        self.mrCombineLitersPerSecond = 0
        self.mrCombineLitersPerSecondS1 = 0
        self.mrCombineLitersPerSecondS2 = 0
        self.mrCombineSpeedLimit = 999
        self.mrCombineLastValidFruitTypeDesc = nil
    end


    return neededPower

end


Combine.mrAddCutterArea = function(self, superFunc, area, liters, inputFruitType, outputFillType, strawRatio, farmId, cutterLoad)

    if self.mrIsMrCombine then
        --we want to store the number of liters threshed by "frame"
        self.mrCombineLastLitersThreshed = self.mrCombineLastLitersThreshed + liters
    end

    return superFunc(self, area, liters, inputFruitType, outputFillType, strawRatio, farmId, cutterLoad)

end
Combine.addCutterArea = Utils.overwrittenFunction(Combine.addCutterArea, Combine.mrAddCutterArea)
