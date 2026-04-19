
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


--new value type for dashboard = fillUnit.mrFillMass to display the mass instead of the fillLevel (example : auger wagon / motherbin)
--mass in kilos
FillUnit.mrAddFillUnitFillLevel = function(self, superFunc, farmId, fillUnitIndex, fillLevelDelta, fillTypeIndex, toolType, fillPositionData)

    local appliedDelta = superFunc(self, farmId, fillUnitIndex, fillLevelDelta, fillTypeIndex, toolType, fillPositionData)

    if appliedDelta~=0 then
        local fillUnit = self.spec_fillUnit.fillUnits[fillUnitIndex]
        if fillUnit.hasDashboards and self.updateDashboardValueType ~= nil then
            self:updateDashboardValueType("fillUnit.mrFillMass")
        end
    end

    return appliedDelta

end
FillUnit.addFillUnitFillLevel = Utils.overwrittenFunction(FillUnit.addFillUnitFillLevel, FillUnit.mrAddFillUnitFillLevel)



FillUnit.mrLoadFillUnitFromXML = function(self, superFunc, xmlFile, key, entry, index)

    local result = superFunc(self, xmlFile, key, entry, index)

    if result and self.isClient and self.registerDashboardValueType ~= nil then

        local spec = self.spec_fillUnit

        local fillUnitLoadFunc = function(self, xmlFile, key, dashboard, isActive)
            local fillTypeName = xmlFile:getValue(key .. "#fillType")
            if fillTypeName ~= nil then
                local fillTypeIndex = g_fillTypeManager:getFillTypeIndexByName(fillTypeName)
                if fillTypeIndex ~= nil then
                    for _, fillUnit in ipairs(spec.fillUnits) do
                        if fillUnit.supportedFillTypes[fillTypeIndex] then
                            dashboard.fillUnit = fillUnit
                        end
                    end
                end
            end

            local fillUnitIndex = xmlFile:getValue(key .. "#fillUnitIndex")
            if fillUnitIndex ~= nil then
                dashboard.fillUnit = spec.fillUnits[fillUnitIndex]
            end

            if dashboard.fillUnit ~= nil then
                dashboard.fillUnit.hasDashboards = true
            else
                entry.hasDashboards = true
            end

            return true
        end

        local fillMass = DashboardValueType.new("fillUnit", "mrFillMass")
        fillMass:setXMLKey(key)
        fillMass:setValue(entry, function(_fillUnit, dashboard)
            local fillUnit = dashboard.fillUnit or _fillUnit
            local fillLevel = fillUnit.fillLevel
            if fillLevel>0 then
                local density = 1
                local fillTypeDesc = g_fillTypeManager:getFillTypeByIndex(fillUnit.fillType)
                if fillTypeDesc ~= nil and fillTypeDesc.massPerLiter ~= 0 then
                    density = 1000*fillTypeDesc.massPerLiter
                end
                return fillUnit.fillLevel * density
            else
                return 0
            end
        end)
        fillMass:setRange(0, function(_fillUnit, dashboard)
            return (dashboard.fillUnit or _fillUnit).capacity * 2
        end)
        fillMass:setInterpolationSpeed(function(_fillUnit, dashboard)
            return (dashboard.fillUnit or _fillUnit).capacity * 0.001
        end)
        fillMass:setAdditionalFunctions(fillUnitLoadFunc, nil)
        fillMass:setPollUpdate(false)
        self:registerDashboardValueType(fillMass)

    end

    return result

end
FillUnit.loadFillUnitFromXML = Utils.overwrittenFunction(FillUnit.loadFillUnitFromXML, FillUnit.mrLoadFillUnitFromXML)