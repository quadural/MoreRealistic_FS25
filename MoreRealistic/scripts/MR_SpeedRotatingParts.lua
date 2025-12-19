
SpeedRotatingParts.mrInitSpecialization = function()
    local schema = Vehicle.xmlSchema
    schema:setXMLSpecializationType("SpeedRotatingParts")
    schema:register(XMLValueType.BOOL, SpeedRotatingParts.SPEED_ROTATING_PART_XML_KEY .. "#mrOnlyActiveWhenTurnedOn", "only active when turned on")
    schema:setXMLSpecializationType()
end
SpeedRotatingParts.initSpecialization = Utils.appendedFunction(SpeedRotatingParts.initSpecialization, SpeedRotatingParts.mrInitSpecialization)


---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- add some randomness, otherwise, it doesn't feel real (example : rollers when lifting the smaragd 500K)
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
SpeedRotatingParts.mrLoadSpeedRotatingPartFromXML = function(self, superFunc, speedRotatingPart, xmlFile, key)

    if superFunc(self, speedRotatingPart, xmlFile, key) then
        speedRotatingPart.fadeOutTime = xmlFile:getValue(key .. "#fadeOutTime", 6) * 1000 * (0.8+0.2*math.random(0,2)) --between 0.8x and 1.2x the value
        speedRotatingPart.mrOnlyActiveWhenTurnedOn = xmlFile:getValue(key .. "#mrOnlyActiveWhenTurnedOn", false)
        return true
    end
    return false

end
SpeedRotatingParts.loadSpeedRotatingPartFromXML = Utils.overwrittenFunction(SpeedRotatingParts.loadSpeedRotatingPartFromXML, SpeedRotatingParts.mrLoadSpeedRotatingPartFromXML)


---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- add "mrOnlyActiveWhenTurnedOn" param
-- example : grimme GL860 exacta => the cup belts are driven hydraulically (and so, they can only rotate when the planter is turned on and moving)
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
SpeedRotatingParts.mrGetIsSpeedRotatingPartActive = function(self, superFunc, speedRotatingPart)
    local result = superFunc(self, speedRotatingPart)

    if result then
        if speedRotatingPart.mrOnlyActiveWhenTurnedOn then
            if self.getIsTurnedOn ~= nil and not self:getIsTurnedOn() then
                return false
            end
        end
        return true
    end

    return false
end
SpeedRotatingParts.getIsSpeedRotatingPartActive = Utils.overwrittenFunction(SpeedRotatingParts.getIsSpeedRotatingPartActive, SpeedRotatingParts.mrGetIsSpeedRotatingPartActive)
