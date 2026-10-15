-- Standalone permission regression for multiplayer recovery (Lua 5.1).
-- Fake GIANTS APIs reproduce remote client and trusted server events.
MR_RecoverVehicleEvent = nil
Class = function(class, parent) return {__index=class} end
Event = {new=function(meta) return setmetatable({},meta) end}
InitEventClass = function() end
local vehicle = {farmId=2, getAttachedImplements=function()
    return {{object={}}}
end}
NetworkUtil = {readNodeObject=function() return vehicle end}
dofile("MoreRealistic/scripts/MR_RecoverVehicleEvent.lua")
local function clear()
    vehicle.mrRecoveryModeActive=nil
    vehicle.mrRecoveryModeTimer=nil
end
local currentPlayer
local hasAccess = false
g_currentMission = {
    playerSystem = {getPlayerByConnection=function(_,connection) return currentPlayer end},
    accessHandler = {canFarmAccess=function(_,farmId,object)
        return hasAccess and object==vehicle and farmId==1
    end},
}
local client={getIsServer=function() return false end}
local server={getIsServer=function() return true end}
local function receive(conn)
    local event={}
    MR_RecoverVehicleEvent.readStream(event,17,conn)
    return vehicle.mrRecoveryModeActive==true
end
clear()
currentPlayer={farmId=1};hasAccess=false
assert(not receive(client),"Unauthorized client's recovery must be denied")
clear()
currentPlayer={farmId=1};hasAccess=true
assert(receive(client),"Client explicitly granted vehicle access should recover")
clear()
currentPlayer=nil;hasAccess=true
assert(not receive(client),"Unknown client must be denied")
clear()
currentPlayer={farmId=1};hasAccess=false
assert(receive(server),"Trusted server event must apply")
clear()
NetworkUtil.readNodeObject=function() return nil end
assert(pcall(function() MR_RecoverVehicleEvent.readStream({},17,client) end),"Nil vehicle should be safe")
print("PASS: multiplayer vehicle recovery access enforced")
