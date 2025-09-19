
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
--Fix reverse light for MR = only active when a reverse gear is active
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
Lights.mrOnVehiclePhysicsUpdate = function(self, superFunc, acceleratorPedal, brakePedal, automaticBrake, currentSpeed)

    self:setBrakeLightsVisibility(not automaticBrake and math.abs(brakePedal) > 0)

    --only light on reverse light if moving
    if currentSpeed < -self.spec_lights.reverseLightActivationSpeed then
        local vehicleToCheck = self
        --we are attached to a tractor vehicle = check tractor vehicle
        if self.rootVehicle~=nil then
            vehicleToCheck = self.rootVehicle
        end

        if vehicleToCheck.spec_motorized~=nil then
            self:setReverseLightsVisibility(vehicleToCheck.spec_motorized.motor.currentDirection==-1)
            return
        end
    end

    self:setReverseLightsVisibility(false)

end
Lights.onVehiclePhysicsUpdate = Utils.overwrittenFunction(Lights.onVehiclePhysicsUpdate, Lights.mrOnVehiclePhysicsUpdate)



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