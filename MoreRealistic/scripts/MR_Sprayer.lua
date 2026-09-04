

Sprayer.mrGetSprayerUsage = function(self, superFunc, fillType, dt)

    --2024/11/24 - this function is called for each frame in the game (even when we are in the shop, purchasing the equipment)
    if self:getIsTurnedOn() then
        local factor = self:getLastSpeed()/self.speedLimit
        factor = math.clamp(factor, 0.1, 1.2)
    --    print("test sprayer usage factor : ".. factor)
        local liters = superFunc(self, fillType, dt)

        if not self.spec_sprayer.isFertilizerSprayer and self.spec_sprayer.doubledAmountIsActive then
            liters = liters * 2
        end

        return liters * factor
    end

    return 0

end
Sprayer.getSprayerUsage = Utils.overwrittenFunction(Sprayer.getSprayerUsage, Sprayer.mrGetSprayerUsage)


Sprayer.mrRegisterOverwrittenFunctions = function(vehicleType, superFunc)
    superFunc(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getDischargeNodeEmptyFactor", Sprayer.mrGetDischargeNodeEmptyFactor)
end
Sprayer.registerOverwrittenFunctions = Utils.overwrittenFunction(Sprayer.registerOverwrittenFunctions, Sprayer.mrRegisterOverwrittenFunctions)


Sprayer.mrGetDischargeNodeEmptyFactor = function(self, superFunc, dischargeNode)

    local parentFactor = superFunc(self, dischargeNode)

    if self.mrIsMrVehicle then
        parentFactor = parentFactor * RealisticMain.SPRAYER_EMPTYSPEED_FX
    end

    return parentFactor
end

--remove the double amount limited speed
--with Mr, the usage already take into account the "double amount"
Sprayer.getRawSpeedLimit = function(self, superFunc)
    if not self.mrIsMrManureSpreader then
        local spec = self.spec_sprayer
        local sprayType
        if spec.workAreaParameters ~= nil then
            sprayType = spec.workAreaParameters.sprayType
        end

        if self:getSprayerDoubledAmountActive(sprayType) and self:getIsTurnedOn() then
            return spec.doubledAmountSpeed
        end
    end
    return superFunc(self)
end


--optimized
Sprayer.getIsSprayTypeActive = function(self, sprayType)
    if sprayType.fillTypes ~= nil then
        local retValue = false

        local currentFillType = self:getFillUnitFillType(sprayType.fillUnitIndex or self.spec_sprayer.fillUnitIndex)
        for _, fillType in ipairs(sprayType.fillTypes) do
            if currentFillType == g_fillTypeManager:getFillTypeIndexByName(fillType) then
                retValue = true
                break --MR
            end
        end

        return retValue --MR

    end

    return true
end