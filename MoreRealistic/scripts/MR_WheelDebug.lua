WheelDebug.mrGetDebugValueHeader = function(self, superFunc)
    local table1 = superFunc(self)
    table1[16]="LoSlip\n"
    table1[17]="LaSlip\n"
    table1[18]="Frict\n"
    table1[19]="Fcoeff\n"
    table1[20]="WSpdS\n"
    table1[21]="Slip2\n"
    table1[22]="GType\n"
    table1[23]="rrFx\n"
    table1[24]="GPressure\n"
    return table1
end
WheelDebug.getDebugValueHeader = Utils.overwrittenFunction(WheelDebug.getDebugValueHeader, WheelDebug.mrGetDebugValueHeader)

WheelDebug.mrFillDebugValues = function(self, superFunc, debugTable)

    if not self.wheel.physics.wheelShapeCreated then
        return
    end

    superFunc(self, debugTable)

    if self.mrSmoothLongSlip==nil then
        self.mrSmoothLongSlip = 0
        self.mrSmoothLatSlip = 0
        self.mrSmoothSpeed = 0
    end

    self.mrSmoothLongSlip = 0.95*self.mrSmoothLongSlip + 0.05*self.wheel.physics.mrLastLongSlip
    self.mrSmoothLatSlip = 0.95*self.mrSmoothLatSlip + 0.05*self.wheel.physics.mrLastLatSlip
    self.mrSmoothSpeed = 0.95*self.mrSmoothSpeed + 0.05*self.wheel.physics.mrLastWheelSpeed

    local slip = 0
    if self.vehicle.lastSpeedReal>0.0001 then
        slip = math.abs(self.mrSmoothSpeed)/(self.vehicle.lastSpeedReal * 1000) -1
    end

    debugTable[16]  = debugTable[16]  .. string.format("%2.2f\n", self.mrSmoothLongSlip)
    debugTable[17]  = debugTable[17]  .. string.format("%2.2f\n", self.mrSmoothLatSlip)
    debugTable[18]  = debugTable[18]  .. string.format("%2.2f\n", self.wheel.physics.tireGroundFrictionCoeff)
    debugTable[19]  = debugTable[19]  .. string.format("%2.2f\n", self.wheel.physics.mrDynamicFrictionScale)
    debugTable[20]  = debugTable[20]  .. string.format("%2.2f\n", self.mrSmoothSpeed*3.6) --m/s to kph
    debugTable[21]  = debugTable[21]  .. string.format("%2.2f\n", slip)
    debugTable[22]  = debugTable[22]  .. string.format("%s\n", RealisticUtils.groundTypeToName[self.wheel.physics.mrLastGroundType])
    debugTable[23]  = debugTable[23]  .. string.format("%2.2f\n", self.wheel.physics.mrLastRrFx)
    debugTable[24]  = debugTable[24]  .. string.format("%2.2f\n", WheelPhysics.mrGetPressureFx(self.wheel.physics.mrTotalWidth, self.wheel.physics.radius, self.wheel.physics.mrLastTireLoad))

end
WheelDebug.fillDebugValues = Utils.overwrittenFunction(WheelDebug.fillDebugValues, WheelDebug.mrFillDebugValues)


-- MR : avoid hundred of error lines in the log when reloading a vehicle xml and Physics debug is activated
WheelDebug.mrDrawSlipGraphs = function(self, superFunc)
    if not self.wheel.physics.wheelShapeCreated then
        return
    end
    superFunc(self)
end
WheelDebug.drawSlipGraphs = Utils.overwrittenFunction(WheelDebug.drawSlipGraphs, WheelDebug.mrDrawSlipGraphs)