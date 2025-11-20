

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
--We don't want the reverse light to display "on/off/on/off" when reversing and changing gears (each time the transmission is in neutral during change, the reverse light is off when there is not enough speed)
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
Lights.mrOnVehiclePhysicsUpdate = function(self, superFunc, acceleratorPedal, brakePedal, automaticBrake, currentSpeed)
    self:setBrakeLightsVisibility(not automaticBrake and math.abs(brakePedal) > 0)

    local reverserDirection = 1
    if self.spec_drivable ~= nil then
        reverserDirection = self.spec_drivable.reverserDirection
    end

    local displayReverseLight = (currentSpeed < -self.spec_lights.reverseLightActivationSpeed or acceleratorPedal < 0) and reverserDirection == 1
    if displayReverseLight then
        self.mrLastLightOnTime = g_time
    elseif reverserDirection == 1 then
        --check timer since last "light on"
        if self.mrLastLightOnTime==nil then self.mrLastLightOnTime=0 end
        if g_time-self.mrLastLightOnTime<1500 then
            displayReverseLight = true --keep the reverse light on at least during 1.5s
        end
    end

    self:setReverseLightsVisibility(displayReverseLight)
end
Lights.onVehiclePhysicsUpdate = Utils.overwrittenFunction(Lights.onVehiclePhysicsUpdate, Lights.mrOnVehiclePhysicsUpdate)