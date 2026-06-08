TurnOnVehicle.mrInitSpecialization = function(_, superFunc)
    superFunc()
    local schema = Vehicle.xmlSchema
    schema:register(XMLValueType.FLOAT, TurnOnVehicle.TURNED_ON_ANIMATION_XML_PATH .. "#mrMovingSpeedRatio", "varying anim speed depending on the ground speed")
end
TurnOnVehicle.initSpecialization = Utils.overwrittenFunction(TurnOnVehicle.initSpecialization, TurnOnVehicle.mrInitSpecialization)


TurnOnVehicle.mrLoadTurnedOnAnimationFromXML = function(self, superFunc, xmlFile, key, turnedOnAnimation)
    if superFunc(self, xmlFile, key, turnedOnAnimation) then
        turnedOnAnimation.mrMovingSpeedRatio = self.xmlFile:getValue(key.."#mrMovingSpeedRatio", 0)
        return true
    end
    return false
end
TurnOnVehicle.loadTurnedOnAnimationFromXML = Utils.overwrittenFunction(TurnOnVehicle.loadTurnedOnAnimationFromXML, TurnOnVehicle.mrLoadTurnedOnAnimationFromXML)


-- MR : example = we want to be able to modulate the reel speed for cutter bar (combine harvester)
-- mrMovingSpeedRatio = ratio between the ground speed and the animation scale speed (1 means we want the animation to runs at a speedScale of 1 when the ground speed is 1 meter per second)
TurnOnVehicle.mrOnUpdate = function(self, superFunc, dt, isActiveForInput, isActiveForInputIgnoreSelection, isSelected)

    superFunc(self, dt, isActiveForInput, isActiveForInputIgnoreSelection, isSelected)

    local spec = self.spec_turnOnVehicle
    for i=1, #spec.turnedOnAnimations do
        local turnedOnAnimation = spec.turnedOnAnimations[i]
        if turnedOnAnimation.isTurnedOn and turnedOnAnimation.speedDirection == 0 and turnedOnAnimation.mrMovingSpeedRatio~=0 then
            local currentGroundSpeed = self.lastSpeedSmoothed*1000 -- meters per second
            local wantedSpeedRatio = math.clamp(turnedOnAnimation.mrMovingSpeedRatio*currentGroundSpeed, 0.3, 1) --limit the anim speedscale between 0.3 and 1 times the genuine speedscale

            local diff = turnedOnAnimation.currentSpeed-wantedSpeedRatio

            if math.abs(diff)>0.05 then
                --increase or decrease speed depending on current speed
                local direction = diff>0 and -1 or 1
                turnedOnAnimation.currentSpeed = math.clamp(turnedOnAnimation.currentSpeed + direction * dt/10000, 0.3, 1) -- 0.3 to 1 in 7 seconds
                self:setAnimationSpeed(turnedOnAnimation.name, turnedOnAnimation.currentSpeed*turnedOnAnimation.speedScale)
            end
        end
    end

end
TurnOnVehicle.onUpdate = Utils.overwrittenFunction(TurnOnVehicle.onUpdate, TurnOnVehicle.mrOnUpdate)



