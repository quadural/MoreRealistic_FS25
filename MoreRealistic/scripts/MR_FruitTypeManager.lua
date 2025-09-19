---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- we only want to override default game fruitTypes
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
FruitTypeManager.mrLoadDefaultTypes = function(self, superFunc)
    FruitTypeManager.mrIsLoadingDefaultFruitTypes = true
    --load mr list of default fillType to override
    FruitTypeManager.mrLoadFruitTypeList()
    superFunc(self)
    FruitTypeManager.mrIsLoadingDefaultFruitTypes = false
    FruitTypeManager.mrFruitTypeList = nil
end
FruitTypeManager.loadDefaultTypes = Utils.overwrittenFunction(FruitTypeManager.loadDefaultTypes, FruitTypeManager.mrLoadDefaultTypes)

---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Override some default yield values--
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
FruitTypeManager.mrAddFruitType = function(self, superFunc, fruitTypeDesc)
    superFunc(self, fruitTypeDesc)
    if FruitTypeManager.mrIsLoadingDefaultFruitTypes then
        --check if there is a Morerealistic value for the massPerLiter
        FruitTypeManager.mrCheckFruitType(fruitTypeDesc)
    end
end
FruitTypeManager.addFruitType = Utils.overwrittenFunction(FruitTypeManager.addFruitType, FruitTypeManager.mrAddFruitType)


---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Parse mrFruitTypeList to check if there is a mr value for the literPerSqm of the given fruitType
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
FruitTypeManager.mrCheckFruitType = function(fruitTypeDesc)
    if FruitTypeManager.mrFruitTypeList[fruitTypeDesc.name]~=nil then
        if FruitTypeManager.mrFruitTypeList[fruitTypeDesc.name].literPerSqm~=nil then
            fruitTypeDesc.literPerSqm = FruitTypeManager.mrFruitTypeList[fruitTypeDesc.name].literPerSqm
        end
        fruitTypeDesc.mrCapacityFx = FruitTypeManager.mrFruitTypeList[fruitTypeDesc.name].capacityFx
        fruitTypeDesc.mrThreshingFx = FruitTypeManager.mrFruitTypeList[fruitTypeDesc.name].threshingFx
        fruitTypeDesc.mrChopperFx = FruitTypeManager.mrFruitTypeList[fruitTypeDesc.name].chopperFx
    end
end


---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Load mr fruitType xml file
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
FruitTypeManager.mrLoadFruitTypeList = function()
    FruitTypeManager.mrFruitTypeList = {}
    local xmlFile = loadXMLFile("fruitTypes", RealisticUtils.mrBaseDir .. "data/fruitTypes.xml")
    local i = 0
    while true do
        local fruitTypeXmlPath = string.format("fruitTypes.fruitType(%d)", i)
        if not hasXMLProperty(xmlFile, fruitTypeXmlPath) then break end
        local name = getXMLString(xmlFile, fruitTypeXmlPath.."#name")
        local literPerHa = getXMLFloat(xmlFile, fruitTypeXmlPath.."#litersPerHa")
        local capacityFx = getXMLFloat(xmlFile, fruitTypeXmlPath.."#capacityFx") or 1
        local threshingFx = getXMLFloat(xmlFile, fruitTypeXmlPath.."#threshingFx") or 1
        local chopperFx = getXMLFloat(xmlFile, fruitTypeXmlPath.."#chopperFx") or 1
        FruitTypeManager.mrFruitTypeList[name] = {}
        if literPerHa~=nil then
            FruitTypeManager.mrFruitTypeList[name].literPerSqm=literPerHa/20000 --literPerHa to literPerSqm => divide by 10000. Then, LiterPerSqm in game = worst yield (no fertilization, no ploughing etc => 50% of best yield) => we have to divide by 2
        end
        FruitTypeManager.mrFruitTypeList[name].capacityFx = capacityFx
        FruitTypeManager.mrFruitTypeList[name].threshingFx = threshingFx
        FruitTypeManager.mrFruitTypeList[name].chopperFx = chopperFx
        i=i+1
    end
    delete(xmlFile)
end
