StoreManager.mrLoadItem = function(self, superFunc, rawXMLFilename, baseDir, customEnvironment, isMod, isBundleItem, dlcTitle, extraContentId, ignoreAdd)

    if baseDir=="" or dlcTitle~="" then -- this is a base game vehicle (or DLC) = we want to check if we ovveride it with a MR version

        local item = RealisticUtils.getOverridingXmlFileNameData(rawXMLFilename)

        if item~=nil then
            local mrConfigFileName = item.newFileName

            --20250614 -store the full path of the item too (indeed, for DLC vehicle by example, once loaded, the full path is the index // vanilla game => index=relative path)
            local fullFileName = baseDir .. rawXMLFilename
            if RealisticUtils.defaultVehiclesModifiedData[fullFileName]==nil then
                RealisticUtils.defaultVehiclesModifiedData[fullFileName] = item
            end
            --override value with full path
            if baseDir~="" then
                RealisticUtils.defaultVehicleMrFilenameToGenuineFilename[string.lower(mrConfigFileName)] = fullFileName
            end

            --20250613 - we want to keep "cutomEnvironment" and "baseDir" (function Vehicle:setFileName // Utils.getModNameAndBaseDirectory)
            if item.keepEnvironment then
                RealisticUtils.defaultVehiclesKeepEnvironmentTable[mrConfigFileName] = fullFileName
                rawXMLFilename = "$" .. mrConfigFileName -- $ tells the game not to concatenate baseDir and xmlfile path
            else
                rawXMLFilename = mrConfigFileName
            end
        end

    end

    ------------------------------------------------------------------------------------------------------------------------------------------
    --this code allow us to get the xml content of DLC vehicles so that we can override them with MR version
--     if dlcTitle~="" then
--         if string.find(rawXMLFilename,"1156") then
--             local xmlFilename = Utils.getFilename(rawXMLFilename, baseDir)
--             local xmlFile = loadXMLFile("storeItemXML", xmlFilename)
--             local xmlString = saveXMLFileToMemory(xmlFile)
--             print(xmlString)
--             delete(xmlFile)
--         end
--     end
    ------------------------------------------------------------------------------------------------------------------------------------------

    local storeItem = superFunc(self, rawXMLFilename, baseDir, customEnvironment, isMod, isBundleItem, dlcTitle, extraContentId, ignoreAdd)

    if storeItem~=nil then
        --check if MR tag is present
        local xmlFilename = Utils.getFilename(rawXMLFilename, baseDir)
        local xmlFile = loadXMLFile("storeItemXML", xmlFilename)
        local isMrVehicle = getXMLBool(xmlFile, "vehicle.MR") or false
        delete(xmlFile)
        if isMrVehicle then
            storeItem.name = "MR " .. storeItem.name
        end
    end

    return storeItem
end
StoreManager.loadItem = Utils.overwrittenFunction(StoreManager.loadItem, StoreManager.mrLoadItem)


StoreManager.mrAddPackItem = function(self, superFunc, name, itemFilename)
    local item = RealisticUtils.getOverridingXmlFileNameData(itemFilename)
    if item~=nil then
        itemFilename = item.newFileName
    end

    return superFunc(self, name, itemFilename)
end
StoreManager.addPackItem = Utils.overwrittenFunction(StoreManager.addPackItem, StoreManager.mrAddPackItem)

StoreManager.mrGetItemByXMLFilename = function(self, superFunc, xmlFilename)
    if xmlFilename ~= nil then
        --check if MR version is present
        local item = RealisticUtils.getOverridingXmlFileNameData(xmlFilename)
        if item~=nil then
            xmlFilename = item.newFileName
        end
    end

    return superFunc(self, xmlFilename)
end
StoreManager.getItemByXMLFilename = Utils.overwrittenFunction(StoreManager.getItemByXMLFilename, StoreManager.mrGetItemByXMLFilename)

---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
--MR : fix combination display in the ingame store (we want base game combinations to show even if the vehicle is MR converted)
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
StoreManager.mrGetItemsByCombinationData = function(self, superFunc, combinationData)

    --check if this is a MR converted base game vehicle
    if combinationData.xmlFilename ~= nil then
        --check customXMLFilename and xmlFilename
        local overridingData = RealisticUtils.getOverridingXmlFileNameData(combinationData.customXMLFilename)
        if overridingData~=nil then
            combinationData.customXMLFilename = overridingData.newFileName
        end
        overridingData = RealisticUtils.getOverridingXmlFileNameData(combinationData.xmlFilename)
        if overridingData~=nil then
            combinationData.xmlFilename = overridingData.newFileName
        end
    end

    return superFunc(self, combinationData)

end
StoreManager.getItemsByCombinationData = Utils.overwrittenFunction(StoreManager.getItemsByCombinationData, StoreManager.mrGetItemsByCombinationData)