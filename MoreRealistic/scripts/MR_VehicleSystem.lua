
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
    if mission:getIsServer() then
        addConsoleCommand("mrVehicleRecover", "try to recover the currently entered vehicle at the current position by lifting it", "mrConsoleCommandRecoverVehicle", self)
    end
    return self
end
VehicleSystem.new = Utils.overwrittenFunction(VehicleSystem.new, VehicleSystem.mrNew)


VehicleSystem.mrDelete = function(self, superFunc)
    superFunc(self)
    removeConsoleCommand("mrVehicleRecover")
end
VehicleSystem.delete = Utils.overwrittenFunction(VehicleSystem.delete, VehicleSystem.mrDelete)


VehicleSystem.mrConsoleCommandRecoverVehicle = function(self)
    local vehicleToRecover = g_localPlayer:getCurrentVehicle()
    if vehicleToRecover~=nil then
        vehicleToRecover.mrRecoveryModeActive = true
        if vehicleToRecover.getAttachedImplements~=nil then
            local attachedImplements = vehicleToRecover:getAttachedImplements()
            for _, implement in pairs(attachedImplements) do
                implement.object.mrRecoveryModeActive = true
            end
        end
    end
end
