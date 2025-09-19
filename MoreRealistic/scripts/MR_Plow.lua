---Returns current wear multiplier
-- @return float dirtMultiplier current wear multiplier
Plow.getWearMultiplier = function(self, superFunc)
    local multiplier = superFunc(self)

    local spec = self.spec_plow
    if spec.isWorking then
        multiplier = multiplier + self:getWorkWearMultiplier() * (self:getLastSpeed() / spec.speedLimit)^1.5 --MR : more difference between "high" and "low" working speed
    end

    return multiplier
end