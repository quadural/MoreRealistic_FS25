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
        self.mrCombineLastRegulatingAccFactor = 1
        self.mrCombineSpeedBuffer = 0
        self.mrCombineSpeedBufferCount = 0
        self.mrCombineCapacitySpeedLimitCurrent = 999
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
        if spec.lastValidInputFruitType~=nil then
            fruitTypeDesc = g_fruitTypeManager:getFruitTypeByIndex(spec.lastValidInputFruitType)
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

        self.mrCombineSpeedBuffer = self.mrCombineSpeedBuffer + self.lastSpeedReal
        self.mrCombineSpeedBufferCount = self.mrCombineSpeedBufferCount + 1

        --sample every 750 millisecond
        if g_time>self.mrCombineLitersBufferTime then
            local maxTime = 750
            local totalTime = maxTime + g_time - self.mrCombineLitersBufferTime
            self.mrCombineLitersPerSecond = 1000*self.mrCombineLitersBuffer / totalTime
            self.mrCombineLitersPerSecondS1 = 0.5*self.mrCombineLitersPerSecondS1 + 0.5*self.mrCombineLitersPerSecond --smooth1
            self.mrCombineLitersPerSecondS2 = 0.8*self.mrCombineLitersPerSecondS2 + 0.2*self.mrCombineLitersPerSecond --smooth2

            local avgSpeed = 3600 * self.mrCombineSpeedBuffer / self.mrCombineSpeedBufferCount


            self.mrCombineLitersBuffer = 0
            self.mrCombineSpeedBuffer = 0
            self.mrCombineSpeedBufferCount = 0

            self.mrCombineLitersBufferTime = g_time + maxTime

            --conversion : tons per hour to liter per second
            local maxCapacity = self.mrCombineSpotRate*0.35*RealisticMain.COMBINE_CAPACITY_FX*fruitCapacityFx --Metric Ton per hour to Liters per second. Base "fruit" = wheat // 1000/0.79/3600 liters for wheat = 0.35
            if self.mrCombineLitersPerSecondS1<0.1*maxCapacity then
                self.mrCombineCapacitySpeedLimitCurrent = 999
            else
                local capacityFx = 0
                --in the game, compared to IRL, we harvest "cell size" by "cell size" => which means at lower speed, we can get "0 0 something 0 0" etc
                --so we have to smooth the liters per seconds at low harvest speed
                if avgSpeed>11 then
                    capacityFx = maxCapacity / math.max(0.1, self.mrCombineLitersPerSecond)
                elseif avgSpeed>8 then
                    capacityFx = math.pow(maxCapacity / math.max(0.1, self.mrCombineLitersPerSecondS1), 0.6)
                else
                    capacityFx = math.pow(maxCapacity / math.max(0.1, self.mrCombineLitersPerSecondS2), 0.25)
                end

                self.mrCombineCapacitySpeedLimitCurrent = avgSpeed * capacityFx
            end
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

        --local peakWantedPower = 0.8*self.spec_powerConsumer.sourceMotorPeakPower
        local engineLoad = 0

        local minSpeedLimit = 2
        local maxSpeedLimit = self.mrCombineSpeedLimitMax
        self.mrCombineSpeedLimit = math.min(maxSpeedLimit, self.mrCombineSpeedLimit)


        --check needed power not too high
        --overloadedFx = math.sqrt(neededPower/peakWantedPower)

        --20260306 - now rely on the engine smooth load percent
        if self.spec_motorized then
            engineLoad = self.spec_motorized.smoothedLoadPercentage
        else
            local attacherVehicle = self:getAttacherVehicle()
            if attacherVehicle ~= nil and attacherVehicle.spec_motorized then
                engineLoad = attacherVehicle.spec_motorized.smoothedLoadPercentage
            end
        end

        --check max capacity
        --overloadedFx = math.max(overloadedFx, self.mrCombineLitersPerSecondS1/maxCapacity)

        if self.mrCombineSpeedLimit>self.mrCombineCapacitySpeedLimitCurrent then
            --we are going too fast compared to the combine harvesting capacity (nothing to do with power = IRL the combine would be plugged or losing grain)
            local spd = self.mrCombineSpeedLimit-self.mrCombineCapacitySpeedLimitCurrent
            self.mrCombineSpeedLimit = math.max(self.mrCombineSpeedLimit-spd*g_physicsDtLastValidNonInterpolated/2000, self.mrCombineCapacitySpeedLimitCurrent, minSpeedLimit) --deceleration = 2 seconds to reach the difference
        elseif self.mrCombineLitersPerSecond==0 then
            --no more crop ?
            self.mrCombineSpeedLimit = math.min(self.mrCombineSpeedLimit+g_physicsDtLastValidNonInterpolated/500, maxSpeedLimit) -- acc = 2kph per second
        elseif engineLoad>1.005 then
            --engine overloaded = lower the speedlimit
            --local spd = overloadedFx-1
            self.mrCombineSpeedLimit = math.max(self.mrCombineSpeedLimit-g_physicsDtLastValidNonInterpolated/20000, minSpeedLimit) --acc = 0.05kph per second
        elseif engineLoad<0.95 then
            --no enough engine load -> increase speed limit
            local spd = 1-engineLoad
            self.mrCombineSpeedLimit = math.min(self.mrCombineSpeedLimit+spd*g_physicsDtLastValidNonInterpolated/1000, self.mrCombineCapacitySpeedLimitCurrent, maxSpeedLimit) --acc = 0.5kph per second @50% engine load
        end

--[[
        if overloadedFx<1 then
            --increase speed
            --the lower the overloadedFx, the faster the increase speed
            --self.mrCombineSpeedLimit = math.min(maxSpeedLimit, self.mrCombineSpeedLimit+(1-overloadedFx)*g_physicsDtLastValidNonInterpolated/800)

            --20260409
            --accFactor with time
            if self.mrCombineLitersPerSecond==0 then
                --nothing to "eat" = faster increase speed
                self.mrCombineLastRegulatingAccFactor = 1
            else
                self.mrCombineLastRegulatingAccFactor = math.min(1, self.mrCombineLastRegulatingAccFactor + g_physicsDtLastValidNonInterpolated/2000)
            end
            self.mrCombineSpeedLimit = math.min(maxSpeedLimit, self.mrCombineSpeedLimit+self.mrCombineLastRegulatingAccFactor*g_physicsDtLastValidNonInterpolated/800)
        else
            self.mrCombineLastRegulatingAccFactor = 0
            if overloadedFx>1.02 then
                --decrease speed
                --the higher the overloadedFx, the faster the decrease speed
                --up to 1.1 => very slow adjustment
                --if overloadedFx<1.1 then
                    self.mrCombineSpeedLimit = math.max(minSpeedLimit, self.mrCombineSpeedLimit-(overloadedFx-1)*g_physicsDtLastValidNonInterpolated/2000) --0.05 per second @1.1
                --else
                    --self.mrCombineSpeedLimit = math.max(minSpeedLimit, self.mrCombineSpeedLimit-(overloadedFx^4)*g_physicsDtLastValidNonInterpolated/10000) --0.146 per second when overloadedFx=1.1
                --end
            end
        end

        self.mrCombineSpeedLimit = math.min(self.mrCombineSpeedLimit, self.mrCombineCapacitySpeedLimitCurrent)

        --]]

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
        self.mrCombineLastRegulatingAccFactor = 1
        self.mrCombineCapacitySpeedLimitCurrent = 999
    end


    return neededPower

end


Combine.mrAddCutterArea = function(self, superFunc, area, liters, inputFruitType, outputFillType, strawRatio, farmId, cutterLoad)

    --2025/10/24 - remove PrecisionFarming yield boost
    if FS25_precisionFarming~=nil then
        liters = liters * 0.85
    end

    if self.mrIsMrCombine then
        --we want to store the number of liters threshed by "frame"
        self.mrCombineLastLitersThreshed = self.mrCombineLastLitersThreshed + liters
    end

    return superFunc(self, area, liters, inputFruitType, outputFillType, strawRatio, farmId, cutterLoad)

end
Combine.addCutterArea = Utils.overwrittenFunction(Combine.addCutterArea, Combine.mrAddCutterArea)
