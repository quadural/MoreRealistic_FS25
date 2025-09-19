
FillUnit.mrInitSpecialization = function(_, superFunc)
    superFunc()
    local schema = Vehicle.xmlSchema
    local fillUnitPath = FillUnit.FILL_UNIT_XML_KEY
    schema:register(XMLValueType.VECTOR_TRANS, fillUnitPath .. "#mrCenterOfMass", "Center of mass of the fillUnit")
end
FillUnit.initSpecialization = Utils.overwrittenFunction(FillUnit.initSpecialization, FillUnit.mrInitSpecialization)

FillUnit.mrLoadFillUnitFromXML = function(self, superFunc, xmlFile, key, entry, index)
    local result = superFunc(self, xmlFile, key, entry, index)
    if result then
        local comX, comY, comZ = xmlFile:getValue(key .. "#mrCenterOfMass")
        if comX~=nil then
            entry.mrCenterOfMassX = comX
            entry.mrCenterOfMassY = comY
            entry.mrCenterOfMassZ = comZ
        end
    end
    return result
end
FillUnit.loadFillUnitFromXML = Utils.overwrittenFunction(FillUnit.loadFillUnitFromXML, FillUnit.mrLoadFillUnitFromXML)

---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- MR = return CenterOfMass of the fillUnit => where the mass is added to the vehicle, so that Vehicle.UpdateMass could move the cneterOfMass of the component too
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
FillUnit.mrGetAdditionalComponentMass = function(self, superFunc0, superFunc, component)
    local additionalMass = superFunc(self, component)
    local spec = self.spec_fillUnit

    component.mrAdditionalMassWithCOMx = nil
    component.mrAdditionalMassWithCOMy = nil
    component.mrAdditionalMassWithCOMz = nil
    component.mrAdditionalMassWithCOM = nil

    for _, fillUnit in ipairs(spec.fillUnits) do
        if fillUnit.updateMass and fillUnit.fillMassNode == component.node and fillUnit.fillType ~= nil and fillUnit.fillType ~= FillType.UNKNOWN then
            local desc = g_fillTypeManager:getFillTypeByIndex(fillUnit.fillType)
            local mass = fillUnit.fillLevel * desc.massPerLiter

            if fillUnit.mrCenterOfMassX~=nil then
                if component.mrAdditionalMassWithCOM==nil or component.mrAdditionalMassWithCOM==0 then
                    component.mrAdditionalMassWithCOMx = fillUnit.mrCenterOfMassX
                    component.mrAdditionalMassWithCOMy = fillUnit.mrCenterOfMassY
                    component.mrAdditionalMassWithCOMz = fillUnit.mrCenterOfMassZ
                    component.mrAdditionalMassWithCOM = mass
                elseif mass>0 then
                    component.mrAdditionalMassWithCOMx = (component.mrAdditionalMassWithCOM*component.mrAdditionalMassWithCOMx+mass*fillUnit.mrCenterOfMassX)/(component.mrAdditionalMassWithCOM+mass)
                    component.mrAdditionalMassWithCOMy = (component.mrAdditionalMassWithCOM*component.mrAdditionalMassWithCOMy+mass*fillUnit.mrCenterOfMassY)/(component.mrAdditionalMassWithCOM+mass)
                    component.mrAdditionalMassWithCOMz = (component.mrAdditionalMassWithCOM*component.mrAdditionalMassWithCOMz+mass*fillUnit.mrCenterOfMassZ)/(component.mrAdditionalMassWithCOM+mass)
                    component.mrAdditionalMassWithCOM = component.mrAdditionalMassWithCOM + mass
                end
            end

            additionalMass = additionalMass + mass
        end
    end

    return additionalMass
end
FillUnit.getAdditionalComponentMass = Utils.overwrittenFunction(FillUnit.getAdditionalComponentMass, FillUnit.mrGetAdditionalComponentMass)