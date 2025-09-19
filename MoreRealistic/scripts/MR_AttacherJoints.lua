---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- add new param in xml
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
AttacherJoints.mrRegisterAttacherJointXMLPaths = function(schema, superFunc, baseName)

    schema:register(XMLValueType.BOOL, baseName .. ".attacherJoint(?)#mrAlwaysLowered", "joint is always fully lowered", false)
    superFunc(schema, baseName)

end
AttacherJoints.registerAttacherJointXMLPaths = Utils.overwrittenFunction(AttacherJoints.registerAttacherJointXMLPaths, AttacherJoints.mrRegisterAttacherJointXMLPaths)

---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- read new param in xml
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
AttacherJoints.mrLoadAttacherJointFromXML = function(self, superFunc, attacherJoint, xmlFile, baseName, index)

    local result = superFunc(self, attacherJoint, xmlFile, baseName, index)
    if result then
        attacherJoint.mrAlwaysLowered = xmlFile:getValue(baseName.."#mrAlwaysLowered", false)
    end
    return result
end
AttacherJoints.loadAttacherJointFromXML = Utils.overwrittenFunction(AttacherJoints.loadAttacherJointFromXML, AttacherJoints.mrLoadAttacherJointFromXML)

---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- manage "mrAlwaysLowered" param (example : agrisem combiplow = back attacher is always lowered, it can't be raised). Otherwise ,the game set it to "not lowered" (raised) and take into account the "upperRotationOffset" of the attached implement instead of taking into account the "lowerRotationOffset"
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
AttacherJoints.mrUpdateAttacherJointRotation = function(self, superFunc, jointDesc, object)

    local rotDiff
    local objectAttacherJoint = object.spec_attachable.attacherJoint

    if jointDesc.mrAlwaysLowered then
        jointDesc.moveAlpha = 1
        jointDesc.lowerAlpha = 1
        jointDesc.upperAlpha = 0
        jointDesc.isDefaultLowered = true
    end

    -- rotate attacher such that
    --MR : this is so wrong... we want to get the same "lowerRotationOffset" whatever the "lowerAlpha" corresponding to the current lower distanceToGround of the implement
    --local targetRot = MathUtil.lerp(objectAttacherJoint.upperRotationOffset, objectAttacherJoint.lowerRotationOffset, jointDesc.moveAlpha)

    --MR : if moveAlpha==lowerAlpha, then alpha=1, if moveAlpha==upperAlpha, then alpha=0 => only for the implement
    local targetRot
    if object.mrIsMrVehicle then
        if jointDesc.mrAlwaysLowered then
            targetRot = objectAttacherJoint.lowerRotationOffset
        else
            local alpha = MathUtil.inverseLerp(jointDesc.upperAlpha, jointDesc.lowerAlpha, jointDesc.moveAlpha)
            targetRot = MathUtil.lerp(objectAttacherJoint.upperRotationOffset, objectAttacherJoint.lowerRotationOffset, alpha)
        end
    else
        --we don't want to "mess up" not converted vehicles
        targetRot = MathUtil.lerp(objectAttacherJoint.upperRotationOffset, objectAttacherJoint.lowerRotationOffset, jointDesc.moveAlpha)
    end
    local curRot = MathUtil.lerp(jointDesc.upperRotationOffset, jointDesc.lowerRotationOffset, jointDesc.moveAlpha)
    rotDiff = targetRot - curRot


    setRotation(jointDesc.jointTransform, unpack(jointDesc.jointOrigRot))
    rotateAboutLocalAxis(jointDesc.jointTransform, rotDiff, 0, 0, 1)

end
AttacherJoints.updateAttacherJointRotation = Utils.overwrittenFunction(AttacherJoints.updateAttacherJointRotation, AttacherJoints.mrUpdateAttacherJointRotation)

---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- when "hard attached" (example : loaders for tractors), the implement mass is already included in the vehicle component mass
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
AttacherJoints.getTotalMass = function(self, superFunc, onlyGivenVehicle)
    local spec = self.spec_attacherJoints
    local mass = superFunc(self)

    if onlyGivenVehicle == nil or not onlyGivenVehicle then
        for _, implement in pairs(spec.attachedImplements) do
            local object = implement.object
            if object ~= nil then
                mass = mass + object:getTotalMass(onlyGivenVehicle)
                if object.spec_attachable.isHardAttached then
                    mass = mass - object:getTotalMass(true)
                end
            end
        end
    end

    return mass
end