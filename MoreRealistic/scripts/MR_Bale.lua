
--mass function of fillType and fillLevel
Bale.mrSetFillLevel = function(self, superFunc, fillLevel)
    superFunc(self, fillLevel)
    Bale.mrComputeMass(self)
end
Bale.setFillLevel = Utils.overwrittenFunction(Bale.setFillLevel, Bale.mrSetFillLevel)



--mass function of fillType and fillLevel
Bale.mrSetFillType = function(self, superFunc, fillTypeIndex, fillBale)

    superFunc(self, fillTypeIndex, fillBale)

    local fillTypeInfo = self:getFillTypeInfo(self.fillType)
    if fillTypeInfo ~= nil and not fillBale then
        Bale.mrComputeMass(self)
    end

end
Bale.setFillType = Utils.overwrittenFunction(Bale.setFillType, Bale.mrSetFillType)

--mass function of fillType and fillLevel
Bale.mrComputeMass = function(self)

    if self.fillType~=nil then
        local desc = g_fillTypeManager:getFillTypeByIndex(self.fillType)
        if desc~=nil then
            local newMass = self.fillLevel * desc.massPerLiter

            --apply factor for grass (see RealisticMain.lua for explanation)
            if desc.name=="GRASS_WINDROW" or desc.name=="GRASS" then
                newMass = newMass * RealisticMain.BALER_GRASS_MASS_FX
            end

            setMass(self.nodeId, newMass)
            self.defaultMass = newMass
        end
    end

end



