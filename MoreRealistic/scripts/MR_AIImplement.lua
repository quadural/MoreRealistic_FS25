AIImplement.mrGetDoConsumePtoPower = function(self, superFunc, superFunc0)
    if self.mrIsMrVehicle then
        return superFunc0(self) -- we don't want AI to have miraculous power (example : combine turned on, but 0 power consumed when doing headlands)
    else
        return superFunc(self, superFunc0)
    end
end
AIImplement.getDoConsumePtoPower = Utils.overwrittenFunction(AIImplement.getDoConsumePtoPower, AIImplement.mrGetDoConsumePtoPower)