Attachable.mrRegisterInputAttacherJointXMLPaths = function(schema, superFunc, baseName)

    superFunc(schema, baseName)

    --we want to be able to keep one configuration when playing not MR and one config when playing MR
    --thanks to that, a mod vehicle can be MR and nor MR ready
    schema:register(XMLValueType.ANGLE, baseName .. "#mrLowerRotationOffset", "override base game Rotation offset if lowered")

end
Attachable.registerInputAttacherJointXMLPaths = Utils.overwrittenFunction(Attachable.registerInputAttacherJointXMLPaths, Attachable.mrRegisterInputAttacherJointXMLPaths)



Attachable.mrLoadInputAttacherJoint = function(self, superFunc, xmlFile, key, inputAttacherJoint, index)

    local result = superFunc(self, xmlFile, key, inputAttacherJoint, index)

    if result then
        local mrLowerRotationOffset = xmlFile:getValue(key .. "#mrLowerRotationOffset", nil)
        if mrLowerRotationOffset~=nil then
            --override base game value "lowerRotationOffset"
            inputAttacherJoint.lowerRotationOffset = mrLowerRotationOffset
        end
    end

    return result

end
Attachable.loadInputAttacherJoint = Utils.overwrittenFunction(Attachable.loadInputAttacherJoint, Attachable.mrLoadInputAttacherJoint)


---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
--MR : we don't want the implement wheels to leave "ruts" in working position => most of the time, the "workArea" processing function is just deleting that
--unwanted behavior = implement's wheels included in the work area are leaving heavy "ruts". At work, this is not perceptible because the processing area function is deleting it all the time
--but when we stop working, the implement sinks into the ground. And then, when we get back to work, the processing area function delete the "ruts" and the wheels bump a big time to get back to the "flat" surface
--for most implements, IRL, the wheels are not bearing the full implement weight in working position => the "ruts" would be small
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
Attachable.mrSetLowered = function(self, superFunc, lowered)

    superFunc(self, lowered)
    Attachable.mrManagedLoweredEvent(self, lowered)

end
Attachable.setLowered = Utils.overwrittenFunction(Attachable.setLowered, Attachable.mrSetLowered)

Attachable.mrOnFoldStateChanged = function(self, superFunc, direction, moveToMiddle)

    superFunc(self, direction, moveToMiddle)

    local spec = self.spec_foldable
    if spec.foldMiddleAnimTime ~= nil then
        Attachable.mrManagedLoweredEvent(self, not moveToMiddle and direction == spec.turnOnFoldDirection)
    end

end
Attachable.onFoldStateChanged = Utils.overwrittenFunction(Attachable.onFoldStateChanged, Attachable.mrOnFoldStateChanged)


Attachable.mrManagedLoweredEvent = function(self, lowered)

    if self.isServer and self.spec_wheels~=nil then
        for _, wheel in ipairs(self.spec_wheels.wheels) do
            if wheel.physics.supportsWheelSink and wheel.physics.mrNoGroundDisplacementWhenLowered then
                wheel.physics:setDisplacementAllowed(not lowered)
                --wheel.physics:setDisplacementCollisionEnabled(not lowered)
            end
        end
    end

end


---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
--MR : requiresExternalPower = no problem running when no motorized vehicle attached, but then, this is problematic if there is a motorized vehicle not running attached ?)
--fix that
--example : conveyAll CST1550
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--superFunc1 = Attachable.getIsPowered
--superFunc0 = genuine overriden function by Attachable.getIsPowered
Attachable.mrGetIsPowered = function(self, superFunc1, superFunc0)
    if not self.spec_attachable.requiresExternalPower then
        --MR: we don't want to check the attacher vehicle in such case
        return superFunc0(self)
    else
        return superFunc1(self, superFunc0)
    end
end
Attachable.getIsPowered = Utils.overwrittenFunction(Attachable.getIsPowered, Attachable.mrGetIsPowered)