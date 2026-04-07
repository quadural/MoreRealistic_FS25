--we want to forbid "mounting" a drivable vehicle onto a "cutter trailer"
--Example : combine harvester trying to attach/detach its header onto the trailer => if we leave the combine, there is a possibility that the combine is "mounted" onto the trailer !
--and we can't unmount it except by "reseting" the trailer to the shop (because the only way for an implement to be "unmounted" = when it is attached to another vehicle
--solution = prevent mounting an object without the "attachable" spec when this is a "combine header trailer"
DynamicMountAttacher.mrDynamicMountTriggerCallback = function(self, superFunc, triggerId, otherActorId, onEnter, onLeave, onStay, otherShapeId)

    if not onEnter and not onLeave then
        --no need to do anything = less "cpu usage" than vanilla game
        return
    end

    local preventMounting = false
    if onEnter then
        local object = g_currentMission:getNodeObject(otherActorId)
        if object~=nil then
            if object==self then
                preventMounting = true --no need to run the code if the header trailer has triggered the mounting trigger by itself
            elseif self.mrIsHeaderTrailer and not self.spec_dynamicMountAttacher.limitToKnownObjects and object.spec_attachable==nil then
                preventMounting = true -- we don't want to allow mounting not attachable vehicle (example : a combine harvester) to the trailer
            end
        end
    end

    if not preventMounting then
        superFunc(self, triggerId, otherActorId, onEnter, onLeave, onStay, otherShapeId)
    end

end
DynamicMountAttacher.dynamicMountTriggerCallback = Utils.overwrittenFunction(DynamicMountAttacher.dynamicMountTriggerCallback, DynamicMountAttacher.mrDynamicMountTriggerCallback)