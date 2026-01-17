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

    local displayTypeTextIndex = Dashboard.TYPES["TEXT"]
    if dashboard~=nil and dashboard.valueType~=nil then
        if dashboard.valueType.fullName=="motorized.rpm" and dashboard.displayTypeIndex==displayTypeTextIndex then
            if dashboard.mrLastTime==nil or (g_time-dashboard.mrLastTime)>=400 then
                local smoothValue = 0.5*newValue+0.5*dashboard.lastValue
                newValue = 10*math.round(smoothValue/10)--rounded to 10 rpm
                dashboard.mrLastTime = g_time
                dashboard.mrLastValue = newValue
            else
                if math.abs(dashboard.mrLastValue-dashboard.lastValue)>10 then
                    dashboard.lastValue = dashboard.mrLastValue
                end
                return --no refresh
            end
        elseif dashboard.valueType.fullName=="motorized.speed" and dashboard.displayTypeIndex==displayTypeTextIndex then
            if dashboard.mrLastTime==nil or (g_time-dashboard.mrLastTime)>=550 then
                local smoothValue = 0.5*newValue+0.5*dashboard.lastValue
                newValue = 0.1*math.round(smoothValue*10)--rounded to .1 kph
                dashboard.mrLastTime = g_time
                dashboard.mrLastValue = newValue
            else
                if math.abs(dashboard.mrLastValue-dashboard.lastValue)>0.1 then
                    dashboard.lastValue = dashboard.mrLastValue
                end
                return --no refresh
            end
        end
    end

    superFunc(self, dashboard, newValue, minValue, maxValue, isActive)

end
Dashboard.defaultDashboardStateFunc = Utils.overwrittenFunction(Dashboard.defaultDashboardStateFunc, Dashboard.mrDefaultDashboardStateFunc)