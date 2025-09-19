---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- we only want to override default game fillTypes
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
FillTypeManager.mrLoadDefaultTypes = function(self, superFunc)
    FillTypeManager.mrIsLoadingDefaultFillTypes = true
    --load mr list of default fillType to override
    FillTypeManager.mrLoadFillTypeList()
    superFunc(self)
    FillTypeManager.mrIsLoadingDefaultFillTypes = false
    FillTypeManager.mrFillTypeList = nil
end
FillTypeManager.loadDefaultTypes = Utils.overwrittenFunction(FillTypeManager.loadDefaultTypes, FillTypeManager.mrLoadDefaultTypes)

---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Override some default massPerLiter values
-- See "data\maps\maps_fillTypes.xml" to get all values from base game
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
FillTypeManager.mrAddFillType = function(self, superFunc, fillTypeDesc)
    local result = superFunc(self, fillTypeDesc)
    if result and FillTypeManager.mrIsLoadingDefaultFillTypes then
        --check if there is a Morerealistic value for the massPerLiter
        FillTypeManager.mrCheckFillType(fillTypeDesc)
    end
    return result
end
FillTypeManager.addFillType = Utils.overwrittenFunction(FillTypeManager.addFillType, FillTypeManager.mrAddFillType)


---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Parse mrFillTypeList to check if there is a better value for the massPerLiter of the given fillType
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
FillTypeManager.mrCheckFillType = function(fillTypeDesc)
    if FillTypeManager.mrFillTypeList[fillTypeDesc.name]~=nil then
        if FillTypeManager.mrFillTypeList[fillTypeDesc.name].massPerLiter~=0 then
            fillTypeDesc.massPerLiter = FillTypeManager.mrFillTypeList[fillTypeDesc.name].massPerLiter
        end
        if FillTypeManager.mrFillTypeList[fillTypeDesc.name].pricePerLiter~=0 then
            fillTypeDesc.pricePerLiter = FillTypeManager.mrFillTypeList[fillTypeDesc.name].pricePerLiter
        end
    end
end


---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Load mr fillType xml file
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
FillTypeManager.mrLoadFillTypeList = function()
    FillTypeManager.mrFillTypeList = {}
    local xmlFile = loadXMLFile("fillTypes", RealisticUtils.mrBaseDir .. "data/fillTypes.xml")
    local i = 0
    while true do
        local fillTypeXmlPath = string.format("fillTypes.fillType(%d)", i)
        if not hasXMLProperty(xmlFile, fillTypeXmlPath) then break end
        local name = getXMLString(xmlFile, fillTypeXmlPath.."#name")
        local density = getXMLFloat(xmlFile, fillTypeXmlPath.."#density") or 0
        local pricePerLiter = getXMLFloat(xmlFile, fillTypeXmlPath.."#pricePerLiter") or 0
        FillTypeManager.mrFillTypeList[name] = {}
        FillTypeManager.mrFillTypeList[name].massPerLiter=density/1000
        FillTypeManager.mrFillTypeList[name].pricePerLiter=pricePerLiter
        i=i+1
    end
    delete(xmlFile)
end
