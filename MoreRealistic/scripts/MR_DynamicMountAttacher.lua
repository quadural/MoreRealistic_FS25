--we want to forbid "mounting" a drivable vehicle onto a "cutter trailer"
--Example : combine harvester trying to attach/detach its header onto the trailer => if we leave the combine, there is a possibility that the combine is "mounted" onto the trailer !
--and we can't unmount it except by "reseting" the trailer to the shop (because the only way for an implement to be "unmounted" = when it is attached to another vehicle
--solution = prevent mounting an object without the "attachable" spec when this is a "combine header trailer"
DynamicMountAttacher.mrDynamicMountTriggerCallback = function(self, superFunc, triggerId, otherActorId, onEnter, onLeave, onStay, otherShapeId)

    if not onEnter and not onLeave then
        --no need to do anything = less "cpu usage" than vanilla game
        return
    end

    local preventMounting = false
    if onEnter then
        local object = g_currentMission:getNodeObject(otherActorId)
        if object~=nil then
            if object==self then
                preventMounting = true --no need to run the code if the header trailer has triggered the mounting trigger by itself
            elseif self.mrIsHeaderTrailer and not self.spec_dynamicMountAttacher.limitToKnownObjects and object.spec_attachable==nil then
                preventMounting = true -- we don't want to allow mounting not attachable vehicle (example : a combine harvester) to the trailer
            end
        end
    end

    if not preventMounting then
        superFunc(self, triggerId, otherActorId, onEnter, onLeave, onStay, otherShapeId)
    end

end
DynamicMountAttacher.dynamicMountTriggerCallback = Utils.overwrittenFunction(DynamicMountAttacher.dynamicMountTriggerCallback, DynamicMountAttacher.mrDynamicMountTriggerCallback)



--replace xmlFilename by mr xmlFilename if present
DynamicMountAttacher.mrLoadDynamicLockPositionFromXML = function(self, superFunc, xmlFile, key, lockPosition)

    if superFunc(self, xmlFile, key, lockPosition) then
        local searchString = lockPosition.xmlFilename
        if string.startsWith(searchString, "vehicles/") then
            searchString = "$data/" .. searchString
        end
        local item = RealisticUtils.getOverridingXmlFileNameData(searchString)
        if item~=nil then
            lockPosition.xmlFilename = item.newFileName
        end

        return true
    end

    return false


end
DynamicMountAttacher.loadDynamicLockPositionFromXML = Utils.overwrittenFunction(DynamicMountAttacher.loadDynamicLockPositionFromXML, DynamicMountAttacher.mrLoadDynamicLockPositionFromXML)



--takes into account object center of mass when "mounting" it
-- TODO = NOT TESTED
DynamicMountAttacher.mrGetAdditionalComponentMass = function(self, superFunc0, superFunc, component)
    local additionalMass = superFunc(self, component)
    local spec = self.spec_dynamicMountAttacher

    if spec.dynamicMountAttacherTrigger ~= nil and spec.transferMass then
        if spec.dynamicMountAttacherTrigger.component == component.node then

            component.mrAdditionalMassWithCOM["DynamicMountAttacher"] = nil

            local comTable = {}
            comTable.mass = 0

            for object, _ in pairs(spec.dynamicMountedObjects) do
                if object.getAllowComponentMassReduction ~= nil and object:getAllowComponentMassReduction() then
                    local objectMassToAdd = object:getDefaultMass() - 0.1
                    additionalMass = additionalMass + objectMassToAdd
                    local objX, objY, objZ = localToLocal(object, component.node, getCenterOfMass(object))
                    if comTable.mass==0 then
                        comTable.x, comTable.y, comTable.z = objX, objY, objZ
                        comTable.mass = objectMassToAdd
                    else
                        local newMass = comTable.mass+objectMassToAdd
                        comTable.x = (comTable.mass*comTable.x+objectMassToAdd*objX)/newMass
                        comTable.y = (comTable.mass*comTable.y+objectMassToAdd*objY)/newMass
                        comTable.z = (comTable.mass*comTable.z+objectMassToAdd*objZ)/newMass
                        comTable.mass = newMass
                    end
                end
            end

            if comTable.mass>0 then
                component.mrAdditionalMassWithCOM["DynamicMountAttacher"] = comTable
            end

        end
    end

    return additionalMass
end
DynamicMountAttacher.getAdditionalComponentMass = Utils.overwrittenFunction(DynamicMountAttacher.getAdditionalComponentMass, DynamicMountAttacher.mrGetAdditionalComponentMass)