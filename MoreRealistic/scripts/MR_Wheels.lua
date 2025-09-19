Wheels.mrOnLoad = function(self, savegame)
    self.spec_wheels.mrTotalWeightOnDrivenWheels = 0
    self.spec_wheels.mrNbDrivenWheels = 0
    self.spec_wheels.mrAvgDrivenWheelsSpeed = 0
    self.spec_wheels.mrAvgDrivenWheelsSlip = 0
end
Wheels.onLoad = Utils.appendedFunction(Wheels.onLoad, Wheels.mrOnLoad)

---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- 20250725 : wheelshape mass is not taken into for physics.
-- Example : tractor with frontloader and masses in the rear wheels are tipping the same as the version without masses in the wheels
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
Wheels.getComponentMass = function(self, superFunc, component)
    local mass = superFunc(self, component)

--     local spec = self.spec_wheels
--     for _, wheel in pairs(spec.wheels) do
--         if wheel.node == component.node then
--             mass = mass + wheel:getMass()
--         end
--     end

--     if component.mrWheelsMass~=nil then
--         mass = mass + component.mrWheelsMass
--     end

    return mass
end

---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- 20250725 : wheelshape mass is not taken into for physics.
-- Example : tractor with frontloader and masses in the rear wheels are tipping the same as the version without masses in the wheels
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
Wheels.mrLoadWheelsFromXML = function(self, superFunc, xmlFile, key, wheelConfigurationId)

    superFunc(self, xmlFile, key, wheelConfigurationId)

    --MR - modify components default mass and center of masses
    for _, component in ipairs(self.components) do
        if component.mrWheelsMass~=nil then
            local newX, newY, newZ
            local x0, y0, z0 = component.mrDefaultCOMx, component.mrDefaultCOMy, component.mrDefaultCOMz
            local baseMass = component.mrDefaultMass
            local addMass = component.mrWheelsMass.mass
            newX = (baseMass*x0+addMass*component.mrWheelsMass.COMx)/(baseMass+addMass)
            newY = (baseMass*y0+addMass*component.mrWheelsMass.COMy)/(baseMass+addMass)
            newZ = (baseMass*z0+addMass*component.mrWheelsMass.COMz)/(baseMass+addMass)

            component.mrDefaultCOMx = newX
            component.mrDefaultCOMy = newY
            component.mrDefaultCOMz = newZ
            component.mrDefaultMass = baseMass + addMass

            component.mrCenterOfMassIsDirty = true
        end
    end

end
Wheels.loadWheelsFromXML = Utils.overwrittenFunction(Wheels.loadWheelsFromXML, Wheels.mrLoadWheelsFromXML)



