RealisticMain.FIXPFgetCropSensorLinkageData = function(self, configFileName)
    if configFileName ~= nil then
        for i=1, #self.linkageData do
            local vehicleData = self.linkageData[i]
            --check if this is an overrided MR vehicle
            local fileNameToCheck = vehicleData.filename
            local item = RealisticUtils.getOverridingXmlFileNameData(vehicleData.filename)
            if item~=nil then
                fileNameToCheck = item.newFileName
            end
            if string.endsWith(configFileName, fileNameToCheck) then
                return vehicleData
            end
        end
    end

    return nil
end

RealisticMain.FIXPFgetManureSensorLinkageData = function(self, configFileName)
    if configFileName ~= nil then
        for i=1, #self.linkageData do
            local vehicleData = self.linkageData[i]
            --check if this is an overrided MR vehicle
            local fileNameToCheck = vehicleData.filename
            local item = RealisticUtils.getOverridingXmlFileNameData(vehicleData.filename)
            if item~=nil then
                fileNameToCheck = item.newFileName
            end
            if string.endsWith(configFileName, fileNameToCheck) then
                return vehicleData
            end
        end
    end

    return nil
end

RealisticMain.FIXPFgetSprayerNodeData = function(self, configFileName, configurations)
    if configFileName ~= nil then
        for i=1, #self.linkageData do
            local vehicleData = self.linkageData[i]
            --check if this is an overrided MR vehicle
            local fileNameToCheck = vehicleData.filename
            local item = RealisticUtils.getOverridingXmlFileNameData(vehicleData.filename)
            if item~=nil then
                fileNameToCheck = item.newFileName
            end
            if string.endsWith(configFileName, fileNameToCheck) then
                if configurations ~= nil then
                    local configId = configurations[vehicleData.configurationName]
                    if configId ~= nil then
                        return vehicleData.configurations[configId], vehicleData
                    else
                        return vehicleData.configurations[1], vehicleData
                    end
                else
                    return vehicleData.configurations[1], vehicleData
                end
            end
        end
    end

    return nil
end



--override PrecisionFarming "getSprayerNodeData" data to be able to recognize modified default vehicles
--g_precisionFarming
if FS25_precisionFarming~=nil then
    FS25_precisionFarming.CropSensorLinkageData.getCropSensorLinkageData = RealisticMain.FIXPFgetCropSensorLinkageData
    FS25_precisionFarming.ManureSensorLinkageData.getManureSensorLinkageData = RealisticMain.FIXPFgetManureSensorLinkageData
    FS25_precisionFarming.SprayerNodeData.getSprayerNodeData = RealisticMain.FIXPFgetSprayerNodeData
end