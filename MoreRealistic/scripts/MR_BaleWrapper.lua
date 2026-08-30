

BaleWrapper.mrRegisterOverwrittenFunctions = function(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getDoConsumePtoPower", BaleWrapper.getDoConsumePtoPower)
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

BaleWrapper.getDoConsumePtoPower = function(self, superFunc)

    local doConsume = superFunc(self)
    if not doConsume then
        doConsume = BaleWrapper.mrGetIsActive(self)
    end

    return doConsume

end