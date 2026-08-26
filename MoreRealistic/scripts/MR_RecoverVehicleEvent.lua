
MR_RecoverVehicleEvent = {}
local MR_RecoverVehicleEvent_mt = Class(MR_RecoverVehicleEvent, Event)

InitEventClass(MR_RecoverVehicleEvent, "MR_RecoverVehicleEvent")


---Create instance of Event class
-- @return table self instance of class event
function MR_RecoverVehicleEvent.emptyNew()
    local self = Event.new(MR_RecoverVehicleEvent_mt)
    return self
end


---Create new instance of event
-- @param table vehicleToRecover
-- @return table instance instance of event
function MR_RecoverVehicleEvent.new(vehicleToRecover)
    local self = MR_RecoverVehicleEvent.emptyNew()
    self.vehicleToRecover = vehicleToRecover
    return self
end


---Called on client or server side when the connection:sendEvent has been run (receiving side)
-- @param integer streamId streamId
-- @param Connection connection connection
function MR_RecoverVehicleEvent:readStream(streamId, connection)
    self.vehicleToRecover = NetworkUtil.readNodeObject(streamId)
    MR_RecoverVehicleEvent.mrRecoverVehicle(self.vehicleToRecover)
end


---Called on client or server side when the connection:sendEvent is run (sending side)
-- @param integer streamId streamId
-- @param Connection connection connection
function MR_RecoverVehicleEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.vehicleToRecover)
end


MR_RecoverVehicleEvent.mrRecoverVehicle = function(vehicleToRecover)
    if vehicleToRecover~=nil then
        MR_RecoverVehicleEvent.mrRecoverVehicleSwitchState(vehicleToRecover)
        if vehicleToRecover.getAttachedImplements~=nil then
            local attachedImplements = vehicleToRecover:getAttachedImplements()
            for _, implement in pairs(attachedImplements) do
                MR_RecoverVehicleEvent.mrRecoverVehicleSwitchState(implement.object)
            end
        end
    end
end

MR_RecoverVehicleEvent.mrRecoverVehicleSwitchState = function(vehicle)
    if vehicle.mrRecoveryModeActive then
        --already active => stop it
        vehicle.mrRecoveryModeActive = false
    else
        vehicle.mrRecoveryModeActive = true
    end
     vehicle.mrRecoveryModeTimer = 0
end

