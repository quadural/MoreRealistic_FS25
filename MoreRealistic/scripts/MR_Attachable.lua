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