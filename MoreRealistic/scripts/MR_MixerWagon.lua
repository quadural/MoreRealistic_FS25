MixerWagon.mrLoadMrValues = function(self, xmlFile)

    self.mrIsMrMixerWagon = hasXMLProperty(xmlFile, "vehicle.mrMixerWagon")
    if self.mrIsMrMixerWagon then
        self.mrIsMrMixerWagonIdlePower = getXMLFloat(xmlFile, "vehicle.mrMixerWagon#idlePower") or 5
        self.mrIsMrMixerWagonMixingPowerFx = getXMLFloat(xmlFile, "vehicle.mrMixerWagon#mixingPowerFx") or 1
        self.mrIsMrMixerWagonUnloadingPower = getXMLFloat(xmlFile, "vehicle.mrMixerWagon#unloadingPower") or 0
    end

end


MixerWagon.mrGetActiveConsumedPtoPower = function(self)

    local spec = self.spec_mixerWagon

    local tipState = self:getTipState()
    local isTurnedOn = self:getIsTurnedOn()
    local isDischarging = tipState == Trailer.TIPSTATE_OPENING or tipState == Trailer.TIPSTATE_OPEN

    local neededPower = 0

    if spec.activeTimer > 0 or isTurnedOn or isDischarging then

        self.mrPowerConsumerForcePtoRpm = true

        neededPower = self.mrIsMrMixerWagonIdlePower

        if isDischarging then
            neededPower = neededPower + self.mrIsMrMixerWagonUnloadingPower
        end

        local mixingPower = self.mrIsMrMixerWagonMixingPowerFx * 6 * math.pow(MixerWagon.mrGetContentMass(spec), 0.9)

        neededPower = neededPower + mixingPower

    end

    return neededPower

end












---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- MR : 2000L of straw (80kg) + 5000L of silage (3750kg) + 5000L of hay (300kg) doesn't mean 12000L of forage/TMR (5280kg)
-- we should get 4130kg == 9386L of TMR
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

MixerWagon.addFillUnitFillLevel = function(self, superFunc, farmId, fillUnitIndex, fillLevelDelta, fillTypeIndex, toolType, fillPositionData)
    local spec = self.spec_mixerWagon

    if fillUnitIndex ~= spec.fillUnitIndex then
        return superFunc(self, farmId, fillUnitIndex, fillLevelDelta, fillTypeIndex, toolType, fillPositionData)
    end

    if #spec.mixerWagonFillTypes == 0 then
        if fillLevelDelta ~= 0 and self:getIsSynchronized() then
            spec.activeTimer = spec.activeTimerMax
        end

        return superFunc(self, farmId, fillUnitIndex, fillLevelDelta, fillTypeIndex, toolType, fillPositionData)
    end

    local oldFillLevel = self:getFillUnitFillLevel(fillUnitIndex)

    local mixerWagonFillType = spec.fillTypeToMixerWagonFillType[fillTypeIndex]

    -- allow to put forage back to mixer. Split it up into valid forage mixing ratios
    if fillTypeIndex == FillType.FORAGE and fillLevelDelta > 0 then
        for _, entry in pairs(spec.mixerWagonFillTypes) do
            local delta = fillLevelDelta * entry.ratio
            self:addFillUnitFillLevel(farmId, fillUnitIndex, delta, next(entry.fillTypes), toolType, fillPositionData)
        end

        return fillLevelDelta
    end

    if mixerWagonFillType == nil then
        -- used for discharge
        if fillLevelDelta < 0 and oldFillLevel > 0 then
            -- remove values from all fill types such that the ratio doesn't change
            fillLevelDelta = math.max(fillLevelDelta, -oldFillLevel)

            local newFillLevel = 0
            for _, entry in pairs(spec.mixerWagonFillTypes) do --MR : better readability code + take into account mrFillMass too (discharging time here)
                local ratio = fillLevelDelta/oldFillLevel --ratio is negative here
                entry.fillLevel = entry.fillLevel * math.max(0, 1 + ratio)
                entry.mrFillMass = entry.mrFillMass * math.max(0, 1 + ratio)
                newFillLevel = newFillLevel + entry.fillLevel
            end

            if newFillLevel < 0.1 then
                for _, entry in pairs(spec.mixerWagonFillTypes) do
                    entry.fillLevel = 0
                    entry.mrFillMass = 0 --MR : take into account mrFillMass too
                end
                fillLevelDelta = -oldFillLevel
            end

            self:raiseDirtyFlags(spec.dirtyFlag)
            local ret = superFunc(self, farmId, fillUnitIndex, fillLevelDelta, fillTypeIndex, toolType, fillPositionData)
            return ret
        end

        return 0
    end

    --MR : better optimized code + store the mass of the product added
    local desc = g_fillTypeManager:getFillTypeByIndex(fillTypeIndex) --MR : we need the "massPerLiter"
    if fillLevelDelta > 0 then
        local capacity = self:getFillUnitCapacity(fillUnitIndex)
        local free = capacity - oldFillLevel
        fillLevelDelta = math.min(free, fillLevelDelta)
        mixerWagonFillType.fillLevel = mixerWagonFillType.fillLevel + fillLevelDelta

        --tons. We want to store the mass of "ingredients"
        mixerWagonFillType.mrFillMass = mixerWagonFillType.mrFillMass + desc.massPerLiter * fillLevelDelta

        if self:getIsSynchronized() then
            spec.activeTimer = spec.activeTimerMax
        end
    else
        mixerWagonFillType.fillLevel = math.max(0, mixerWagonFillType.fillLevel + fillLevelDelta)
        --discharging a single mixerWagonFillType
        mixerWagonFillType.mrFillMass = math.max(0, mixerWagonFillType.mrFillMass + desc.massPerLiter * fillLevelDelta)
    end

    local newFillLevel = 0
    for _, fillType in pairs(spec.mixerWagonFillTypes) do
        newFillLevel = newFillLevel + fillType.fillLevel
    end
    newFillLevel = math.clamp(newFillLevel, 0, self:getFillUnitCapacity(fillUnitIndex))

    local newFillType = FillType.UNKNOWN
    local isSingleFilled = false
    local isForageOk = false

    for _, fillType in pairs(spec.mixerWagonFillTypes) do
        if newFillLevel == fillType.fillLevel then
            isSingleFilled = true
            newFillType = next(mixerWagonFillType.fillTypes)
            break
        end
    end

    if not isSingleFilled then
        isForageOk = true
        for _, fillType in pairs(spec.mixerWagonFillTypes) do
            if fillType.fillLevel < fillType.minPercentage * newFillLevel - 0.01 or fillType.fillLevel > fillType.maxPercentage * newFillLevel + 0.01 then
                isForageOk = false
                break
            end
        end
    end

    if isForageOk then
        newFillType = FillType.FORAGE
    elseif not isSingleFilled then
        newFillType = FillType.FORAGE_MIXING
    end

    self:raiseDirtyFlags(spec.dirtyFlag)

    self:setFillUnitFillType(fillUnitIndex, newFillType)

    return superFunc(self, farmId, fillUnitIndex, newFillLevel-oldFillLevel, newFillType, toolType, fillPositionData)

end


---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- MR : takes into account BALE_SILAGE_MASS_FX
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
MixerWagon.onUpdate = function(self, dt, isActiveForInput, isActiveForInputIgnoreSelection, isSelected)
    local spec = self.spec_mixerWagon

    local tipState = self:getTipState()
    local isTurnedOn = self:getIsTurnedOn()
    local isDischarging = tipState == Trailer.TIPSTATE_OPENING or tipState == Trailer.TIPSTATE_OPEN

    if self:getIsPowered() and (spec.activeTimer > 0 or isTurnedOn or isDischarging) then
        spec.activeTimer = spec.activeTimer - dt
        g_animationManager:startAnimations(spec.mixAnimationNodes)
    else
        g_animationManager:stopAnimations(spec.mixAnimationNodes)
    end

    if self.isServer then

        local fillEffectsFillType = FillType.UNKNOWN
        if self:getFillUnitFreeCapacity(spec.fillUnitIndex) > 0 then
            for i=1, #spec.baleTriggers do
                local baleTrigger = spec.baleTriggers[i]
                if not baleTrigger.needsSetIsTurnedOn or self:getIsTurnedOn() then
                    for bale, _ in pairs(baleTrigger.balesInTrigger) do
                        local baleFillLevel = bale:getFillLevel()

                        --MR : takes into account silage bale BALE_SILAGE_MASS_FX
                        local fillType = bale:getFillType()
                        local desc = g_fillTypeManager:getFillTypeByIndex(fillType)
                        local mrFillFx = 1
                        if desc.name=="SILAGE" then
                            mrFillFx = RealisticMain.BALE_SILAGE_MASS_FX  --we want to convert a 1000kg silage bale to 1000kg of loose silage at 0.4 density
                        end
                        local deltaFillLevel = math.min(baleTrigger.pickupSpeed * dt * mrFillFx, baleFillLevel) --we don't want the pickup speed to be too fast with silage bales
                        deltaFillLevel = self:addFillUnitFillLevel(self:getOwnerFarmId(), spec.fillUnitIndex, deltaFillLevel, fillType, ToolType.BALE, nil)

                        deltaFillLevel = deltaFillLevel / mrFillFx --we want to convert from "silage bale liters" (coming from grass) to "silage" liters (density = 0.75)

                        baleFillLevel = baleFillLevel - deltaFillLevel

                        if baleFillLevel < 0.01 then
                            bale:delete()
                            baleTrigger.balesInTrigger[bale] = nil
                        else
                            bale:setFillLevel(baleFillLevel) --MR : no need to to that before checking if baleFillLevel<0.01
                        end

                        if baleTrigger.useEffect then
                            fillEffectsFillType = fillType
                        end
                    end
                end
            end
        end

        if fillEffectsFillType == FillType.UNKNOWN then
            if self.getIsShovelEffectState ~= nil then
                local state, fillType = self:getIsShovelEffectState()
                if state then
                    fillEffectsFillType = fillType
                end
            end
        end

        if spec.fillEffectsFillType ~= fillEffectsFillType then
            spec.fillEffectsFillType = fillEffectsFillType
            self:raiseDirtyFlags(spec.effectDirtyFlag)
        end
    end

    if self.isClient then
        local state = spec.fillEffectsFillType ~= FillType.UNKNOWN
        if state ~= spec.fillEffectsState then
            if state then
                g_effectManager:setEffectTypeInfo(spec.fillEffects, spec.fillEffectsFillType)
                g_effectManager:startEffects(spec.fillEffects)
            else
                g_effectManager:stopEffects(spec.fillEffects)
            end

            spec.fillEffectsState = state
        end
    end
end

---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- MR : get the current mixer wagon content mass in tons
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
MixerWagon.mrGetContentMass = function(spec_mixerWagon)
    local newMass = 0
    for _, entry in pairs(spec_mixerWagon.mixerWagonFillTypes) do
        newMass = newMass + entry.mrFillMass
    end
    return newMass
end

---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- MR : save the fillMass of each mixerWagonFillType
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
MixerWagon.mrSaveToXMLFile = function(self, xmlFile, key, usedModNames)
    local spec = self.spec_mixerWagon

    for i, fillType in ipairs(spec.mixerWagonFillTypes) do
        local fillTypeKey = string.format("%s.fillType(%d)", key, i-1)
        xmlFile:setValue(fillTypeKey.."#mrFillMass", fillType.mrFillMass)
    end
end
MixerWagon.saveToXMLFile = Utils.appendedFunction(MixerWagon.saveToXMLFile, MixerWagon.mrSaveToXMLFile)

---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- MR : load the fillMass of each mixerWagonFillType
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
MixerWagon.mrOnPostLoad = function(self, savegame)
    local spec = self.spec_mixerWagon
    if savegame ~= nil then
        for i, entry in ipairs(spec.mixerWagonFillTypes) do
            local fillTypeKey = savegame.key..string.format(".mixerWagon.fillType(%d)#mrFillMass", i-1)
            local fillMass = savegame.xmlFile:getValue(fillTypeKey, 0)
            if fillMass > 0 then
                entry.mrFillMass = fillMass
            end
        end
    end
end
MixerWagon.onPostLoad = Utils.appendedFunction(MixerWagon.onPostLoad, MixerWagon.mrOnPostLoad)

---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- MR : init the fillMass of each mixerWagonFillType to 0
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
MixerWagon.mrOnLoad = function(self, savegame)
    local spec = self.spec_mixerWagon
    for i, entry in ipairs(spec.mixerWagonFillTypes) do
        entry.mrFillMass = 0
    end
end
MixerWagon.onLoad = Utils.appendedFunction(MixerWagon.onLoad, MixerWagon.mrOnLoad)

---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- MR : send the fillMass of each mixerWagonFillType to client on join
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
MixerWagon.mrOnWriteStream = function(self, streamId, connection)
    local spec = self.spec_mixerWagon
    for _, entry in ipairs(spec.mixerWagonFillTypes) do
        streamWriteFloat32(streamId, entry.mrFillMass)
    end
end
MixerWagon.onWriteStream = Utils.appendedFunction(MixerWagon.onWriteStream, MixerWagon.mrOnWriteStream)

---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- MR : read the fillMass of each mixerWagonFillType from server on join
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
MixerWagon.mrOnReadStream = function(self, streamId, connection)
    local spec = self.spec_mixerWagon
    for _, entry in ipairs(spec.mixerWagonFillTypes) do
        entry.mrFillMass = streamReadFloat32(streamId)
    end
end
MixerWagon.onReadStream = Utils.appendedFunction(MixerWagon.onReadStream, MixerWagon.mrOnReadStream)

---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- MR : send the updated values of mrfillMass of each mixerWagonFillType to clients
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
MixerWagon.onWriteUpdateStream = function(self, streamId, connection, dirtyMask)
    if not connection:getIsServer() then --we are on server side
        local spec = self.spec_mixerWagon
        if streamWriteBool(streamId, bit32.band(dirtyMask, spec.dirtyFlag) ~= 0) then
            for _, entry in ipairs(spec.mixerWagonFillTypes) do
                streamWriteFloat32(streamId, entry.fillLevel)
                streamWriteFloat32(streamId, entry.mrFillMass) --add mrfillMass to the updated stream
            end
        end

        if streamWriteBool(streamId, bit32.band(dirtyMask, spec.effectDirtyFlag) ~= 0) then
            streamWriteUIntN(streamId, spec.fillEffectsFillType, FillTypeManager.SEND_NUM_BITS)
        end
    end
end

---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- MR : read the updated values of mrfillMass of each mixerWagonFillType from server
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
MixerWagon.onReadUpdateStream = function(self, streamId, timestamp, connection)
    if connection:getIsServer() then --we are on client side
        local spec = self.spec_mixerWagon
        if streamReadBool(streamId) then
            for _, entry in ipairs(spec.mixerWagonFillTypes) do
                local fillLevel = streamReadFloat32(streamId)
                local delta = fillLevel - entry.fillLevel
                if delta ~= 0 then
                    self:addFillUnitFillLevel(self:getOwnerFarmId(), spec.fillUnitIndex, delta, next(entry.fillTypes), ToolType.UNDEFINED, nil)
                end
                entry.mrFillMass = streamReadFloat32(streamId)
            end
        end

        if streamReadBool(streamId) then
            spec.fillEffectsFillType = streamReadUIntN(streamId, FillTypeManager.SEND_NUM_BITS)
        end
    end
end

---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- MR : add the path to the "mrfillMass" params i nthe savegame xml schema
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
MixerWagon.mrInitSpecialization = function()
    local schemaSavegame = Vehicle.xmlSchemaSavegame
    schemaSavegame:register(XMLValueType.FLOAT, "vehicles.vehicle(?).mixerWagon.fillType(?)#mrFillMass", "Fill mass", 0)
end
MixerWagon.initSpecialization = Utils.appendedFunction(MixerWagon.initSpecialization, MixerWagon.mrInitSpecialization)

---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- MR : refresh the mass display unit when the mixer wagon is activated (example : loading a game, the mixer wagon is already filled)
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
MixerWagon.mrOnTurnedOn = function(self)
    if self.isClient then
        FillUnit.mrRefreshFillUnitDashboard(self, self.spec_mixerWagon.fillUnitIndex)
    end
end
MixerWagon.onTurnedOn = Utils.appendedFunction(MixerWagon.onTurnedOn, MixerWagon.mrOnTurnedOn)