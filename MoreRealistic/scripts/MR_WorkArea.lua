---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--
--MR : we want to fix the problem with cultivators and wheels
--At still, when the cultivator is lowered and not moving, the wheels add "tracks" and "ruts" to the ground and the cultivator "processCultivatorArea" function remove that
--This a loop = the wheels are sinking/raising (bouncing effect) continously
--
--Notorious example = Pottinger Terria 6040 : when detaching the tool while working a field => dancing effect as soon as we approach the implement
--
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
WorkArea.mrGetIsWorkAreaActive = function(self, superFunc, workArea)

    local result = superFunc(self, workArea)

    if result and self.isServer and self.mrIsMrVehicle and workArea.requiresGroundContact and not self.mrImplementProcessAreaWhileNotMoving then --only for MR vehicle to avoid unmanaged cases
        if self.components[1].isDynamic then
            --check ground speed of the implement
            --local vx, vy, vz = getLocalLinearVelocity(self.components[1].node)
            local vx, _, vz = getLinearVelocity(self.components[1].node)
            if vx~=nil and vz~=nil then --protection against nil value
                local spd2d = MathUtil.vector2Length(vx, vz)
                if spd2d<0.1 then --0.36kph
                    result = false
                end
            end
        end
    end

    return result

end
WorkArea.getIsWorkAreaActive = Utils.overwrittenFunction(WorkArea.getIsWorkAreaActive, WorkArea.mrGetIsWorkAreaActive)


-- -- ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- -- --
-- -- --MR : add new listener for "onSetLowered"
-- -- --
-- -- ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- WorkArea.mrRegisterEventListeners = function(vehicleType, superFunc)

--     superFunc(vehicleType)
--     SpecializationUtil.registerEventListener(vehicleType, "onSetLowered", WorkArea)

-- end
--  WorkArea.registerEventListeners = Utils.overwrittenFunction(WorkArea.registerEventListeners, WorkArea.mrRegisterEventListeners)



-- -- ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- -- --
-- -- --MR : we don't want the implement wheels to leave "ruts" in working position => most of the time, the "workArea" processing function is just deleting that
-- -- --unwanted behavior = implement's wheels included in the work area are leaving heavy "ruts". At work, this is not perceptible because the processing area function is deleting it all the time
-- -- --but when we stop working, the implement sinks into the ground. And then, when we get back to work, the processing area function delete the "ruts" and the wheels bump a big time to get back to the "flat" surface
-- -- --for most implements, IRL, the wheels are not bearing the full implement weight in working position => the "ruts" would be small
-- -- --
-- -- ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- WorkArea.mrOnSetLowered = function(self, lowered)

--     if self.isServer then
--         local spec = self.spec_wheels
--         if spec==nil or #spec.wheels==0 then
--             SpecializationUtil.removeEventListener(self, "onSetLowered", WorkArea)
--         else
--             for _, wheel in ipairs(spec.wheels) do
--                 wheel.physics:setDisplacementAllowed(not lowered)
--                 --wheel.physics:setDisplacementCollisionEnabled(not lowered)
--             end
--         end
--     end

-- end