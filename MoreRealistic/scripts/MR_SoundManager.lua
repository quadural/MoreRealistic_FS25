-- SoundManager.setSampleLoopSynthesisParameters = function(self, sample, rpm, loadFactor)
--     if sample ~= nil and sample.soundSample ~= nil then
--         if rpm ~= nil then
--             if sample.loopSynthesisRPMRatio ~= 1 then
--                 rpm = math.clamp(rpm / sample.loopSynthesisRPMRatio, 0, 3) --MR allow more "rpm"
--             end

--             setSampleLoopSynthesisRPM(sample.soundSample, rpm, true)
--         end

--         if loadFactor ~= nil then
--             setSampleLoopSynthesisLoadFactor(sample.soundSample, loadFactor)
--         end
--     end
-- end