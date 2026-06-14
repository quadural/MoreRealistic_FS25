
--mass function of fillType and fillLevel
Bale.mrSetFillLevel = function(self, superFunc, fillLevel)

    superFunc(self, fillLevel)

    if self.fillType~=nil then
        local desc = g_fillTypeManager:getFillTypeByIndex(self.fillType)
        if desc~=nil then
            local newMass = self.fillLevel * desc.massPerLiter
            setMass(self.nodeId, newMass)
            self.defaultMass = newMass
        end
    end

end
Bale.setFillLevel = Utils.overwrittenFunction(Bale.setFillLevel, Bale.mrSetFillLevel)