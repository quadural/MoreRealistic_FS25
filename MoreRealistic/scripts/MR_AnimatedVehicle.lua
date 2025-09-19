---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- fix "setCenterOfMass" not working for animation anymore (20250727)
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
AnimatedVehicle.mrRegisterAnimationValueType = function(self, superFunc, name, startName, endName, initialUpdate, classObject, load, get, set)

    if name=="centerOfMass" then
        set = function(value, x, y, z)
            value.component.mrAnimatedVehicleWantedCOM = {}
            value.component.mrAnimatedVehicleWantedCOM.x = x
            value.component.mrAnimatedVehicleWantedCOM.y = y
            value.component.mrAnimatedVehicleWantedCOM.z = z
            value.component.mrCenterOfMassIsDirty = true
            value.vehicle:setMassDirty() --force refresh of component mass/centerofmass
        end
    end

    if name=="componentMass" then
        set = function(value, mass)
            value.component.mrAnimatedVehicleWantedComponentMass = mass * 0.001
            value.vehicle:setMassDirty() --force refresh of component mass/centerofmass
        end
    end

    superFunc(self, name, startName, endName, initialUpdate, classObject, load, get, set)

end
AnimatedVehicle.registerAnimationValueType = Utils.overwrittenFunction(AnimatedVehicle.registerAnimationValueType, AnimatedVehicle.mrRegisterAnimationValueType)