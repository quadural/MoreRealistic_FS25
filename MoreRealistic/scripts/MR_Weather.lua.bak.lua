--20261110 - doesn't take into account current month anymore. Because it highly depends on the map location IRL
--only take into account current 'minTemprature', 'maxTemperature', and 'currentTemperature' g_currentMission.environment.weather.temperatureUpdater.currentMax VehicleDebug.state // weather:getCurrentTemperature()
--base game settings seem a little bit "OFF".
--there are no settings by month.
--settings are by season.
-- season 1 = spring (march april may)
-- season 2 = summer (june july august)
-- season 3 = autumn (september october november)
-- season 4 = winter (december january february)
--it means player can experience the same weather/temperatures in march and may, or in june and august, or in september and november, or in december and february.
--it doesn't fit my area at all for example (north of france). The temperatures in november are just "crazy" compared to IRL here.
--and it means we can experience a "gap" when changing season (great difference between may and june for example)
--another "flaw" = each base game map has the exact same config (USA, European and Asian map => not realistic at all)

Weather.mrCurrentWetness = 0 --init
Weather.mrCurrentWetnessMin = 0
Weather.mrCurrentWetnessDamp = 0
Weather.mrUpdateTimer = 0


Weather.mrGetGroundWetness = function(self, superFunc, updateMR, dt)

    if updateMR then

        local wetness = superFunc(self)

        local minWetness = 0
        if g_currentMission.environment.weather.temperatureUpdater.currentMax<10 then
            minWetness = 0.25
        elseif g_currentMission.environment.weather.temperatureUpdater.currentMax<30 then
            minWetness = (30 - g_currentMission.environment.weather.temperatureUpdater.currentMax)/80 --10°C = 25% / 30°C = 0%
        end

        local dampWetness = 0
        if g_currentMission.environment.isSunOn then
            if Weather.mrCurrentWetnessDamp>0 then
                local timeScale = g_currentMission:getEffectiveTimeScale()
                local fxTemp = math.max(0.1, g_currentMission.environment.weather:getCurrentTemperature()/25)
                fxTemp = math.pow(fxTemp, 0.7)
                dampWetness = math.max(0, Weather.mrCurrentWetnessDamp - 0.1*fxTemp*timeScale*dt/3600000) --decrease dampness when the sun is present. 1 hour to go from 10% to 0% dampness when the outdoor temperature is 25°C
            end
        else
            local currentTemperature = g_currentMission.environment.weather:getCurrentTemperature()
            if currentTemperature<30 then
                if currentTemperature>25 then
                    dampWetness = 0.06-0.012*(currentTemperature-25)
                elseif currentTemperature>20 then
                    dampWetness = 0.115-0.011*(currentTemperature-20)
                elseif currentTemperature>15 then
                    dampWetness = 0.165-0.01*(currentTemperature-15)
                elseif currentTemperature>10 then
                    dampWetness = 0.205-0.008*(currentTemperature-10)
                elseif currentTemperature>5 then
                    dampWetness = 0.235-0.006*(currentTemperature-5)
                elseif currentTemperature>0 then
                    dampWetness = 0.25-0.003*currentTemperature
                else
                    dampWetness = 0.25
                end
            end
        end

        wetness = math.max(minWetness, dampWetness, wetness)

        --telemetry
        Weather.mrCurrentWetnessMin = minWetness
        Weather.mrCurrentWetnessDamp = dampWetness
        Weather.mrCurrentWetness = wetness

    end

    return Weather.mrCurrentWetness
end


--[[ old function
Weather.mrGetGroundWetness = function(self, superFunc)

    local wetness = superFunc(self)

    --minimum groundwetness function of month and time
    -- wetness during night => +0.1
    -- wetness during winter
    -- period = month
    -- season 1 = spring (march april may)
    -- season 2 = summer (june july august)
    -- season 3 = autumn (september october november)
    -- season 4 = winter (december january february)
    local month = g_currentMission.environment.currentPeriod
    local minWetness = 0
    local dampStart=99
    local dampStop=0
    if month==11 then --january
        minWetness = 0.25
    elseif month==12 then --february
        minWetness = 0.20
    elseif month==1 then --march
        minWetness = 0.15
        dampStart = 19
        dampStop = 11
    elseif month==2 then --april
        minWetness = 0.1
        dampStart = 19
        dampStop = 11
    elseif month==3 then --may
        minWetness = 0.05
        dampStart = 19
        dampStop = 10
    elseif month==4 then --june
        minWetness = 0
        dampStart = 20
        dampStop = 10
    elseif month==5 then --july
        minWetness = 0
        dampStart = 21
        dampStop = 9
    elseif month==6 then --august
        minWetness = 0
        dampStart = 22
        dampStop = 9
    elseif month==7 then --september
        minWetness = 0.1
        dampStart = 20
        dampStop = 10
    elseif month==8 then --october
        minWetness = 0.15
        dampStart = 19
        dampStop = 11
    elseif month==9 then --november
        minWetness = 0.2
    elseif month==10 then --december
        minWetness = 0.25
    end

    --damp = can't increase minWetness above 0.2
    if minWetness<0.2 then
        local damp = 0
        local hour = g_currentMission.environment.currentHour + g_currentMission.environment.currentMinute / 60
        --2hours for damp to fully increase or decrease
        if hour>dampStart then
            damp = math.min(0.1, hour-dampStart * 0.05)
        elseif hour<dampStop then
            damp = math.min(0.1, dampStop-hour * 0.05)
        end
        minWetness = math.min(0.2, minWetness + damp)
    end

    wetness = math.max(minWetness, wetness)

    return wetness
end
--]]
