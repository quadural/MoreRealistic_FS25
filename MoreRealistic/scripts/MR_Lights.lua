

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