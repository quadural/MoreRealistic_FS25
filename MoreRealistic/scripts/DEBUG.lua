function Motorized:setGearLeversState(gear, group, time, isResetPosition)
    local spec = self.spec_motorized
    for i=1, #spec.gearLevers do
        local gearLever = spec.gearLevers[i]
        for j=1, #gearLever.states do
            local state = gearLever.states[j]
            if (state.gear ~= nil and state.gear == gear) or (state.group ~= nil and state.group == group) then
                self:generateShiftAnimation(gearLever, state, time, isResetPosition)
            end
        end
    end
end


function Motorized:onGearChanged(gear, targetGear, changeTime, previousGear)
    self:setGearLeversState(targetGear, nil, changeTime)

    local spec = self.spec_motorized
    if self.isClient then
        if gear == 0 then
            if not g_soundManager:getIsSamplePlaying(spec.samples.gearDisengaged) then
                g_soundManager:playSample(spec.samples.gearDisengaged)
            end
        else
            if not g_soundManager:getIsSamplePlaying(spec.samples.gearEngaged) then
                g_soundManager:playSample(spec.samples.gearEngaged)
            end

            if previousGear ~= 0 and spec.motor.currentGears ~= nil then
                local numGears = #spec.motor.currentGears
                local lowRangeMax = math.ceil(numGears * 0.5)

                if (previousGear <= lowRangeMax and gear > lowRangeMax) or (gear <= lowRangeMax and previousGear > lowRangeMax) then
                    if not g_soundManager:getIsSamplePlaying(spec.samples.gearRangeChange) then
                        g_soundManager:playSample(spec.samples.gearRangeChange)
                    end
                end
            end
        end
    end

    if self.isServer then
        self:raiseDirtyFlags(spec.dirtyFlag)
    end

    if self.isClient then
        if self.updateDashboardValueType ~= nil then
            self:updateDashboardValueType("motorized.gear")
            self:updateDashboardValueType("motorized.gearIndex")
        end
    end
end