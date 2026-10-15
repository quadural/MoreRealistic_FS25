-- Self-contained Lua 5.1 test of the real WoodCrusher delivery block.
-- Dynamically extract the delivery block from source; do not reimplement it.
local f=assert(io.open("MoreRealistic/scripts/MR_WoodCrusher.lua","rb"))
local text=f:read("*a");f:close()
local start=assert(text:find("WoodCrusher.mrUpdateWoodCrusher = function",1,true))
local stop=assert(text:find("            --before processing the \"crushNodes\"",start,true))
local chunk=text:sub(start,stop-1).. "        end\n    end\nend\n"
WoodCrusher={}
FillType={WOODCHIPS=1}
ToolType={UNDEFINED=0}
assert(loadstring(chunk))()
local function simulate(waiting,capacity,dt)
    local tank=capacity
    local crusher={mrWaitingFillLevel=waiting}
    local obj={
        isServer=true,
        getOwnerFarmId=function() return 1 end,
        addFillUnitFillLevel=function(_,_,_,request)
            local accepted=math.min(request,capacity-tank)
            tank=tank+accepted
            return accepted
        end,
    }
    crusher.fillUnitIndex=1
    WoodCrusher.mrUpdateWoodCrusher(obj,function() end,crusher,dt,true)
    return crusher.mrWaitingFillLevel,tank
end
local remain,stored=simulate(50,100,100)
assert(math.abs(remain-50)<1e-6,"Full output consumed buffered woodchips")
assert(stored==100,"Full output must remain full")
local remain2,stored2=simulate(4,100,100)
assert(remain2==4,"Tiny buffered amount lost when tank full")
local tank=95
local crusher={mrWaitingFillLevel=50,fillUnitIndex=1}
local obj={isServer=true,getOwnerFarmId=function()return 1 end,addFillUnitFillLevel=function(_,_,_,req) local n=math.min(req,100-tank);tank=tank+n;return n end}
WoodCrusher.mrUpdateWoodCrusher(obj,function()end,crusher,1000,true)
assert(tank==100,"Partial fill tank wasn't filled")
assert(math.abs(crusher.mrWaitingFillLevel-45)<1e-6,"Partial fill lost excess buffered material")
print("PASS: woodchip buffer preserves material when receiving fill unit is full or nearly full")
