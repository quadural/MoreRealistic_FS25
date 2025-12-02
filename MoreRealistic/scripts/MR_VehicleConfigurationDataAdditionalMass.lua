--MR 20251202 - v1.15 ready
VehicleConfigurationDataAdditionalMass.onLoad = function(vehicle, configItem, configId)
    if configItem.configKey ~= "" then
        for _, key in vehicle.xmlFile:iterator(configItem.configKey .. ".component") do
            local componentNode = vehicle.xmlFile:getValue(key .. "#node", nil, vehicle.components, vehicle.i3dMappings)
            local additionalMass = vehicle.xmlFile:getValue(key .. "#additionalMass", 0) * 0.001
            if componentNode ~= nil and additionalMass ~= 0 then
                local additionalMassNode = vehicle.xmlFile:getValue(key .. "#additionalMassNode", nil, vehicle.components, vehicle.i3dMappings)
                local additionalMassOffset = vehicle.xmlFile:getValue(key .. "#additionalMassOffset", nil, true)
                local useTotalMassReference = vehicle.xmlFile:getValue(key .. "#useTotalMassReference", true)

                local componentJointIndex = vehicle.xmlFile:getValue(key .. ".dependentComponentJoint#index", nil)
                if componentJointIndex ~= nil then
                    local transSpringFactor = vehicle.xmlFile:getValue(key .. ".dependentComponentJoint#transSpringFactor", 1)
                    local transDampingFactor = vehicle.xmlFile:getValue(key .. ".dependentComponentJoint#transDampingFactor", 1)
                    if vehicle.setDependentComponentJointBaseFactors ~= nil then
                        vehicle:setDependentComponentJointBaseFactors(componentJointIndex, transSpringFactor, transDampingFactor)
                    end
                end

                -- use the total vehicle mass as reference, as we have a 50/50 distribution with the front axle
                local totalMass = 0
                for _, component in ipairs(vehicle.components) do
                    totalMass = totalMass + component.defaultMass
                end

                for _, component in ipairs(vehicle.components) do
                    if component.node == componentNode then
                        if additionalMassNode ~= nil or additionalMassOffset ~= nil then
                            --local comX, comY, comZ = getCenterOfMass(componentNode)
                            local comX, comY, comZ = component.mrDefaultCOMx, component.mrDefaultCOMy, component.mrDefaultCOMz

                            local massX, massY, massZ
                            if additionalMassNode ~= nil then
                                massX, massY, massZ = localToLocal(additionalMassNode, componentNode, 0, 0, 0)
                            else
                                massX, massY, massZ = additionalMassOffset[1], additionalMassOffset[2], additionalMassOffset[3]
                            end

                            local alpha = additionalMass / (useTotalMassReference and totalMass or component.defaultMass)
                            local invAlpha = 1 - alpha
                            comX, comY, comZ = comX * invAlpha + massX * alpha, comY * invAlpha + massY * alpha, comZ * invAlpha + massZ * alpha
                            --setCenterOfMass(componentNode, comX, comY, comZ)
                            component.mrDefaultCOMx = comX
                            component.mrDefaultCOMy = comY
                            component.mrDefaultCOMz = comZ
                            component.mrCenterOfMassIsDirty = true
                        end

                        --component.defaultMass = component.defaultMass + additionalMass
                        component.mrDefaultMass = component.mrDefaultMass + additionalMass
                        break
                    end
                end
            end
        end
    end
end