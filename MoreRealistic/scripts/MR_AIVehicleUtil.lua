---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Limit AI driving speed when near the target to avoid getting too far
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
AIVehicleUtil.mrDriveAlongCurvature = function(self, superFunc, dt, curvature, maxSpeed, acceleration)
    local spec = self.spec_aiDrivable
    if spec~=nil then
        if spec.distanceToTarget~=nil then
            maxSpeed = math.min(maxSpeed, math.max(6, spec.distanceToTarget)) --maxSpeed in kph
        end
    end
    superFunc(self, dt, curvature, maxSpeed, acceleration)
end
AIVehicleUtil.driveAlongCurvature = Utils.overwrittenFunction(AIVehicleUtil.driveAlongCurvature, AIVehicleUtil.mrDriveAlongCurvature)


---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Limit AI driving speed when near the target to avoid getting too far
-- bug in "AIFieldWorker:updateAIFieldWorker" => lookAheadDistance should be greater while turning to reduce speed compared to straight line
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
AIVehicleUtil.mrDriveToPoint = function(self, superFunc, dt, acceleration, allowedToDrive, moveForwards, tX, tZ, maxSpeed, doNotSteer)

    if self.finishedFirstUpdate then
        --we can't get the distanceToStop (local variable) and so, we only interfer while AI is turning
        if self:getAIFieldWorkerIsTurning() then --AI reversing, or turning at field corner
            local rotFx = math.abs(self.rotatedTime)
            if rotFx>0.1 then
                rotFx = rotFx/math.max(self.maxRotTime, -self.minRotTime)
                maxSpeed = math.min(12-rotFx*7, maxSpeed) -- from 12 to 6
            else
                maxSpeed = math.min(12, maxSpeed)
            end
        end

        superFunc(self, dt, acceleration, allowedToDrive, moveForwards, tX, tZ, maxSpeed, doNotSteer)
    end

end
AIVehicleUtil.driveToPoint = Utils.overwrittenFunction(AIVehicleUtil.driveToPoint, AIVehicleUtil.mrDriveToPoint)



---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- This function doesn't seem to be called in the base game engine
-- But it is used by "AutoDrive" mod for example to control the AI
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- AIVehicleUtil.mrDriveInDirection = function(self, superFunc, dt, steeringAngleLimit, acceleration, slowAcceleration, slowAngleLimit, allowedToDrive, moveForwards, lx, lz, maxSpeed, slowDownFactor)

--     superFunc(self, dt, steeringAngleLimit, acceleration, slowAcceleration, slowAngleLimit, allowedToDrive, moveForwards, lx, lz, maxSpeed, slowDownFactor)

-- end
-- AIVehicleUtil.driveInDirection = Utils.overwrittenFunction(AIVehicleUtil.driveInDirection, AIVehicleUtil.mrDriveInDirection)
