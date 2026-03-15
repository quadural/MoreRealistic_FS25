WoodCrusher.mrLoadWoodCrusher = function(self, superFunc, woodCrusher, xmlFile, rootNode, i3dMappings)
    superFunc(self, woodCrusher, xmlFile, rootNode, i3dMappings)

    --old way of loading xml values to be able to read the MR xml file instead of the genuine vehicle one
    local xmlFileMR = loadXMLFile("Vehicle", self.xmlFile.filename)
    woodCrusher.mrWoodCrusherPowerFx = getXMLFloat(xmlFileMR, "vehicle.mrWoodCrusher#powerFx") or 1
    woodCrusher.mrIdlePower = getXMLFloat(xmlFileMR, "vehicle.mrWoodCrusher#idlePower") or 15
    woodCrusher.mrMaxCrushingPowerPossible = getXMLFloat(xmlFileMR, "vehicle.mrWoodCrusher#maxCrushingPower")
    woodCrusher.mrMaxTractionForce = getXMLFloat(xmlFileMR, "vehicle.mrWoodCrusher#maxTractionForce") or 10
    woodCrusher.mrCutWidth = getXMLFloat(xmlFileMR, "vehicle.mrWoodCrusher#cutFeedWidth")
    woodCrusher.mrCutTargetY = getXMLFloat(xmlFileMR, "vehicle.mrWoodCrusher#cutTargetY")
    delete(xmlFileMR)

    if woodCrusher.mrCutWidth==nil then
        woodCrusher.mrCutWidth = 0.8*woodCrusher.cutSizeZ
    end

    self.mrWoodCrusherPowerConsumption = 0
    woodCrusher.mrFeedingActive = false
    woodCrusher.mrFeedingLastStateActive = false
    woodCrusher.mrFeedingLastVelocityFactor = 0
    woodCrusher.mrFeedingAnimationRunning = false
    woodCrusher.mrCrushingPowerWanted = 0
    woodCrusher.mrWaitingForFillLevel = false
    woodCrusher.mrCutLength = 0.15
    woodCrusher.mrWaitingFillLevel = 0
    if woodCrusher.mrCutTargetY==nil then
        woodCrusher.mrCutTargetY = 0.2
    end
    --mr traction
    woodCrusher.mrTractionNodes = {}
    woodCrusher.mrPendingTractionNodes = {}
    woodCrusher.mrCrushTimers = {}

    --no loss MR25 system
    woodCrusher.mrCheckSplitShapes = {}

    if woodCrusher.mrMaxCrushingPowerPossible==nil then
        --maxCrushingPower the woodcrusher can handle => above that, the feeding system will pause even if the tractor's engine has still power available
        local neededMaxPtoPower = xmlFile:getValue("vehicle.powerConsumer#neededMaxPtoPower")
        if neededMaxPtoPower~=nil then
            woodCrusher.mrMaxCrushingPowerPossible = 2*neededMaxPtoPower
        else
            woodCrusher.mrMaxCrushingPowerPossible = 350 --default value when nothing is found
        end
    end

    woodCrusher.mrMoveVelocityZ = woodCrusher.moveVelocityZ
    woodCrusher.moveVelocityZ = 0

end
WoodCrusher.loadWoodCrusher = Utils.overwrittenFunction(WoodCrusher.loadWoodCrusher, WoodCrusher.mrLoadWoodCrusher)

---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
--MR : we want a varying power requirement for the wood crusher depending on the "actual crushing load"
--     we want varying crushing time
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
WoodCrusher.mrCrushSplitShape = function(self, superFunc, woodCrusher, shape)
    if entityExists(shape) then
        local splitType = g_splitShapeManager:getSplitTypeByIndex(getSplitType(shape))
        if splitType ~= nil and splitType.woodChipsPerLiter > 0 then
            local volume = getVolume(shape)
            delete(shape)
            WoodCrusher.mrProcessVolume(self, woodCrusher, splitType, volume)
        end
    end
end
WoodCrusher.crushSplitShape = Utils.overwrittenFunction(WoodCrusher.crushSplitShape, WoodCrusher.mrCrushSplitShape)

WoodCrusher.mrProcessVolume = function(self, woodCrusher, splitType, volume)
    if splitType ~= nil and splitType.woodChipsPerLiter > 0 then
        local crushNeededTime = math.clamp(100000*volume, 700, 3000) --MR : varying crushing time
        woodCrusher.crushingTime = math.max(woodCrusher.crushingTime, crushNeededTime)
        self:onCrushedSplitShape(splitType, volume)
        local powerRequired = 4 * woodCrusher.mrWoodCrusherPowerFx * volume * splitType.volumeToLiter * splitType.woodChipsPerLiter --this takes into account the wood essence => the more woodChips produced, the more power consumed
        --20250622 - limit to 2x mrMaxCrushingPowerPossible because sometimes, a big piece of wood is crush in one time (usually = very high, very wide, but not thick)
        powerRequired = math.min(2*woodCrusher.mrMaxCrushingPowerPossible, powerRequired)
        woodCrusher.mrCrushingPowerWanted = woodCrusher.mrCrushingPowerWanted + powerRequired
    end
end

---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
--MR : we don't want to deliver the full volume in 1 millisecond. We want the volume to be released in 1s
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
WoodCrusher.mrOnCrushedSplitShape = function(self, superFunc, splitType, volume)
    local woodCrusher = self.spec_woodCrusher
    local damage = self:getVehicleDamage()
    if damage > 0 then
        volume = volume * (1 - damage * WoodCrusher.DAMAGED_YIELD_DECREASE)
    end
    local woodChipsVolume = volume * splitType.volumeToLiter * splitType.woodChipsPerLiter
    woodCrusher.mrWaitingFillLevel = woodCrusher.mrWaitingFillLevel + woodChipsVolume
end
WoodCrusher.onCrushedSplitShape = Utils.overwrittenFunction(WoodCrusher.onCrushedSplitShape, WoodCrusher.mrOnCrushedSplitShape)

---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
--MR : we want to limit crushing speed according to engine capability (base game = you can put the smallest engine matching the min power required and get the same result as a big one) = no point in putting a bigger tractor
--MR = the more power we have, the faster we can make woodchip
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
WoodCrusher.mrUpdateTickWoodCrusher = function(self, superFunc, woodCrusher, dt, isTurnedOn)

    if self.isServer then
        if not isTurnedOn then
            WoodCrusher.mrRemoveTractionJoints(woodCrusher)
            woodCrusher.mrFeedingLastVelocityFactor = 0
        else

            --20260313 remove tractionJoints that are too far from cutNode
            if woodCrusher.cutNode ~= nil then
                for id, tractionNode in pairs(woodCrusher.mrTractionNodes) do
                    if woodCrusher.moveTriggerNodes[id]==nil then
                        if not entityExists(id) then
                            woodCrusher.mrTractionNodes[id] = nil
                        else
                            local x,y,z = localToLocal(id, woodCrusher.cutNode, tractionNode.forcePointX, tractionNode.forcePointY, tractionNode.forcePointZ)  --position in the cutnode coordinate system
                            if z<-0.2 or z>(woodCrusher.mrCutWidth+0.2) or y>(woodCrusher.cutSizeY+0.5) or y<-0.2 or x>1 or x<-1 then
                                WoodCrusher.mrRemoveTractionNode(woodCrusher, id)
                            end
                        end
                    end
                end
            end

            if not woodCrusher.mrFeedingActive then
                if woodCrusher.mrFeedingLastStateActive then
                    woodCrusher.mrFeedingLastVelocityFactor = 0
                    if woodCrusher.moveColNodes ~= nil then
                        for _, moveColNode in pairs(woodCrusher.moveColNodes) do
                            setFrictionVelocity(moveColNode.node, 0.0)
                        end
                    end
                    --WoodCrusher.mrRemoveTractionJoints(woodCrusher)
                end
                woodCrusher.mrFeedingLastStateActive = false
            else
                woodCrusher.mrFeedingLastStateActive = true

                if woodCrusher.moveColNodes ~= nil then
                    if woodCrusher.mrFeedingLastVelocityFactor<1 then
                        woodCrusher.mrFeedingLastVelocityFactor = math.min(1, woodCrusher.mrFeedingLastVelocityFactor + dt/3000)
                        --for _, moveColNode in pairs(woodCrusher.moveColNodes) do
                            --setFrictionVelocity(moveColNode.node, woodCrusher.moveVelocityZ*woodCrusher.mrFeedingLastVelocityFactor)
                        --end
                    end
                end


                --20250628 - reset woodCrusher.mrCrushTimers if needed
                for shapeId in pairs(woodCrusher.mrCrushTimers) do
                    if not entityExists(shapeId) then
                        woodCrusher.mrCrushTimers[shapeId] = nil
                    end
                end

                if woodCrusher.cutNode ~= nil then
                    --20250626
                    --sometimes, there can be part of logs not caught by the moving nodes and not crushed
                    --> check if there is a shape waiting by the crusher node
                    local x,y,z = localToWorld(woodCrusher.cutNode, 0.2, 0 ,0)
                    local nx,ny,nz = localDirectionToWorld(woodCrusher.cutNode, 1,0,0)
                    local yx,yy,yz = localDirectionToWorld(woodCrusher.cutNode, 0,1,0)
                    --we want to define a plane and limit its size => x,y,z = one world point // nx,ny,nz = normal (perpendicular) vector to the plane we want
                    --yx,yy,yz = one vector of the plane => the crossproduct of nx,ny,nz and yx,yy,tz gives the second vector of the plane // cutSizeY and cutSizeZ = length of these two vectors
                    local foundShapeId, _, _, _, _ = findSplitShape(x, y, z, nx, ny, nz, yx, yy, yz, woodCrusher.cutSizeY, woodCrusher.cutSizeZ)
                    if foundShapeId==nil or foundShapeId==0 then
                        --test 20cm back
                        x,y,z = localToWorld(woodCrusher.cutNode, 0.4, 0 ,0)
                        foundShapeId, _, _, _, _ = findSplitShape(x, y, z, nx, ny, nz, yx, yy, yz, woodCrusher.cutSizeY, woodCrusher.cutSizeZ)
                    end
                    if foundShapeId==nil or foundShapeId==0 then
                        --test 20cm front
                        x,y,z = localToWorld(woodCrusher.cutNode, 0, 0 ,0)
                        foundShapeId, _, _, _, _ = findSplitShape(x, y, z, nx, ny, nz, yx, yy, yz, woodCrusher.cutSizeY, woodCrusher.cutSizeZ)
                    end
                    if foundShapeId~=nil and foundShapeId>0 then
                        WoodCrusher.mrProcessShape(woodCrusher, foundShapeId, x, y ,z, nx, ny, nz, yx, yy, yz, dt)
                    end

                    --reset x,y,z to default cutNode position
                    x,y,z = getWorldTranslation(woodCrusher.cutNode)

                    --process shapes caught in tractionNodes but not in moveTriggerNodes
                    for id in pairs(woodCrusher.mrTractionNodes) do
                        if id~=foundShapeId then
                            if woodCrusher.moveTriggerNodes[id]==nil then
                                WoodCrusher.mrProcessShape(woodCrusher, id, x, y ,z, nx, ny, nz, yx, yy, yz, dt)
                            end
                        end
                    end

                    for id in pairs(woodCrusher.moveTriggerNodes) do
                        if id~=foundShapeId then
                            WoodCrusher.mrProcessShape(woodCrusher, id, x, y ,z, nx, ny, nz, yx, yy, yz, dt)
                        end
                    end

                end

                if woodCrusher.moveColNodes ~= nil then
                    local rand = -0.005 + 0.01 * math.random() --between -5mm and +5mm
                    for _, moveColNode in pairs(woodCrusher.moveColNodes) do
                        setTranslation(moveColNode.node, moveColNode.transX + rand, moveColNode.transY + rand, moveColNode.transZ + rand)
                    end
                end
            end
         end
    end

    if woodCrusher.crushingTime > 0 then
        woodCrusher.crushingTime = math.max(woodCrusher.crushingTime - dt, 0)
    end

    local isCrushing = woodCrusher.crushingTime > 0

    if self.isClient then
        if isCrushing then
            g_effectManager:setEffectTypeInfo(woodCrusher.crushEffects, FillType.WOODCHIPS)
            g_effectManager:startEffects(woodCrusher.crushEffects)
        else
            g_effectManager:stopEffects(woodCrusher.crushEffects)
        end

        if isTurnedOn and isCrushing then
            if not woodCrusher.isWorkSamplePlaying then
                g_soundManager:playSample(woodCrusher.samples.work)
                woodCrusher.isWorkSamplePlaying = true
            end
        else
            if woodCrusher.isWorkSamplePlaying then
                g_soundManager:stopSample(woodCrusher.samples.work)
                woodCrusher.isWorkSamplePlaying = false
            end
        end

        if isTurnedOn and woodCrusher.mrFeedingActive then
            if not woodCrusher.mrFeedingAnimationRunning then
                g_animationManager:startAnimations(woodCrusher.animationNodes)
                woodCrusher.mrFeedingAnimationRunning = true
            end
        elseif woodCrusher.mrFeedingAnimationRunning then
            g_animationManager:stopAnimations(woodCrusher.animationNodes)
            woodCrusher.mrFeedingAnimationRunning = false
        end

    end

end
WoodCrusher.updateTickWoodCrusher = Utils.overwrittenFunction(WoodCrusher.updateTickWoodCrusher, WoodCrusher.mrUpdateTickWoodCrusher)


---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
--MR function to separate this code from the "updateTick" code => better lisibility
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
WoodCrusher.mrProcessShape = function(woodCrusher, id, x, y ,z, nx, ny, nz, yx, yy, yz, dt)

    if not entityExists(id) then
        woodCrusher.moveTriggerNodes[id] = nil
        WoodCrusher.mrRemoveTractionNode(woodCrusher, id)
    else
        --lenAbove = part we want to crush
        --lenBelow = remaining part
        local lenBelow, lenAbove = getSplitShapePlaneExtents(id, x,y,z, nx,ny,nz) --we want to define a plane => x,y,z = one world point, nx,ny,nz = normal (perpendicular) vector to the plane we want
        if lenAbove ~= nil and lenBelow ~= nil then
            local logVolume = getVolume(id)
            if (lenBelow < 0.25 and logVolume<0.1) or ((lenBelow+lenAbove)<1 and logVolume<0.025) then --if remaining log is too small, crush the whole remaining log
                woodCrusher.crushNodes[id] = id --add the shape to the crushing list instead of crushing it here
            elseif lenAbove > woodCrusher.mrCutLength or (lenAbove>0 and woodCrusher.mrCrushTimers[id]~=nil and woodCrusher.mrCrushTimers[id]>2000) then
                --cut the log in 2
                woodCrusher.shapeBeingCut = id

                --whether or not the split occurs, the "id" shape is not valid after the call to this function
                --problem : when using splitShape, if one part after the cut is too small, it is not created = lost wood
                --we can experience that with the chainsaw too = cutting "cookies" means they disappear after the cut is complete




                --first we testSplitShape to know if we can split or not (avoid case where splitshape try to split the shape in two but do not split anything
                local minY = testSplitShape(id, x,y,z, nx,ny,nz, yx,yy,yz, woodCrusher.cutSizeY, woodCrusher.cutSizeZ, "woodCrusherSplitShapeCallback", woodCrusher)
                if minY~=nil then

                    --1. store the current volume and reset the checkSlipShapes data
                    woodCrusher.mrCheckSplitShapes[id] = {}
                    woodCrusher.mrCheckSplitShapes[id].shapes = {}
                    woodCrusher.mrCheckSplitShapes[id].genuineVolume = logVolume
                    woodCrusher.mrCheckSplitShapes[id].splitTypeIndex = getSplitType(id)

                    --2. split the log in 2 parts
                    splitShape(id, x,y,z, nx,ny,nz, yx,yy,yz, woodCrusher.cutSizeY, woodCrusher.cutSizeZ, "woodCrusherSplitShapeCallback", woodCrusher)
                    g_treePlantManager:removingSplitShape(id)

                    --3. in the update function, before processing the "crushNodes", check if there is a lost volume from a cut
                    woodCrusher.moveTriggerNodes[id] = nil
                    WoodCrusher.mrRemoveTractionNode(woodCrusher, id)

                    -- no shapes after split ? should not be possible
--                         local numSplit = #woodCrusher.mrCheckSplitShapes[id].shapes
--                         if numSplit==0 then --no split really occurs ? (should not occurs since testSplitShape first) or both parts are too small = one shape split in 2 = no more shapes = lost volume
--                             woodCrusher.mrCheckSplitShapes[id] = nil
--                         end
                end

            else
                --MR : there is a log (long enough not to be crushed in one time) near the feeding roller, but the part in the crusher is too small to be split
                --we really want the log to move toward the crusher, especially knowing it is under the feeding roller which should apply a very high moving force on it
                --the force should be downward because of the feeding roller and toward the crusher => 2 forces or one force "diagonal" ?


                --20250628 - too much time near the cutter = allow cutter to cut less than woodCrusher.mrCutLength
                if lenAbove>-0.05 then
                    if woodCrusher.mrCrushTimers[id]==nil then
                        woodCrusher.mrCrushTimers[id] = dt
                    else
                        woodCrusher.mrCrushTimers[id] = woodCrusher.mrCrushTimers[id] + dt
                    end
                else
                    woodCrusher.mrCrushTimers[id] = 0
                end

                --20250625 - we want to keep the same "traction" point until the log is "out of the system" (split, crushed, or not on the woodcrusher anymore)
                --add traction node if not present
                WoodCrusher.mrAddTractionNode(woodCrusher, id, lenAbove, x, y, z, nx, ny, nz, yx, yy, yz)

            end
        end

    end

end


---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
--MR : we want to update power consumption
--we stop feeding system in 3 cases :
--     * rpm too low
--     * output pipe overloaded
--     * wanted crushing power too high
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
WoodCrusher.mrUpdateWoodCrusher = function(self, superFunc, woodCrusher, dt, isTurnedOn)

    if self.isServer then
        if not isTurnedOn then
            --reset power needed
            woodCrusher.mrCrushingPowerWanted = 0
            self.mrWoodCrusherPowerConsumption = 0 --this is the power read by the powerConsumer class
        else
            --deliver the remaining woodChips
            if woodCrusher.mrWaitingFillLevel>0 then --mrWaitingFillLevel in liters
                local volumeToDeliver
                if woodCrusher.mrWaitingFillLevel<5 then
                    volumeToDeliver = woodCrusher.mrWaitingFillLevel
                    woodCrusher.mrWaitingFillLevel = 0
                else
                    volumeToDeliver = woodCrusher.mrWaitingFillLevel*dt/1000 --100% per second
                    woodCrusher.mrWaitingFillLevel = woodCrusher.mrWaitingFillLevel - volumeToDeliver
                end
                self:addFillUnitFillLevel(self:getOwnerFarmId(), woodCrusher.fillUnitIndex, volumeToDeliver, FillType.WOODCHIPS, ToolType.UNDEFINED)
            end

            --before processing the "crushNodes", check if there is a lost volume from the previous cut
            for key, checkSlipShape in pairs(woodCrusher.mrCheckSplitShapes) do
                if checkSlipShape.genuineVolume > 0.001 then --volume is in m3
                    local shapesVolume = 0
                    for index, shape in pairs(checkSlipShape.shapes) do
                        if entityExists(shape) then
                            shapesVolume = shapesVolume + getVolume(shape)
                        end
                    end
                    local lostVolume = checkSlipShape.genuineVolume - shapesVolume
                    if lostVolume>0 then
                        local splitType = g_splitShapeManager:getSplitTypeByIndex(checkSlipShape.splitTypeIndex)
                        WoodCrusher.mrProcessVolume(self, woodCrusher, splitType, lostVolume)
                    end

                    --reset mrCheckSplitShapes data
                    woodCrusher.mrCheckSplitShapes[key] = nil
                end
            end

            --if there are woodShapes to crush = crush them
            for node in pairs(woodCrusher.crushNodes) do
                WoodCrusher.crushSplitShape(self, woodCrusher, node)
                woodCrusher.crushNodes[node] = nil
                woodCrusher.moveTriggerNodes[node] = nil
            end


            --check if we stop feeding system or not
            --MR = we don't want to move the feeding roller/pickup when the pto speed is too slow
            woodCrusher.mrFeedingActive = true
            if self.mrPtoCurrentRpmRatio~=nil then
                if self.mrPtoCurrentRpmRatio<0.78 then
                    woodCrusher.mrFeedingActive = false
                else
                    woodCrusher.mrFeedingActive = true
                end
            end

            local maxCrushingPowerWanted = woodCrusher.mrMaxCrushingPowerPossible
            if self.getMotor~=nil then
                local rootMotor = self:getMotor()
                maxCrushingPowerWanted = math.min(maxCrushingPowerWanted, rootMotor.peakMotorPower)
            else
                local rootAttacherVehicle = self:getRootVehicle()
                if rootAttacherVehicle ~= nil and rootAttacherVehicle.getMotor ~= nil then
                    local rootMotor = rootAttacherVehicle:getMotor()
                    maxCrushingPowerWanted = math.min(maxCrushingPowerWanted, rootMotor.peakMotorPower)
                end
            end

            --update power consumption
            woodCrusher.mrCrushingPowerWanted = math.max(woodCrusher.mrIdlePower, woodCrusher.mrCrushingPowerWanted - maxCrushingPowerWanted*dt/1000)
            self.mrWoodCrusherPowerConsumption = (1-0.005*dt)*self.mrWoodCrusherPowerConsumption + (0.005*dt)*woodCrusher.mrCrushingPowerWanted

            if woodCrusher.mrCrushingPowerWanted>maxCrushingPowerWanted then
                woodCrusher.mrFeedingActive = false
            end

            --MR : check fillLevel of the temp tank
            local currentfillLevelRatio = self:getFillUnitFillLevelPercentage(self.spec_woodCrusher.fillUnitIndex)
            if currentfillLevelRatio>0.3 then
                --crushing process is too fast for the machine = pause the feeding system
                woodCrusher.mrWaitingForFillLevel = true
            elseif currentfillLevelRatio<0.1 then
                --hysteresis : unpause the feeding system when the machine is no more overloaded
                woodCrusher.mrWaitingForFillLevel = false
            end

            if woodCrusher.mrWaitingForFillLevel then
                woodCrusher.mrFeedingActive = false
            end

            --20260314 - check if there is a wood shape to add to the traction node (after a split)
            for shapeId in pairs(woodCrusher.mrPendingTractionNodes) do
                WoodCrusher.mrAddTractionNode(woodCrusher, shapeId)
            end

            --MR : we don't want to apply forces or move the feeding roller when it is actually stopped
            if woodCrusher.mrFeedingActive then

                --apply traction forces on "hooked" shapes
                --local maxAvailableForce = woodCrusher.mrMaxTractionForce

                for shapeId, tractionNode in pairs(woodCrusher.mrTractionNodes) do
                    if entityExists(shapeId) then
                        --reduce translationLimit
                        if tractionNode.jointId~=nil and (tractionNode.jointLimitZ>0 or tractionNode.jointLimitY>0.1) then

                            local translationChange = woodCrusher.mrMoveVelocityZ*woodCrusher.mrFeedingLastVelocityFactor*dt/1000
                            tractionNode.jointLimitX = math.max(0, tractionNode.jointLimitX - translationChange)
                            tractionNode.jointLimitY = math.max(0, tractionNode.jointLimitY - translationChange)
                            tractionNode.jointLimitZ = math.max(0, tractionNode.jointLimitZ - translationChange)

                            setJointTranslationLimit(tractionNode.jointId, 0, true, -tractionNode.jointLimitX, tractionNode.jointLimitX)
                            setJointTranslationLimit(tractionNode.jointId, 1, true, 0, tractionNode.jointLimitY)
                            setJointTranslationLimit(tractionNode.jointId, 2, true, 0, tractionNode.jointLimitZ)

                        end
                    else
                        WoodCrusher.mrRemoveTractionNode(woodCrusher, shapeId)
                    end
                end

                local maxTreeSizeY = 0
                for id in pairs(woodCrusher.moveTriggerNodes) do
                    if not entityExists(id) then
                        woodCrusher.moveTriggerNodes[id] = nil
                    else

                        if woodCrusher.shapeSizeDetectionNode ~= nil then
                            local x, y, z = getWorldTranslation(woodCrusher.shapeSizeDetectionNode)
                            local nx, ny, nz = localDirectionToWorld(woodCrusher.shapeSizeDetectionNode, 1,0,0)
                            local yx, yy, yz = localDirectionToWorld(woodCrusher.shapeSizeDetectionNode, 0,1,0)

                            local minY, maxY, _, _ = testSplitShape(id, x, y, z, nx, ny, nz, yx, yy, yz, woodCrusher.cutSizeY, woodCrusher.cutSizeZ)

                            if minY==nil then
                                --MR : also check after detectionNode => sometimes, the log is not "flat" but vertical or diagonaly positioned, and already under the feeding roller
                                x, y, z = localToWorld(woodCrusher.shapeSizeDetectionNode, 0.25, 0, 0)
                                minY, maxY, _, _ = testSplitShape(id, x, y, z, nx, ny, nz, yx, yy, yz, woodCrusher.cutSizeY, woodCrusher.cutSizeZ)
                            end

                            if minY==nil then
                                --MR : also check before detectionNode => sometimes, the log is not "flat" but vertical or diagonaly positioned, and hitting the feeding roller collision box
                                x, y, z = localToWorld(woodCrusher.shapeSizeDetectionNode, -0.25, 0, 0)
                                minY, maxY, _, _ = testSplitShape(id, x, y, z, nx, ny, nz, yx, yy, yz, woodCrusher.cutSizeY, woodCrusher.cutSizeZ)
                            end

                            if minY ~= nil then
                                if woodCrusher.mainDrumRefNode ~= nil then
                                    maxTreeSizeY = math.max(maxTreeSizeY, maxY+0.1) --0.1 to keep some error margin
                                end
                            end
                        end

                    end
                end
                if woodCrusher.mainDrumRefNode ~= nil then
                    local x, y, z = getTranslation(woodCrusher.mainDrumRefNode)
                    local ty = math.min(maxTreeSizeY, woodCrusher.mainDrumRefNodeMaxY)
                    if ty > y then
                        y = math.min(y + 0.0003*dt, ty)
                    else
                        y = math.max(y - 0.0003*dt, ty)
                    end

                    setTranslation(woodCrusher.mainDrumRefNode, x, y, z)
                end

            end --end MR mrFeedingActive

            if next(woodCrusher.moveTriggerNodes) ~= nil or woodCrusher.crushingTime > 0 then
                self:raiseActive()
            end
        end
    end
end
WoodCrusher.updateWoodCrusher = Utils.overwrittenFunction(WoodCrusher.updateWoodCrusher, WoodCrusher.mrUpdateWoodCrusher)



---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
--MR : we want to know if split shape get 2 new shapes, or split nothing, or get only one new shape and nothing
-- if the split worked, this function is called 2 times
-- isBelow = part after the cut (remaining part)
-- isAbove = part before the cut (what we want to crush)
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
WoodCrusher.mrWoodCrusherSplitShapeCallback = function(self, superFunc, shape, isBelow, isAbove, minY, maxY, minZ, maxZ)

    --self = woodCrusher object in this callback

    --the new shape is not ready yet, we can't call the getVolume function on it
    if shape~=nil then
        table.insert(self.mrCheckSplitShapes[self.shapeBeingCut].shapes, shape)
    end

    if isAbove then
        self.crushNodes[shape] = shape
        g_treePlantManager:addingSplitShape(shape, self.shapeBeingCut)
    end

    --remaining part = we want to add it to the tractionNodes if possible
    if isBelow then
        if entityExists(shape) then
            self.mrPendingTractionNodes[shape] = true
        end
    end

end
WoodCrusher.woodCrusherSplitShapeCallback = Utils.overwrittenFunction(WoodCrusher.woodCrusherSplitShapeCallback, WoodCrusher.mrWoodCrusherSplitShapeCallback)

---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
--MR : we want to be able to stop feeding animation even if the crusher is working
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
WoodCrusher.onReadUpdateStream = function(self, streamId, timestamp, connection)
    if connection:getIsServer() then
        local spec = self.spec_woodCrusher
        if streamReadBool(streamId) then
            spec.crushingTime = 1000
        else
            spec.crushingTime = 0
        end
        spec.mrFeedingActive = streamReadBool(streamId)
    end
end


WoodCrusher.onWriteUpdateStream = function(self, streamId, connection, dirtyMask)
    if not connection:getIsServer() then
        local spec = self.spec_woodCrusher
        streamWriteBool(streamId, spec.crushingTime > 0)
        streamWriteBool(streamId, spec.mrFeedingActive)
    end
end


---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
--MR : use joint instead of applying force to move logs when they are dragged by the crusher roller
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
WoodCrusher.mrCreateTractionJoint = function(woodCrusher, shapeId, distance)

    -- Create the joint between the crusher and the log
    local joint = JointConstructor.new()
    joint:setActors(woodCrusher.vehicle.components[1].node, shapeId)

    local zOffset = 0.3+woodCrusher.mrCutLength

    local tx, ty, tz = localToWorld(woodCrusher.cutNode, zOffset, woodCrusher.mrCutTargetY, 0.5*woodCrusher.mrCutWidth) --world point we want to reach to be crushed = traction target point
    local x,y,z = woodCrusher.mrTractionNodes[shapeId].forcePointX, woodCrusher.mrTractionNodes[shapeId].forcePointY, woodCrusher.mrTractionNodes[shapeId].forcePointZ --this is the force point in the shape coordinate system
    local wx,wy,wz = localToWorld(shapeId, x, y, z) --this is the world point where to apply the force to the log

    joint:setJointWorldPositions(tx, ty, tz, wx, wy, wz)

    -- Set the axes and normals.
    local targetLeftX, targetLeftY, targetLeftZ = localDirectionToWorld(woodCrusher.cutNode, 0, 0, 1)
    joint:setJointWorldAxes(targetLeftX, targetLeftY, targetLeftZ, targetLeftX, targetLeftY, targetLeftZ)

    local targetUpX, targetUpY, targetUpZ = localDirectionToWorld(woodCrusher.cutNode, 0, 1, 0)
    joint:setJointWorldNormals(targetUpX, targetUpY, targetUpZ, targetUpX, targetUpY, targetUpZ)

    local dx,dy,dz = localToLocal(shapeId, woodCrusher.cutNode, x,y,z)
    dx = zOffset - dx
    dy = dy - woodCrusher.mrCutTargetY
    dz = math.abs(0.5*woodCrusher.mrCutWidth - dz)

    local jointLimitX = 0.2+math.abs(dz)
    local jointLimitY = 0.1+math.max(0, dy)
    local jointLimitZ = math.max(0, dx)


    -- Set the limits.
    joint:setTranslationLimit(0, true, -jointLimitX, jointLimitX)
    joint:setTranslationLimit(1, true, 0, jointLimitY)
    joint:setTranslationLimit(2, true, 0, jointLimitZ)

    joint:setRotationLimit(0, -math.huge, math.huge)
    joint:setRotationLimit(1, -math.huge, math.huge)
    joint:setRotationLimit(2, -math.huge, math.huge)

    joint:setEnableCollision(true)

    joint:setRotationLimitSpring(1,1,1,1,1,1)
    --joint:setRotationLimitForceLimit(mass, mass, mass)


     local mass =  woodCrusher.mrTractionNodes[shapeId].mass
     local spring = math.max(10, 500*mass)
     local damping = math.max(1, 10*mass)
     local maxForce = math.min(woodCrusher.mrMaxTractionForce, 25*mass)

     --more spring/force for the z axis
     joint:setTranslationLimitSpring(0.1*spring, damping, spring, damping, spring, damping)
     joint:setTranslationLimitForceLimit(0.5*maxForce, 0.5*maxForce, maxForce)

     --joint:setBreakable(forceLimit, forceLimit) --breakForce, breakTorque


    --joint:setLinearDrive(axis, bool drivePosition, bool driveVelocity, axisSpring, axisDamping, maxForce, position, velocity)

     --joint:setLinearDrive(0, true, true, 1000, 10, math.min(100*mass, woodCrusher.mrMaxTractionForce), 0, 0.5)
--      joint:setLinearDrive(0, true, true, 1000, 10, 20*mass, 0, 0.5)
--      joint:setLinearDrive(1, true, true, 1000, 10, 20*mass, 0, 0.5)
--      joint:setLinearDrive(2, true, true, 1000, 10, 20*mass, 0, 0.5)


    woodCrusher.mrTractionNodes[shapeId].jointId = joint:finalize()
    woodCrusher.mrTractionNodes[shapeId].jointLimitX = jointLimitX
    woodCrusher.mrTractionNodes[shapeId].jointLimitY = jointLimitY
    woodCrusher.mrTractionNodes[shapeId].jointLimitZ = jointLimitZ


end

---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
--MR : remove the joint between the crusher and the logs when the feeding is not active
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
WoodCrusher.mrRemoveTractionJoints = function(woodCrusher)
    for shapeId in pairs(woodCrusher.mrTractionNodes) do
        if woodCrusher.mrTractionNodes[shapeId].jointId~=nil then
            if entityExists(shapeId) then
                removeJoint(woodCrusher.mrTractionNodes[shapeId].jointId)
            end
            woodCrusher.mrTractionNodes[shapeId].jointId=nil
        end
    end
end


WoodCrusher.mrRemoveTractionNode = function(woodCrusher, shapeId)
    if woodCrusher.mrTractionNodes[shapeId]~=nil then
        if entityExists(shapeId) then
            if woodCrusher.mrTractionNodes[shapeId].jointId~=nil then
                removeJoint(woodCrusher.mrTractionNodes[shapeId].jointId)
            end
        end
        woodCrusher.mrTractionNodes[shapeId] = nil
    end
end



WoodCrusher.mrAddTractionNode = function(woodCrusher, shapeId, lenAbove, x, y, z, nx, ny, nz, yx, yy, yz)

    if woodCrusher.mrTractionNodes[shapeId]==nil or woodCrusher.mrTractionNodes[shapeId].jointId==nil then
        --we need lenAbove
        if lenAbove==nil then
            if entityExists(shapeId) then
                x,y,z = getWorldTranslation(woodCrusher.cutNode)
                nx,ny,nz = localDirectionToWorld(woodCrusher.cutNode, 1,0,0)
                _, lenAbove = getSplitShapePlaneExtents(shapeId, x,y,z, nx,ny,nz)
            end
        end
    end

    if lenAbove~=nil then
        if woodCrusher.mrTractionNodes[shapeId]==nil then
            local mass = getMass(shapeId)
            if mass~=nil then
                --1. we have to define where to apply the force to the log
                --lenAbove = part we want to crush

                yx,yy,yz = localDirectionToWorld(woodCrusher.cutNode, 0,1,0)

                local lx,ly,lz
                local offsetX = 0
                if lenAbove>0 then
                    lx,ly,lz = x, y, z
                else
                    offsetX = lenAbove-0.02
                    lx,ly,lz = localToWorld(woodCrusher.cutNode, offsetX, 0, 0) -- the log has not reached the cutnode "cut plane" => we try to catch the log about 1 centimeter at the nearest end
                end

                local minY,_,minZ,maxZ = testSplitShape(shapeId, lx,ly,lz, nx,ny,nz, yx,yy,yz, woodCrusher.cutSizeY, woodCrusher.cutSizeZ) --results are local pos : minY and maxY = pos compared to ly // minZ and maxZ = pos compared to lz
                if minY ~= nil then
                    --add the "shape" to the tractionForce list
                    woodCrusher.mrTractionNodes[shapeId] = {}
                    woodCrusher.mrTractionNodes[shapeId].forcePointX, woodCrusher.mrTractionNodes[shapeId].forcePointY, woodCrusher.mrTractionNodes[shapeId].forcePointZ = localToLocal(woodCrusher.cutNode, shapeId, offsetX, minY-0.02, 0.5*(minZ+maxZ)) --position in the shape coordinate system
                    woodCrusher.mrTractionNodes[shapeId].mass = mass
                    WoodCrusher.mrCreateTractionJoint(woodCrusher, shapeId, -lenAbove)
                end
            end
        elseif woodCrusher.mrTractionNodes[shapeId].jointId==nil then
            WoodCrusher.mrCreateTractionJoint(woodCrusher, shapeId, -lenAbove)
        end
    end

    if woodCrusher.mrTractionNodes[shapeId]~=nil then
        woodCrusher.mrPendingTractionNodes[shapeId] = nil
    end

end



function WoodCrusher.mrTurnOnWoodCrusher(self, superFunc, woodCrusher)
    superFunc(self, woodCrusher)
    woodCrusher.mrFeedingAnimationRunning = true
end
WoodCrusher.turnOnWoodCrusher = Utils.overwrittenFunction(WoodCrusher.turnOnWoodCrusher, WoodCrusher.mrTurnOnWoodCrusher)




