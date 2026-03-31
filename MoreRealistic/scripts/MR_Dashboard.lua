Dashboard.mrRegisterDashboardValueType = function(self, superFunc, dashboardValueType)

    if dashboardValueType~=nil and dashboardValueType.specName=="motorized" then
        --override the "speedDir" value function for dashboard => using the "mrGetDashboardSpeedDir" function
        if dashboardValueType.name=="speedDir" then
            dashboardValueType:setValue(self, function() return Motorized.mrGetDashboardSpeedDir(self) end)
        elseif dashboardValueType.name=="fuelUsage" then
            dashboardValueType:setValue(self, function() return Motorized.mrGetDashboardFuelUsage(self) end)
        end
    end

    superFunc(self, dashboardValueType)

end
Dashboard.registerDashboardValueType = Utils.overwrittenFunction(Dashboard.registerDashboardValueType, Dashboard.mrRegisterDashboardValueType)


--dashboard rpm and speed refresh rate are insane. And moreover, IRL, we don't get rpmmeter precise at 1 rpm unit (most of the time = 10rpm by 10rpm step)
Dashboard.mrDefaultDashboardStateFunc = function(self, superFunc, dashboard, newValue, minValue, maxValue, isActive)


    local refreshWanted = true
    if dashboard~=nil and dashboard.valueType~=nil and dashboard.node~=nil then

        if not dashboard.mrInitialized then
            if self.mrDashboardsPerNode == nil then
                self.mrDashboardsPerNode = {}
            end
            if self.mrDashboardsPerNode[dashboard.node]==nil then
                self.mrDashboardsPerNode[dashboard.node] = 1
            else
                self.mrDashboardsPerNode[dashboard.node] = self.mrDashboardsPerNode[dashboard.node] + 1
            end
            dashboard.mrInitialized = true
        end

        if not isActive then
            --special case = speed display with duplicate dashboard. One from 0 to 9.99 and another from 10.0 to max speed
            --we want to know if the dashboard is not active because the value is too high or because the group is inactive
            --in such case = no refresh if the timer of the dashboard is not ringing
            --example : john deere 8R pillar speed display
            if self.mrDashboardsPerNode~=nil and self.mrDashboardsPerNode[dashboard.node]>1 and self.mrDashboardTimers~=nil and self.mrDashboardTimers[dashboard.node]~=nil and self.mrDashboardTimers[dashboard.node].currentTime>0 then
                for j=1, #dashboard.groups do
                    if dashboard.groups[j].isActive then
                        refreshWanted = false
                        --dashboard.lastValue = 9999 -- force refresh of this dashboard the next time Dashboard.updateDashboards is called
                        break
                    end
                end
            end

        else
            local displayTypeTextIndex = Dashboard.TYPES["TEXT"]
            if dashboard.valueType.fullName=="motorized.rpm" and dashboard.displayTypeIndex==displayTypeTextIndex then
                refreshWanted, newValue =  Dashboard.mrDisplayRateAndPrecision(self, dashboard, newValue, 300, 10, 1)
            elseif dashboard.valueType.fullName=="motorized.speed" and dashboard.displayTypeIndex==displayTypeTextIndex then
                refreshWanted, newValue =  Dashboard.mrDisplayRateAndPrecision(self, dashboard, newValue, 400, 0.1, 1)
            elseif dashboard.valueType.fullName=="motorized.fuelUsage" and dashboard.displayTypeIndex==displayTypeTextIndex then
                refreshWanted, newValue =  Dashboard.mrDisplayRateAndPrecision(self, dashboard, newValue, 900, 0.1, 5)
            elseif dashboard.valueType.fullName=="motorized.load" and dashboard.displayTypeIndex==displayTypeTextIndex then
                refreshWanted, newValue =  Dashboard.mrDisplayRateAndPrecision(self, dashboard, newValue, 900, 1, 5, true)
            end
        end
    end

    if refreshWanted then
        superFunc(self, dashboard, newValue, minValue, maxValue, isActive)
    else
        dashboard.lastValue = 9999 -- we want to test if refresh if needed or not the next update
    end

end
Dashboard.defaultDashboardStateFunc = Utils.overwrittenFunction(Dashboard.defaultDashboardStateFunc, Dashboard.mrDefaultDashboardStateFunc)



Dashboard.mrDisplayRateAndPrecision = function(self, dashboard, newValue, timeStep, precision, smoothFx, positiveOnly)

    --timer is now linked to the vehicle => same timer if 2 dashboards are using the same node
    if self.mrDashboardTimers[dashboard.node]==nil then
        self.mrDashboardTimers[dashboard.node] = {}
        self.mrDashboardTimers[dashboard.node].currentTime = -1
        self.mrDashboardTimers[dashboard.node].timeStep = timeStep
        dashboard.mrTimerInitialized = true
    end

    if self.mrDashboardTimers[dashboard.node].currentTime<=0 then

        self.mrDashboardTimers[dashboard.node].consumed = true

        local lastValue = dashboard.lastValue
        if positiveOnly then
            lastValue = math.max(0, lastValue)
            newValue = math.max(0, newValue)
        end

        --local smoothValue = 0.1*(6-smoothFx)*newValue+0.1*(4+smoothFx)*lastValue
        --newValue = precision*math.round(smoothValue/precision)--rounded to precision
        --dashboard.mrLastTime = g_time
        --dashboard.mrLastValue = newValue

        newValue = precision*math.floor(newValue/precision)--rounded to precision "below" to avoid problem with "maxActiveValue" of the dashboard

        return true, newValue
    else
--         if math.abs(dashboard.mrLastValue-dashboard.lastValue)>precision then
--             dashboard.lastValue = dashboard.mrLastValue
--         end
        return false, 0 --no refresh
    end

end



--update all the individual dashboard timers
Dashboard.mrOnUpdate = function(self, superFunc, dt, isActiveForInput, isActiveForInputIgnoreSelection, isSelected)

    if self.isClient then
        if self.mrDashboardTimers==nil then
            self.mrDashboardTimers={}
        else
            for _, timer in pairs(self.mrDashboardTimers) do
                if timer.consumed then
                    timer.currentTime = timer.timeStep
                    timer.consumed = false
                elseif timer.currentTime>0 then
                    timer.currentTime = timer.currentTime - dt
                end
            end
        end
    end

    superFunc(self, dt, isActiveForInput, isActiveForInputIgnoreSelection, isSelected)

end
Dashboard.onUpdate = Utils.overwrittenFunction(Dashboard.onUpdate, Dashboard.mrOnUpdate)