
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
--we want to keep the exact same fileName in saveFile for vehicles => to be able to activate or desactivate "MR engine" when we want without losing vehicles/equipment
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
VehicleSystem.mrSaveVehicleToXML = function(self, superFunc, vehicle, xmlFile, index, i, usedModNames)

    local tempFileName = vehicle.configFileName
    local genuineFileName = RealisticUtils.getOverridedXmlFileName(tempFileName)

    if genuineFileName~=nil then
        vehicle.configFileName = genuineFileName
    end

    superFunc(self, vehicle, xmlFile, index, i, usedModNames)

    vehicle.configFileName = tempFileName

end
VehicleSystem.saveVehicleToXML = Utils.overwrittenFunction(VehicleSystem.saveVehicleToXML, VehicleSystem.mrSaveVehicleToXML)



VehicleSystem.mrNew = function(mission, superFunc, customMt)
    local self = superFunc(mission, customMt)
    addConsoleCommand("mrVehicleRecover", "try to recover the currently entered vehicle at the current position by lifting it", "mrConsoleCommandRecoverVehicle", self)
    if mission:getIsServer() then
        addConsoleCommand("mrVehicleMorePower", "double the engine output of the entered vehicle", "mrConsoleCommandVehicleMorePower", self)
    end
    return self
end
VehicleSystem.new = Utils.overwrittenFunction(VehicleSystem.new, VehicleSystem.mrNew)


VehicleSystem.mrDelete = function(self, superFunc)
    superFunc(self)
    removeConsoleCommand("mrVehicleRecover")
    removeConsoleCommand("mrConsoleCommandVehicleMorePower")
end
VehicleSystem.delete = Utils.overwrittenFunction(VehicleSystem.delete, VehicleSystem.mrDelete)


VehicleSystem.mrConsoleCommandRecoverVehicle = function(self, vehicleToRecover)
    if vehicleToRecover==nil then
        vehicleToRecover = g_localPlayer:getCurrentVehicle()
    end
    if vehicleToRecover~=nil then
        if g_server~=nil then
            MR_RecoverVehicleEvent.mrRecoverVehicle(vehicleToRecover)
        else
            g_client:getServerConnection():sendEvent(MR_RecoverVehicleEvent.new(vehicleToRecover))
        end
    end
end

VehicleSystem.mrConsoleCommandVehicleMorePower = function(self)
    local playerVehicle = g_localPlayer:getCurrentVehicle()
    if playerVehicle~=nil then
        if playerVehicle.mrMorePowerModeActive then
            playerVehicle.mrMorePowerModeActive = false
        else
            playerVehicle.mrMorePowerModeActive = true
        end
    end
end



