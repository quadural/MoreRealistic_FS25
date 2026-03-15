---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
--MR : fix bug = if the player is helding a woodlog and putting it into a woodcrusher, and tries to rotate it while the woodcrusher is "deleting" the woodlog
--=> throw errors because the code is trying to rotate an entity that does not exist anymore
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
HandToolHands.mrGetIsHoldingItem = function(self, superFunc)
    if self.spec_hands.heldItemNode == nil then
        return false
    end

    if entityExists(self.spec_hands.heldItemNode) then
        return true
    end

    --held item has been destroyed (example : woodcrusher)
    self.spec_hands.heldItemNode = nil
    self.spec_hands.heldItemJointId = nil
    return false
end
HandToolHands.getIsHoldingItem = Utils.overwrittenFunction(HandToolHands.getIsHoldingItem, HandToolHands.mrGetIsHoldingItem)