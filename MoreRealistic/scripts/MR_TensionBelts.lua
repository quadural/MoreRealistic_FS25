--takes into account object center of mass when "mounting" it
TensionBelts.mrGetAdditionalComponentMass = function(self, superFunc0, superFunc, component)
    local additionalMass = superFunc(self, component)
    local spec = self.spec_tensionBelts

    component.mrAdditionalMassWithCOM["TensionBelts"] = nil

    if spec.hasTensionBelts and spec.jointComponent == component.node then

        local comTable = {}
        comTable.mass = 0

        for _, objectData in pairs(spec.objectsToJoint) do
            local object = objectData.object
            if object ~= nil then
                if object.getAllowComponentMassReduction ~= nil and object:getAllowComponentMassReduction() then
                    --additionalMass = additionalMass + math.max((object:getDefaultMass() - 0.1), 0)

                    --MR takes into acount center of mass
                    local objectMassToAdd = math.max((object:getDefaultMass() - 0.1), 0)
                    additionalMass = additionalMass + objectMassToAdd

                    if object.nodeId~=nil then
                        local cx, cy, cz = getCenterOfMass(object.nodeId)
                        local objX, objY, objZ = localToLocal(object.nodeId, component.node, cx, cy, cz)
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
            end

            if objectData.objectMass ~= nil then
                additionalMass = additionalMass + (objectData.objectMass - 0.01)
            end
        end

        if comTable.mass>0 then
            component.mrAdditionalMassWithCOM["TensionBelts"] = comTable
        end

    end

    return additionalMass
end
TensionBelts.getAdditionalComponentMass = Utils.overwrittenFunction(TensionBelts.getAdditionalComponentMass, TensionBelts.mrGetAdditionalComponentMass)