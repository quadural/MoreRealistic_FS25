

---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
--Disable brake light when AI has finished his task and get out of the vehicle
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
Lights.mrOnAIDriveableEnd = function(self, superFunc)
    superFunc(self)
    self:setBrakeLightsVisibility(false)
end
Lights.onAIDriveableEnd = Utils.overwrittenFunction(Lights.onAIDriveableEnd, Lights.mrOnAIDriveableEnd)


---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
--ReverseLight = active when reverse gear engaged
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
Lights.mrOnVehiclePhysicsUpdate = function(self, superFunc, acceleratorPedal, brakePedal, automaticBrake, currentSpeed)

    self:setBrakeLightsVisibility(not automaticBrake and math.abs(brakePedal) > 0)

    local reverseLightNeeded = false
    local reverserDirection = self.getReverserDirection == nil and 1 or self:getReverserDirection()
    if reverserDirection == 1 then --we only want reverse light when there is no "reverse position driving" active (Example : valtra twintrac)
        if self.spec_motorized~=nil and self.spec_motorized.motor~=nil then --there is a "motor" => we only check if the "rear gear" is engaged
            if self.spec_motorized.motor.currentDirection == -1 and (self.movingDirection~=1 or currentSpeed<0.00027) then --0.00027 = 1kph
                reverseLightNeeded = true
            end
        else
            reverseLightNeeded = currentSpeed < -self.spec_lights.reverseLightActivationSpeed
        end
    end
    self:setReverseLightsVisibility(reverseLightNeeded)

end
Lights.onVehiclePhysicsUpdate = Utils.overwrittenFunction(Lights.onVehiclePhysicsUpdate, Lights.mrOnVehiclePhysicsUpdate)

---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
--ReverseLight = when the rear drive is engaged (reverse light already active) and we attach a trailer, we want the trailer reverse light to be lit too
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
Lights.mrOnPostAttach = function(self, superFunc, attacherVehicle, inputJointDescIndex, jointDescIndex)

    if attacherVehicle.spec_lights and attacherVehicle.spec_lights.reverseLightsVisibility then
        self.spec_lights.reverseLightsVisibility = true
    end

    superFunc(self, attacherVehicle, inputJointDescIndex, jointDescIndex)
end
Lights.onPostAttach = Utils.overwrittenFunction(Lights.onPostAttach, Lights.mrOnPostAttach)