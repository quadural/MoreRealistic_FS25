--20250726 - not useful anymore ? Giants has done the same with "VehicleConfigurationDataAdditionalMass"
--example : johndeere series6RLarge.xml
--TODO : remove and modify xml to use giants way

-- base game : front weight configuration is not convenient. You have to "compute" (or adjust figures and check ingame multiple times)
-- Biggest problem = if you have to modify/adjust the center of mass or the mass of the base vehicle component, then, you have to modify all the objectChange configuration again
-- MR solution = instead of telling the game the new component mass and center of mass, you only give to it the additionnal mass wanted and the aditionnal mass "COM" (center of mass)

ObjectChangeUtil.mrRegisterObjectChangeSingleXMLPaths = function(schema, superFunc, basePath)
    superFunc(schema, basePath)
    schema:register(XMLValueType.FLOAT, basePath .. ".objectChange(?)#mrAddMassActive", "additional mass to the component if object change is active")
    schema:register(XMLValueType.FLOAT, basePath .. ".objectChange(?)#mrAddMassInactive", "additional mass to the component if object change is not active")
    schema:register(XMLValueType.VECTOR_3, basePath .. ".objectChange(?)#mrAddMassCOMActive", "additional mass 'center of mass' if object change is active")
    schema:register(XMLValueType.VECTOR_3, basePath .. ".objectChange(?)#mrAddMassCOMInactive", "additional mass 'center of mass' if object change is not active")
end

ObjectChangeUtil.registerObjectChangeSingleXMLPaths = Utils.overwrittenFunction(ObjectChangeUtil.registerObjectChangeSingleXMLPaths, ObjectChangeUtil.mrRegisterObjectChangeSingleXMLPaths)

ObjectChangeUtil.mrLoadValuesFromXML = function(xmlFile, superFunc, key, node, object, parent, rootNode, i3dMappings)
    superFunc(xmlFile, key, node, object, parent, rootNode, i3dMappings)

    object.mrAddMass = xmlFile:getString(key.."#mrAddMassActive")
    if object.mrAddMass~=nil then
        object.mrAddMass = object.mrAddMass / 1000
    end

    ObjectChangeUtil.loadValueType(object.values, xmlFile, key, "mrAddMassCOM",
        function()
            return getCenterOfMass(node)
        end,
        function(x, y, z)


            if parent ~= nil and parent.components ~= nil then
                for _, component in ipairs(parent.components) do
                    if component.node == object.node then
                        --check if mrAddMass not added yet
                        if component.mrAddMassCOMKeys==nil or component.mrAddMassCOMKeys[key]==nil then
                            local addMass = object.mrAddMass
                            local baseMass = component.mrDefaultMass
                            local newX, newY, newZ
                            newX = (baseMass*component.mrDefaultCOMx+addMass*x)/(baseMass+addMass)
                            newY = (baseMass*component.mrDefaultCOMy+addMass*y)/(baseMass+addMass)
                            newZ = (baseMass*component.mrDefaultCOMz+addMass*z)/(baseMass+addMass)

                            component.mrDefaultCOMx = newX
                            component.mrDefaultCOMy = newY
                            component.mrDefaultCOMz = newZ

                            component.mrCenterOfMassIsDirty = true

                            if component.mrAddMassCOMKeys==nil then
                                component.mrAddMassCOMKeys = {}
                            end
                            component.mrAddMassCOMKeys[key] = true
                            --parent:setMassDirty()
                        end
                    end
                end
            end

        end,
        true, nil, true)

    ObjectChangeUtil.loadValueType(object.values, xmlFile, key, "mrAddMass",
        function()
            return getMass(node)
        end,
        function(value)
            if parent ~= nil and parent.components ~= nil then
                for _, component in ipairs(parent.components) do
                    if component.node == object.node then
                        if component.mrAddMassKeys==nil or component.mrAddMassKeys[key]==nil then
                            component.mrDefaultMass = component.mrDefaultMass + value / 1000
                            if component.mrAddMassKeys==nil then
                                component.mrAddMassKeys = {}
                            end
                            component.mrAddMassKeys[key] = true
                            --parent:setMassDirty()
                        end
                    end
                end
            end
        end, true)


    --MR : fix setMass not working anymore (20250727)
    -- reload valuetype "mass"
    ObjectChangeUtil.loadValueType(object.values, xmlFile, key, "mass",
        function()
            return getMass(node)
        end,
        function(value)
            if parent ~= nil and parent.components ~= nil then
                for _, component in ipairs(parent.components) do
                    if component.node == object.node then
                        --difference between genuine mass and objectchange wanted mass = replace the genuine mass by the objectchange mass
                        component.mrDefaultMass = component.mrDefaultMass - component.mrDefaultMassBAK + value / 1000
                        component.mrDefaultMassBAK = value / 1000
                    end
                end
            end
        end, true)

    --MR : fix setCenterOfMass not working anymore (20250727)
    -- reload valuetype "centerOfMass"
    ObjectChangeUtil.loadValueType(object.values, xmlFile, key, "centerOfMass",
        function()
            return getCenterOfMass(node)
        end,
        function(x, y, z)
            if parent ~= nil and parent.components ~= nil then
                for _, component in ipairs(parent.components) do
                    if component.node == object.node then
                        if object.centerOfMassMaskActive ~= nil then
                            if object.centerOfMassMask[1] == 0 then x = component.mrDefaultCOMx end
                            if object.centerOfMassMask[2] == 0 then y = component.mrDefaultCOMy end
                            if object.centerOfMassMask[3] == 0 then z = component.mrDefaultCOMz end
                        end
                        component.mrDefaultCOMx = x
                        component.mrDefaultCOMy = y
                        component.mrDefaultCOMz = z
                        component.mrCenterOfMassIsDirty = true
                    end
                end
            end
        end,
        true, nil, true)


end
ObjectChangeUtil.loadValuesFromXML = Utils.overwrittenFunction(ObjectChangeUtil.loadValuesFromXML, ObjectChangeUtil.mrLoadValuesFromXML)

