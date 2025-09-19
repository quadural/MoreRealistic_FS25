Wheel.mrRegisterXMLPaths = function(schema, superFunc, key)
    superFunc(schema, key)
    --allow us to get the rim dimension in the WheelPhysics.mrLoadAdditionalWheel function
    schema:register(XMLValueType.VECTOR_2, key .. ".outerRim#widthAndDiam", "Rim dimension")
    local additionalWheelKey = key .. ".additionalWheel(?)"
    schema:register(XMLValueType.VECTOR_2, additionalWheelKey .. ".outerRim#widthAndDiam", "Rim dimension") -- fix xml load error in some mods (example : Belarus 920)
end
Wheel.registerXMLPaths = Utils.overwrittenFunction(Wheel.registerXMLPaths, Wheel.mrRegisterXMLPaths)


---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- 20250725 : wheelshape mass is not taken into for physics.
-- Example : tractor with frontloader and masses in the rear wheels are tipping the same as the version without masses in the wheels
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
Wheel.mrLoadFromXML = function(self, superFunc)

    local result = superFunc(self)
    if result then
        -- update component wheels mass
        for _, component in ipairs(self.vehicle.components) do
            if self.node == component.node then
                if component.mrWheelsMass==nil then
                    component.mrWheelsMass = {}
                    component.mrWheelsMass.mass = self:getMass()
                    component.mrWheelsMass.COMx, component.mrWheelsMass.COMy, component.mrWheelsMass.COMz = localToLocal(self.repr, component.node, 0, 0, 0)
                else
                    local addMass = self:getMass()
                    local baseMass = component.mrWheelsMass.mass

                    local wheelCOMx, wheelCOMy, wheelCOMz = localToLocal(self.repr, component.node, 0, 0, 0)
                    local newX, newY, newZ
                    newX = (baseMass*component.mrWheelsMass.COMx+addMass*wheelCOMx)/(baseMass+addMass)
                    newY = (baseMass*component.mrWheelsMass.COMy+addMass*wheelCOMy)/(baseMass+addMass)
                    newZ = (baseMass*component.mrWheelsMass.COMz+addMass*wheelCOMz)/(baseMass+addMass)
                    component.mrWheelsMass.COMx = newX
                    component.mrWheelsMass.COMy = newY
                    component.mrWheelsMass.COMz = newZ
                    component.mrWheelsMass.mass = baseMass + addMass
                end
            end
        end
    end
    return result

end
Wheel.loadFromXML = Utils.overwrittenFunction(Wheel.loadFromXML, Wheel.mrLoadFromXML)