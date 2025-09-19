---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- add some randomness, otherwise, it doesn't feel real (example : rollers when lifting the smaragd 500K)
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
SpeedRotatingParts.mrLoadSpeedRotatingPartFromXML = function(self, superFunc, speedRotatingPart, xmlFile, key)

    if superFunc(self, speedRotatingPart, xmlFile, key) then
        speedRotatingPart.fadeOutTime = xmlFile:getValue(key .. "#fadeOutTime", 6) * 1000 * (0.8+0.2*math.random(0,2)) --between 0.8x and 1.2x the value
        return true
    end
    return false

end
SpeedRotatingParts.loadSpeedRotatingPartFromXML = Utils.overwrittenFunction(SpeedRotatingParts.loadSpeedRotatingPartFromXML, SpeedRotatingParts.mrLoadSpeedRotatingPartFromXML)