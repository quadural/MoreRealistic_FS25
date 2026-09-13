---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- MR : allow more freeplay between forks and bales
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------


MountableObject.mrUpdateDynamicMountJointForceLimit = function(self, dt)

    if self.forceLimitUpdate.raycastActive and self.forceLimitUpdate.timer == MountableObject.FORCE_LIMIT_UPDATE_TIME then
        if self:isa(Bale) and self.dynamicMountType==MountableObject.MOUNT_TYPE_DYNAMIC and self.dynamicMountJointIndex~=nil then
            --local mass = self:getMass()
            if not self.dynamicMountSingleAxisFreeX then
                --X axis - this is straw/hay - allow some free play
                setJointTranslationLimit(self.dynamicMountJointIndex, 0, true, -0.02, 0.02)
                --setJointLinearDrive(self.dynamicMountJointIndex, 0, false, true, 0, 0, 100*mass, 100*mass, 10*mass)
            end
            if not self.dynamicMountSingleAxisFreeY then
                --Y axis - this is straw/hay - allow some free play
                setJointTranslationLimit(self.dynamicMountJointIndex, 1, true, -0.02, 0.02)
                --setJointLinearDrive(self.dynamicMountJointIndex, 1, false, true, 0, 0, 100*mass, 100*mass, 10*mass)
            end
        end
    end

end
MountableObject.updateDynamicMountJointForceLimit = Utils.appendedFunction(MountableObject.updateDynamicMountJointForceLimit, MountableObject.mrUpdateDynamicMountJointForceLimit)