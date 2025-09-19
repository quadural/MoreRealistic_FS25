RealisticUtils = {}

RealisticUtils.defaultVehiclesModifiedData = {}
RealisticUtils.defaultVehicleMrFilenameToGenuineFilename = {}


RealisticUtils.nameToGroundType = {
    ["GROUND_ROAD"] = WheelsUtil.GROUND_ROAD,
    ["GROUND_HARD_TERRAIN"] = WheelsUtil.GROUND_HARD_TERRAIN,
    ["GROUND_SOFT_TERRAIN"] = WheelsUtil.GROUND_SOFT_TERRAIN,
    ["GROUND_FIELD"] = WheelsUtil.GROUND_FIELD}

RealisticUtils.groundTypeToName = {
    [WheelsUtil.GROUND_ROAD] = "road",
    [WheelsUtil.GROUND_HARD_TERRAIN] = "hard",
    [WheelsUtil.GROUND_SOFT_TERRAIN] = "soft",
    [WheelsUtil.GROUND_FIELD] = "field"}

RealisticUtils.terrainAttributeToName = {}

RealisticUtils.defaultVehiclesKeepEnvironmentTable = {}

--***************************************************************************************************
RealisticUtils.loadDefaultVehiclesModifiedData = function(folderPath, databaseFileName)

    --reset vehicles data
    RealisticUtils.defaultVehiclesModifiedData = {}
    RealisticUtils.defaultVehicleMrFilenameToGenuineFilename = {}

    --loading database file
    local xmlFile = loadXMLFile("realisticDefaultVehicleDatabase.xml", folderPath .. "/" .. databaseFileName)

    local i = 0
    while true do
        local vehicleXmlPath = string.format("vehicles.vehicle(%d)", i)
        if not hasXMLProperty(xmlFile, vehicleXmlPath) then break end
        local vehicleFilePath = getXMLString(xmlFile, vehicleXmlPath)
        local fileNameToOverride = getXMLString(xmlFile, vehicleXmlPath .. "#fileNameToOverride")
        local keepEnvironment = getXMLString(xmlFile, vehicleXmlPath .. "#keepGenuineEnvironment")
        --local overridedVehicleTypeName = getXMLString(xmlFile, vehicleXmlPath .. "#newVehicleType")

        --replace $pdlcdir by the full path
--         if string.sub(fileNameToOverride,1,8):lower()=="$pdlcdir" then
--             --required for steam users
--             fileNameToOverride = Utils.convertFromNetworkFilename(fileNameToOverride)
--         elseif string.sub(fileNameToOverride,1,7):lower()=="$moddir" then
--             fileNameToOverride = Utils.convertFromNetworkFilename(fileNameToOverride)
--         end

        local newFileName = folderPath .. "/" .. vehicleFilePath

        RealisticUtils.defaultVehiclesModifiedData[fileNameToOverride] = {}
        RealisticUtils.defaultVehiclesModifiedData[fileNameToOverride].newFileName = newFileName
        if keepEnvironment~=nil then
            RealisticUtils.defaultVehiclesModifiedData[fileNameToOverride].keepEnvironment = keepEnvironment
        end
--         if overridedVehicleTypeName~=nil then
--             RealisticUtils.defaultVehiclesModifiedData[fileNameToOverride].newVehicleTypeName = overridedVehicleTypeName
--         end

        RealisticUtils.defaultVehicleMrFilenameToGenuineFilename[string.lower(newFileName)] = fileNameToOverride

        --print("RealisticUtils.loadDefaultVehiclesModifiedData - fileNameToOverride="..tostring(fileNameToOverride) .. " - vehicleFilePath="..tostring(folderPath .. "/" .. vehicleFilePath))

        --load the modified store data
        --2017/11/24 - replace by "RealisticUtils.reloadStoreDataWithMR" to take into account mrDatabank data in the store too
        --RealisticUtils.loadModifiedStoreData(fileNameToOverride, folderPath .. "/" .. vehicleFilePath);

        i = i + 1
    end

    delete(xmlFile)

end



--***************************************************************************************************
--** return mr new filename for vehicle xml
RealisticUtils.getOverridingXmlFileNameData = function(itemName)

    local item = RealisticUtils.defaultVehiclesModifiedData[itemName]
    if item==nil then
        item = RealisticUtils.defaultVehiclesModifiedData[string.gsub(itemName, "%$", "")]
    end

    return item

end

--***************************************************************************************************
--** return vanilla game vehicle xml filename
RealisticUtils.getOverridedXmlFileName = function(itemName)
    local genuineFileName = RealisticUtils.defaultVehicleMrFilenameToGenuineFilename[string.lower(itemName)]
    return genuineFileName
end



--***************************************************************************************************
RealisticUtils.loadRealTyresFrictionAndRr = function(filePath)

    --DebugUtil.printTableRecursively(WheelsUtil.GROUND_HARD_TERRAIN, 1, 1, 100)
    local xmlFile = loadXMLFile("realFrictionAndRrXML", filePath)

    local i = 0
    while true do
        local tyreTypeKey = string.format("tyreTypes.tyreType(%d)", i)
        if not hasXMLProperty(xmlFile, tyreTypeKey) then break end

        local tyreTypeName = getXMLString(xmlFile, tyreTypeKey .. "#name")
        local tireTypeIndex = WheelsUtil.getTireType(tyreTypeName)

        if tireTypeIndex==nil then
            RealisticUtils.printWarning("RealisticUtils.loadRealTyresFrictionAndRr", "unknown tireType, tyreTypeName="..tostring(tyreTypeName) .. ", i="..tostring(i), true)
            break
        end

        local tireType = WheelsUtil.tireTypes[tireTypeIndex]

        --new table to store rolling resistance values
        tireType.mrRollingResistanceCoeffs = {}
        tireType.mrRollingResistanceCoeffsWet = {}
        tireType.mrRollingResistanceCoeffsSnow = {}

        --for each surface type, set the new values
        local j = 0
        while true do
            local surfaceTypeKey = tyreTypeKey .. string.format(".surfaceType(%d)", j)
            if not hasXMLProperty(xmlFile, surfaceTypeKey) then break end

            local surfaceTypeName = getXMLString(xmlFile, surfaceTypeKey .. "#name")
            local groundType = RealisticUtils.nameToGroundType[surfaceTypeName]

            if groundType==nil then
                RealisticUtils.printWarning("RealisticUtils.loadRealTyresFrictionAndRr", "unknown groundType, surfaceTypeName="..tostring(surfaceTypeName) .. ", i="..tostring(i) .. ", j="..tostring(j), true)
                break
            end

            local _getValueFromXML = function(xmlPath, myTable, groundType)
                local value = getXMLFloat(xmlFile, xmlPath)
                if value==nil then
                    RealisticUtils.printWarning("RealisticUtils.loadRealTyresFrictionAndRr", "nil value for groundType, xmlPath="..tostring(xmlPath), true)
                    return false
                end
                myTable[groundType] = value
                return true
            end

            if not _getValueFromXML(surfaceTypeKey .. "#dryFriction", tireType.frictionCoeffs, groundType) then break end
            if not _getValueFromXML(surfaceTypeKey .. "#wetFriction", tireType.frictionCoeffsWet, groundType) then break end
            if not _getValueFromXML(surfaceTypeKey .. "#snowFriction", tireType.frictionCoeffsSnow, groundType) then break end
            if not _getValueFromXML(surfaceTypeKey .. "#dryRollingResistance", tireType.mrRollingResistanceCoeffs, groundType) then break end
            if not _getValueFromXML(surfaceTypeKey .. "#wetRollingResistance", tireType.mrRollingResistanceCoeffsWet, groundType) then break end
            if not _getValueFromXML(surfaceTypeKey .. "#snowRollingResistance", tireType.mrRollingResistanceCoeffsSnow, groundType) then break end

            j = j + 1;
        end

        i = i + 1;
    end

    delete(xmlFile);

end

--***************************************************************************************************
RealisticUtils.loadTerrainIdToName = function()

    RealisticUtils.terrainAttributeToName = {}

    local surfaceSounds = g_currentMission.surfaceSounds
    for j=1, #surfaceSounds do
        local surfaceSound = surfaceSounds[j]
        if surfaceSound.type:lower() == "wheel" then
            RealisticUtils.terrainAttributeToName[surfaceSound.materialId] = surfaceSound.name
        end
    end
end

--***************************************************************************************************
RealisticUtils.printWarning = function(stackTrace, message, isError)

    local gameTime = g_currentMission~=nil and g_currentMission.time or 0
    local msg = "*** " .. tostring(gameTime) .. " MoreRealistic - "

    msg = isError and msg .. "ERROR - " or msg .. "WARNING - "
    msg = msg .. stackTrace .. " - " .. message

    print(msg)

end

--fx must be between 0 and 1
RealisticUtils.linearFx = function(fx, minVal, maxVal)
    return minVal + fx * (maxVal-minVal)
end

--return 1 if param=minParam, return minVal if param=maxParam
--param between minParam and maxParam
RealisticUtils.linearFx2 = function(param, minParam, maxParam, minVal)
    return 1 - (1-minVal)*(param - minParam)/(maxParam-minParam)
end

--return minVal if param=minParam, return maxVal if param=maxParam
--param between minParam and maxParam
--maxParam>minParam
RealisticUtils.linearFx3 = function(param, minParam, maxParam, minVal, maxVal)
    return minVal + (maxVal-minVal)*(param-minParam)/(maxParam-minParam)
end