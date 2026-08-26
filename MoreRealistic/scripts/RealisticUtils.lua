RealisticUtils = {}

RealisticUtils.defaultVehiclesModifiedData = {}
RealisticUtils.defaultVehicleMrFilenameToGenuineFilename = {}

RealisticUtils.databankVehiclesModifiedData = {}
RealisticUtils.databankVehicleMrFilenameToGenuineFilename = {}


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

RealisticUtils.vehiclesKeepEnvironmentTable = {}

--***************************************************************************************************
RealisticUtils.loadDefaultVehiclesModifiedData = function(folderPath, databaseFileName)

    --reset vehicles data
    RealisticUtils.defaultVehiclesModifiedData = {}
    RealisticUtils.defaultVehicleMrFilenameToGenuineFilename = {}
    -- reset databank items too
    RealisticUtils.databankVehiclesModifiedData = {}
    RealisticUtils.databankVehicleMrFilenameToGenuineFilename = {}

    --loading database file
    local xmlFile = loadXMLFile("realisticDefaultVehicleDatabase.xml", folderPath .. "/" .. databaseFileName)

    local i = 0
    while true do
        local vehicleXmlPath = string.format("vehicles.vehicle(%d)", i)
        if not hasXMLProperty(xmlFile, vehicleXmlPath) then break end
        local vehicleFilePath = getXMLString(xmlFile, vehicleXmlPath)
        local fileNameToOverride = getXMLString(xmlFile, vehicleXmlPath .. "#fileNameToOverride")
        local keepEnvironment = getXMLString(xmlFile, vehicleXmlPath .. "#keepGenuineEnvironment")
        local newFileName = folderPath .. "/" .. vehicleFilePath

        RealisticUtils.defaultVehiclesModifiedData[fileNameToOverride] = {}
        RealisticUtils.defaultVehiclesModifiedData[fileNameToOverride].newFileName = newFileName
        if keepEnvironment~=nil then
            RealisticUtils.defaultVehiclesModifiedData[fileNameToOverride].keepEnvironment = keepEnvironment
        end

        RealisticUtils.defaultVehicleMrFilenameToGenuineFilename[string.lower(newFileName)] = fileNameToOverride

        i = i + 1
    end

    delete(xmlFile)

end



--***************************************************************************************************
--** return mr new filename for vehicle xml
RealisticUtils.getOverridingXmlFileNameData = function(itemName)

    local item

    --check DataBank
    if g_modIsLoaded["moreRealisticXmlDatabank"] then
        item = RealisticUtils.databankVehiclesModifiedData[itemName]
    end

    if item==nil then
        item = RealisticUtils.defaultVehiclesModifiedData[itemName]
    end

    if item==nil then
        item = RealisticUtils.defaultVehiclesModifiedData[string.gsub(itemName, "%$", "")]
    end

    return item

end

--***************************************************************************************************
--** return vanilla game vehicle xml filename (or vanilla mod xml filename)
RealisticUtils.getOverridedXmlFileName = function(itemName)

    local genuineFileName
    if g_modIsLoaded["moreRealisticXmlDatabank"] then
        genuineFileName = RealisticUtils.databankVehicleMrFilenameToGenuineFilename[string.lower(itemName)]
    end

    if genuineFileName==nil then
        genuineFileName = RealisticUtils.defaultVehicleMrFilenameToGenuineFilename[string.lower(itemName)]
    end

    return genuineFileName
end


--**********************************************************************************************************************************************************
-- return the full path to the "dataBank" file of a given vehicle
-- use the mod named : "moreRealisticXmlDatabank"
RealisticUtils.getDatabankVehiclePath = function(configFileName)

    local databankPath = g_modsDirectory .. "moreRealisticXmlDatabank/convertedXml/"   --getUserProfileAppPath() .. "mrXmlDatabank/"
    local splitXmlPath = configFileName:split("/")
    local xmlNameOnly = splitXmlPath[#splitXmlPath] --get the last "word" in the full xml file path

    local modFolderName = "default" --we can override default vehicle too by using the "default" prefix
    local _, baseDirectory = Utils.getModNameAndBaseDirectory(configFileName)

    if baseDirectory~="" then
        local splitDirectoryPath = baseDirectory:split("/")
        --print("test base directory - splitDirectoryPath num=".. table.getn(splitDirectoryPath) .." .. modDirectory="..splitDirectoryPath[#splitDirectoryPath-1])
        modFolderName = splitDirectoryPath[#splitDirectoryPath-1] --  remove 1 because the last character is "/" for baseDirectory
    end

    local mrXmlDatabankFilepath = databankPath .. modFolderName .. "_MR_" .. xmlNameOnly

    --print("test - " .. mrXmlDatabankFilepath .. " - baseDirectory="..baseDirectory)

    return mrXmlDatabankFilepath

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

--return centerofmass (x,y,z) and "coordinate node" of the object
RealisticUtils.getCenterOfMass = function(object)
    local cx, cy, cz
    local coordinateNode
    if object.nodeId~=nil then
        coordinateNode = object.nodeId
        cx, cy, cz = getCenterOfMass(coordinateNode)
    elseif object.components~=nil then
        coordinateNode = object.components[1].node
        cx, cy, cz = getCenterOfMass(coordinateNode)
        if #object.components>1 then
            local currentTotalMass = object.components[1].mrDefaultMass
            for i=2, #object.components do
                local cNode = object.components[i].node
                local componentMass = object.components[i].mrDefaultMass
                local totalMass = currentTotalMass + componentMass
                local comX, comY, comZ = getCenterOfMass(cNode)
                comX, comY, comZ = localToLocal(cNode, coordinateNode, comX, comY, comZ) --we want all the center of masses coordinates in the "first component coordinate system"

                cx = (currentTotalMass*cx+componentMass*comX)/totalMass
                cy = (currentTotalMass*cy+componentMass*comY)/totalMass
                cz = (currentTotalMass*cz+componentMass*comZ)/totalMass

                currentTotalMass = totalMass
            end
        end
    end
    return coordinateNode, cx, cy, cz
end

