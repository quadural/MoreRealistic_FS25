---Returns current wear multiplier
-- @return float dirtMultiplier current wear multiplier
Cultivator.getWearMultiplier = function(self, superFunc)
    local spec = self.spec_cultivator
    local multiplier = superFunc(self)

    if spec.isWorking then
        multiplier = multiplier + self:getWorkWearMultiplier() * (self:getLastSpeed() / spec.speedLimit)^1.5 --MR : more difference between "high" and "low" working speed
    end

    return multiplier
end