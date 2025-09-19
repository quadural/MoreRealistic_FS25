--2024/12/27 : FS25 v1.4 = fix bug :
--when driving in reverse direction (backward) : if the speed is above 7.2kph, the "driver" is depressing the brake pedal instead of the accelerator pedal
--bug only present when "manual direction change" is set to true
Drivable.mrGetDecelerationAxis = function(self, superFunc)

    if self.spec_wheels and self.spec_wheels.brakePedal>0 then
        self.mrLastBrakeTime = g_time
        return self.spec_wheels.brakePedal>0.05 and self.spec_wheels.brakePedal or 0
    end
    return 0

end
Drivable.getDecelerationAxis = Utils.overwrittenFunction(Drivable.getDecelerationAxis, Drivable.mrGetDecelerationAxis)



Drivable.mrGetAccelerationAxis = function(self, superFunc)

    if self.spec_wheels then
        self.mrLastBrakeTime = self.mrLastBrakeTime or 0
        if (g_time-self.mrLastBrakeTime)>500 then
            return math.abs(self.spec_drivable.axisForward)
        end
    end
    return 0

end
Drivable.getAccelerationAxis = Utils.overwrittenFunction(Drivable.getAccelerationAxis, Drivable.mrGetAccelerationAxis)