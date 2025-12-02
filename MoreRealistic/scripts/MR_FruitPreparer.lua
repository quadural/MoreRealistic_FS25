FruitPreparer.mrInitSpecialization = function()
    local schema = Vehicle.xmlSchema
    schema:setXMLSpecializationType("FruitPreparer")
    schema:register(XMLValueType.STRING, "vehicle.fruitPreparer#mrPowerScaling", "power factor in KW per m2 per second")
    schema:setXMLSpecializationType()
end
FruitPreparer.initSpecialization = Utils.appendedFunction(FruitPreparer.initSpecialization, FruitPreparer.mrInitSpecialization)


FruitPreparer.mrOnLoad = function(self, superFunc, savegame)

    self.mrFruitPreparerSampleTime = 700

    self.mrFruitPreparerAreaBuffer = 0
    self.mrFruitPreparerLastAreaTime = 0
    self.mrFruitPreparerAreaPerSecond = 0
    self.mrFruitPreparerAreaPerSecondS = 0
    self.mrFruitPreparerAreaPowerScaling = self.xmlFile:getValue("vehicle.fruitPreparer#mrPowerScaling") or 1

    return superFunc(self, savegame)

end
FruitPreparer.onLoad = Utils.overwrittenFunction(FruitPreparer.onLoad, FruitPreparer.mrOnLoad)


FruitPreparer.mrProcessFruitPreparerArea = function(self, superFunc, workArea)
    local dummy, workedArea = superFunc(self, workArea)

    if self.isServer then
        self.mrFruitPreparerAreaBuffer = self.mrFruitPreparerAreaBuffer + workedArea
        local sampleTime = g_time-self.mrFruitPreparerLastAreaTime
        if sampleTime>self.mrFruitPreparerSampleTime then
            self.mrFruitPreparerAreaPerSecond = 10000000 * MathUtil.areaToHa(self.mrFruitPreparerAreaBuffer, g_currentMission:getFruitPixelsToSqm()) / sampleTime --m2 / second
            self.mrFruitPreparerAreaPerSecondS = 0.5*self.mrFruitPreparerAreaPerSecondS + 0.5*self.mrFruitPreparerAreaPerSecond
            self.mrFruitPreparerAreaBuffer = 0
            self.mrFruitPreparerLastAreaTime = g_time
        end
    end

    return dummy, workedArea
end
FruitPreparer.processFruitPreparerArea = Utils.overwrittenFunction(FruitPreparer.processFruitPreparerArea, FruitPreparer.mrProcessFruitPreparerArea)
