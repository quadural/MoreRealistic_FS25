--there is no PowerConsumer in the "loaderVehicle" vehicle type => example : ropa maus.
--and so, we have to make our own script to allow engine reving at work and power consumption

MRConveyorLoaderVehicle = {}

MRConveyorLoaderVehicle.mrLoadMrValues = function(self, xmlFile)
    local ptoRpm = getXMLFloat(xmlFile, "vehicle.mrConveyorLoaderVehicle#ptoRpm")

    if ptoRpm~=nil then
        self.mrConveyorLoaderVehicle = {}
        self.mrConveyorLoaderVehicle.ptoRpm = ptoRpm
        self.mrConveyorLoaderVehicle.turnedOnPower = getXMLFloat(xmlFile, "vehicle.mrConveyorLoaderVehicle#turnedOnPower") or 0
        self.mrConveyorLoaderVehicle.activeIdlePower = getXMLFloat(xmlFile, "vehicle.mrConveyorLoaderVehicle#activeIdlePower") or 0
        self.mrConveyorLoaderVehicle.activePowerPerLiter = getXMLFloat(xmlFile, "vehicle.mrConveyorLoaderVehicle#activePowerPerLiter") or 0
        self.mrConveyorLoaderVehicle.fillUnitIndex = getXMLFloat(xmlFile, "vehicle.mrConveyorLoaderVehicle#fillUnitIndex") or 1
        self.mrConveyorLoaderVehicle.lastPtoPower = 0

        if self.mrConveyorLoaderVehicle.ptoRpm>0 then
            self.getPtoRpm = MRConveyorLoaderVehicle.getPtoRpm
            if self.mrConveyorLoaderVehicle.turnedOnPower>0 or self.mrConveyorLoaderVehicle.activeIdlePower>0 or self.mrConveyorLoaderVehicle.activePowerPerLiter>0 then
                self.getConsumedPtoTorque = MRConveyorLoaderVehicle.getConsumedPtoTorque
            end
        end
        self.getFillUnitFreeCapacity = MRConveyorLoaderVehicle.getFillUnitFreeCapacity
    end
end


MRConveyorLoaderVehicle.getPtoRpm = function(self)
    if self.spec_turnOnVehicle~=nil and self.spec_turnOnVehicle.isTurnedOn then
        return self.mrConveyorLoaderVehicle.ptoRpm
    end
    if self.spec_conveyorBelt~=nil and self.spec_conveyorBelt.lastScrollUpdate then
        return self.mrConveyorLoaderVehicle.ptoRpm
    end
    return 0
end


MRConveyorLoaderVehicle.getConsumedPtoTorque = function(self)
    if self.mrConveyorLoaderVehicle.ptoRpm>0 then
        local neededPtoPower = 0

        if (self.spec_turnOnVehicle~=nil and self.spec_turnOnVehicle.isTurnedOn)  then
            self.mrForcePtoRpm = true
            neededPtoPower = self.mrConveyorLoaderVehicle.turnedOnPower
        end

        if self.spec_conveyorBelt~=nil and self.spec_conveyorBelt.lastScrollUpdate then

            neededPtoPower = neededPtoPower + self.mrConveyorLoaderVehicle.activeIdlePower

            local limitPower = false
            --limit neededPower when the engine is overloaded
            local rootVehicle = self.rootVehicle
            if rootVehicle ~= nil and rootVehicle.getMotor ~= nil then
                local rootMotor = rootVehicle:getMotor()
                if rootMotor~=nil then
                    if (rootMotor:getNonClampedMotorRpm()/rootMotor.ptoMotorRpmRatio)<(0.9*self.mrConveyorLoaderVehicle.ptoRpm) then
                        limitPower = true
                    end
                end
            end

            if not limitPower then
                local fillLevel = self:getFillUnitFillLevel(self.mrConveyorLoaderVehicle.fillUnitIndex)
                neededPtoPower = neededPtoPower + self.mrConveyorLoaderVehicle.activePowerPerLiter * fillLevel
                --progressive starting of the torque required
                if self.mrConveyorLoaderVehicle.lastPtoPower<0.9*neededPtoPower then
                    neededPtoPower = self.mrConveyorLoaderVehicle.lastPtoPower + neededPtoPower * g_physicsDtLastValidNonInterpolated/2000
                end
            end

        end

        if neededPtoPower>0 then
            self.mrConveyorLoaderVehicle.lastPtoPower = neededPtoPower
            return neededPtoPower / (self.mrConveyorLoaderVehicle.ptoRpm*math.pi/30)
        end
    end

    self.mrConveyorLoaderVehicle.lastPtoPower = 0
    return 0
end



--fix bug : capacity and fillLevel increasing indefinitely when "vehicle.dischargeable.dischargeNode#emptySpeed" is too low
MRConveyorLoaderVehicle.getFillUnitFreeCapacity = function(self, fillUnitIndex, fillTypeIndex, farmId)
    local fillUnit = self.spec_fillUnit.fillUnits[fillUnitIndex]
    if fillUnit ~= nil then
        local freeCapacity = fillUnit.defaultCapacity - fillUnit.fillLevel
        return math.max(0, freeCapacity)
    end
    return nil
end