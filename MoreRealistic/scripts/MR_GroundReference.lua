---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
--MR : bug to fix. getPowerMultiplier returns 0 if the last groundReferenceNode has a chargeValue of 0
-- Example = Kverneland Optima RS => when using a ridge marker = no more draftforce = full speed with any tractor
-- chargeValue should not be used anymore. they are replaced by "forcefactor" since FS21 ?
-- weird : grimme matrix 1800 has both forceFactor and chargeValue in its xml file (only forceFactor are taken into account)
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

GroundReference.getPowerMultiplier = function(self, superFunc)
    local powerMultiplier = superFunc(self)

    local spec = self.spec_groundReference
    if #(spec.groundReferenceNodes) > 0 then
        local factor = 0
        for _, refNode in ipairs(spec.groundReferenceNodes) do
            if refNode.isActive then
                if spec.hasForceFactors then
                    factor = factor + refNode.forceFactor
                else
                    factor = factor + refNode.chargeValue --FIX bug in base game engine
                end
            end
        end
        powerMultiplier = powerMultiplier * factor
    end
    return powerMultiplier
end