---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- MR : fix bug when the "wheel config id" present in the savegame doesn't exist anymore for this vehicle (especially when this is a "dynamic wheel config id") => wheels were not loading at all
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
function VehicleConfigurationItemWheel.getFallbackConfigId(configs, configId, configName, configFileName)
    local parts = configId:split("_")

    local maxNumMatches, maxNumMatchesConfig = 0, nil
    for _, config in pairs(configs) do
        local otherParts = config.saveId:split("_")
        local numMatches = 0
        for i=1, math.min(#parts, #otherParts) do
            if parts[i] == otherParts[i] then
                numMatches = numMatches + 1
            else
                break
            end
        end

        --MR : avoid game engine not being able to load a "dynamic wheel config" present in the savegame but not present in the game.
        --we try to select the first matching dynamic wheel config
        numMatches = 10*numMatches + #otherParts
        if numMatches > maxNumMatches then
            maxNumMatches = numMatches
            maxNumMatchesConfig = config
        end
    end

    if maxNumMatchesConfig ~= nil then
        return maxNumMatchesConfig.index, maxNumMatchesConfig.saveId
    end

    return nil, nil
end