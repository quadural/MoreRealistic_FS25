
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- MR : we want to tell the manure barrel that it is currently pumping from a "load trigger"
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
LoadTrigger.mrUpdate = function(self, superFunc, dt)
    superFunc(self, dt)
    if self.isServer and self.isLoading and self.currentFillableObject ~= nil then
        if self.currentFillableObject.mrIsMrManureBarrel then
            self.currentFillableObject.mrManureBarrelIsPumping = true
        end
    end
end
LoadTrigger.update = Utils.overwrittenFunction(LoadTrigger.update, LoadTrigger.mrUpdate)


LoadTrigger.mrStopLoading = function(self, superFunc)
    if self.isServer and self.isLoading and self.currentFillableObject ~= nil then
        if self.currentFillableObject.mrIsMrManureBarrel then
            self.currentFillableObject.mrManureBarrelIsPumping = false
        end
    end
    superFunc(self)
end
LoadTrigger.stopLoading = Utils.overwrittenFunction(LoadTrigger.stopLoading, LoadTrigger.mrStopLoading)