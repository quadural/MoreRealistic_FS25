
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



