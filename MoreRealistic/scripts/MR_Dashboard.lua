Dashboard.mrRegisterDashboardValueType = function(self, superFunc, dashboardValueType)

    --override the "speedDir" value function for dashboard => using the "mrGetDashboardSpeedDir" function
    if dashboardValueType~=nil and dashboardValueType.specName=="motorized" and dashboardValueType.name=="speedDir" then
        dashboardValueType:setValue(self, function() return Motorized.mrGetDashboardSpeedDir(self) end)
    end

    superFunc(self, dashboardValueType)

end
Dashboard.registerDashboardValueType = Utils.overwrittenFunction(Dashboard.registerDashboardValueType, Dashboard.mrRegisterDashboardValueType)


--dashboard rpm and speed refresh rate are insane. And moreover, IRL, we don't get rpmmeter precise at 1 rpm unit (most of the time = 10rpm by 10rpm step)
Dashboard.mrDefaultDashboardStateFunc = function(self, superFunc, dashboard, newValue, minValue, maxValue, isActive)


    local refreshWanted = true
    if dashboard~=nil and dashboard.valueType~=nil then
        if not isActive then
            dashboard.mrLastTimer = 0
        else
            local displayTypeTextIndex = Dashboard.TYPES["TEXT"]
            if dashboard.valueType.fullName=="motorized.rpm" and dashboard.displayTypeIndex==displayTypeTextIndex then
                refreshWanted, newValue =  Dashboard.mrDisplayRateAndPrecision(dashboard, newValue, 400, 10, 1)
            elseif dashboard.valueType.fullName=="motorized.speed" and dashboard.displayTypeIndex==displayTypeTextIndex then
                refreshWanted, newValue =  Dashboard.mrDisplayRateAndPrecision(dashboard, newValue, 600, 0.1, 1)
            elseif dashboard.valueType.fullName=="motorized.fuelUsage" and dashboard.displayTypeIndex==displayTypeTextIndex then
                refreshWanted, newValue =  Dashboard.mrDisplayRateAndPrecision(dashboard, newValue, 900, 0.1, 5)
            elseif dashboard.valueType.fullName=="motorized.load" and dashboard.displayTypeIndex==displayTypeTextIndex then
                refreshWanted, newValue =  Dashboard.mrDisplayRateAndPrecision(dashboard, newValue, 900, 1, 5, true)
            end
        end
    end

    if refreshWanted then
        superFunc(self, dashboard, newValue, minValue, maxValue, isActive)
    end

end
Dashboard.defaultDashboardStateFunc = Utils.overwrittenFunction(Dashboard.defaultDashboardStateFunc, Dashboard.mrDefaultDashboardStateFunc)



Dashboard.mrDisplayRateAndPrecision = function(dashboard, newValue, timeStep, precision, smoothFx, positiveOnly)

    if dashboard.mrLastTimer==nil then
        dashboard.mrLastTimer = 0
    else
        dashboard.mrLastTimer = dashboard.mrLastTimer - g_physicsDtLastValidNonInterpolated
    end

    if dashboard.mrLastTimer<=0 then
        dashboard.mrLastTimer = timeStep
        local lastValue = dashboard.lastValue
        if positiveOnly then
            lastValue = math.max(0, lastValue)
            newValue = math.max(0, newValue)
        end

        local smoothValue = 0.1*(6-smoothFx)*newValue+0.1*(4+smoothFx)*lastValue
        newValue = precision*math.round(smoothValue/precision)--rounded to precision
        dashboard.mrLastTime = g_time
        dashboard.mrLastValue = newValue
        return true, newValue
    else
        if math.abs(dashboard.mrLastValue-dashboard.lastValue)>precision then
            dashboard.lastValue = dashboard.mrLastValue
        end
        return false, 0 --no refresh
    end

end
