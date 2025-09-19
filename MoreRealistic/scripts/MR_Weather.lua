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

