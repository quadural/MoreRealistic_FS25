

BaleWrapper.mrRegisterOverwrittenFunctions = function(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getDoConsumePtoPower", BaleWrapper.mrGetDoConsumePtoPower)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getAdditionalComponentMass", BaleWrapper.mrGetAdditionalComponentMass)
end
BaleWrapper.registerOverwrittenFunctions = Utils.appendedFunction(BaleWrapper.registerOverwrittenFunctions, BaleWrapper.mrRegisterOverwrittenFunctions)

BaleWrapper.mrLoadMrValues = function(self, xmlFile)

    self.mrIsMrWrapper = hasXMLProperty(xmlFile, "vehicle.mrWrapper")
    if self.mrIsMrWrapper then
        self.mrWrapperActivePower = getXMLFloat(xmlFile, "vehicle.mrWrapper#activePower") or 5
        self.mrWrapperBaleMassDependingPower = getXMLFloat(xmlFile, "vehicle.mrWrapper#baleMassDependingPower") or 3
    end

end



BaleWrapper.mrGetActiveConsumedPtoPower = function(self)

    local neededPower = 0

    if BaleWrapper.mrGetIsActive(self) then
        neededPower = self.mrWrapperActivePower
        local spec = self.spec_baleWrapper
        --takes into accoutn bale mass
        if spec.baleWrapperState==BaleWrapper.STATE_WRAPPER_WRAPPING_BALE then
            local bale = NetworkUtil.getObject(spec.currentWrapper.currentBale)
            if bale~=nil then
                neededPower = neededPower + self.mrWrapperBaleMassDependingPower * bale:getDefaultMass()
            end
        end

    end

    return neededPower

end

BaleWrapper.mrGetIsActive = function(self)
    local spec = self.spec_baleWrapper
    if spec.baleWrapperState == BaleWrapper.STATE_NONE or spec.baleWrapperState == BaleWrapper.STATE_WRAPPER_FINSIHED then
        return false
    else
        return true
    end
end

BaleWrapper.mrGetDoConsumePtoPower = function(self, superFunc)

    local doConsume = superFunc(self)
    if not doConsume then
        doConsume = BaleWrapper.mrGetIsActive(self)
    end

    return doConsume

end


---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- MR : add bale mass to wrapper
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
BaleWrapper.mrDoStateChange = function(self, id, nearestBaleServerId)
    if self.isServer then
        self:setMassDirty()
    end
end
BaleWrapper.doStateChange = Utils.appendedFunction(BaleWrapper.doStateChange, BaleWrapper.mrDoStateChange)

---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- MR : add bale mass to wrapper
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
BaleWrapper.mrGetAdditionalComponentMass = function(self, superFunc, component)

    --add bale mass to wrapper
    local additionalMass = superFunc(self, component)
    local spec = self.spec_baleWrapper

    component.mrAdditionalMassWithCOM["BaleWrapperGrabberBale"] = nil
    component.mrAdditionalMassWithCOM["BaleWrapperBale"] = nil

    if spec.baleGrabber.currentBale~=nil then
        if self:getParentComponent(spec.baleGrabber.grabNode)==component.node then
            --add the mass of the bale in the grabber to the component
            local bale = NetworkUtil.getObject(spec.baleGrabber.currentBale)
            if bale~=nil then
                local baleMass = bale:getDefaultMass()
                if baleMass>0 then
                    local comTable = {}
                    comTable.mass = baleMass
                    comTable.x, comTable.y, comTable.z = localToLocal(spec.baleGrabber.grabNode, component.node, 0, 0, 0)
                    component.mrAdditionalMassWithCOM["BaleWrapperGrabberBale"] = comTable
                    additionalMass = additionalMass + baleMass
                    component.mrForceMassAndComUpdate = true
                end
            end
        end
    end

    if spec.currentWrapper.currentBale~=nil then
        if self:getParentComponent(spec.currentWrapper.baleNode)==component.node then
            --add the mass of the bale in the wrapping unit to the component
            local bale = NetworkUtil.getObject(spec.currentWrapper.currentBale)
            if bale~=nil then
                local baleMass = bale:getDefaultMass()
                if baleMass>0 then
                    local comTable = {}
                    comTable.mass = baleMass
                    comTable.x, comTable.y, comTable.z = localToLocal(spec.currentWrapper.baleNode, component.node, 0, 0, 0)
                    component.mrAdditionalMassWithCOM["BaleWrapperBale"] = comTable
                    additionalMass = additionalMass + baleMass
                    component.mrForceMassAndComUpdate = true
                end
            end
        end
    end

    return additionalMass

end

---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- MR : add bale mass to wrapper
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
BaleWrapper.mrOnUpdate = function(self, superFunc, dt, isActiveForInput, isActiveForInputIgnoreSelection, isSelected)
    if self.isServer then
        local spec = self.spec_baleWrapper
        if spec.baleToMount~=nil and NetworkUtil.getObject(spec.baleToMount.serverId)~=nil then
            self:setMassDirty()
        elseif spec.baleWrapperState == BaleWrapper.STATE_MOVING_BALE_TO_WRAPPER or spec.baleWrapperState == BaleWrapper.STATE_WRAPPER_DROPPING_BALE then
            self:setMassDirty()
        end
    end
    superFunc(self, dt, isActiveForInput, isActiveForInputIgnoreSelection, isSelected)
end
BaleWrapper.onUpdate = Utils.overwrittenFunction(BaleWrapper.onUpdate, BaleWrapper.mrOnUpdate)

---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- MR : add bale mass to wrapper
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
BaleWrapper.mrAddToPhysics = function(self, superFunc, superFunc0)
    local result = superFunc(self, superFunc0)
    if self.isServer and result then
        self:setMassDirty()
    end
    return result
end
BaleWrapper.addToPhysics = Utils.overwrittenFunction(BaleWrapper.addToPhysics, BaleWrapper.mrAddToPhysics)