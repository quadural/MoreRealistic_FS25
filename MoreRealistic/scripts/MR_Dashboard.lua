Dashboard.mrRegisterDashboardValueType = function(self, superFunc, dashboardValueType)

    --override the "speedDir" value function for dashboard => using the "mrGetDashboardSpeedDir" function
    if dashboardValueType~=nil and dashboardValueType.specName=="motorized" and dashboardValueType.name=="speedDir" then
        dashboardValueType:setValue(self, function() return Motorized.mrGetDashboardSpeedDir(self) end)
    end

    superFunc(self, dashboardValueType)

end
Dashboard.registerDashboardValueType = Utils.overwrittenFunction(Dashboard.registerDashboardValueType, Dashboard.mrRegisterDashboardValueType)


