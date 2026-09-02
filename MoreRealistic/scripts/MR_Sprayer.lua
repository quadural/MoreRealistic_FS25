

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

        if dt>0 then
            self.mrSprayerLastLitersPerSecondAtSpeedLimit = liters*1000/dt
            self.mrSprayerLastLitersPerSecond = self.mrSprayerLastLitersPerSecondAtSpeedLimit * factor
        end

        liters = liters * factor
        return liters
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
    return superFunc(self)
end