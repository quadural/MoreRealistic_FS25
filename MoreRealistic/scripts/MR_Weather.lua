-- Temperature/sun model, with server-owned persistent dampness.
-- No forecast, rainfall, time scale or cloud settings are changed here.
MRweather = {INTERVAL_MS=2000}
local M = MRweather
local function finite(v) return type(v)=="number" and v==v and math.abs(v)<math.huge end
local function unit(v) return finite(v) and math.max(0,math.min(1,v)) or 0 end
local function currentWeather()
    local m=g_currentMission
    return m and m.environment and m.environment.weather
end
local function state(w)
    if w.MRwetness==nil then
        w.MRwetness={damp=0,minimum=0,wetness=0,elapsed=0,drying=0,ready=false}
    end
    return w.MRwetness
end
function M.nightDamp(t)
    if t>=30 then return 0
    elseif t>25 then return 0.06-0.012*(t-25)
    elseif t>20 then return 0.115-0.011*(t-20)
    elseif t>15 then return 0.165-0.01*(t-15)
    elseif t>10 then return 0.205-0.008*(t-10)
    elseif t>5 then return 0.235-0.006*(t-5)
    elseif t>0 then return 0.25-0.003*t
    end
    return 0.25
end
function M.telemetry(s)
    Weather.mrCurrentWetness=s.wetness
    Weather.mrCurrentWetnessMin=s.minimum
    Weather.mrCurrentWetnessDamp=s.damp
end
local nativeGroundWetness=Weather.getGroundWetness
function M.refresh(w)
    local s=state(w)
    local m=g_currentMission
    if g_server==nil or not m or not m.environment then return false end
    local maxTemp=w.temperatureUpdater and w.temperatureUpdater.currentMax
    local temperature=w:getCurrentTemperature()
    if not finite(maxTemp) or not finite(temperature) then return false end
    local minimum=math.max(0,math.min(0.25,(30-maxTemp)/80))
    if m.environment.isSunOn then
        s.damp=math.max(0,s.damp-s.drying)
    else
        s.damp=M.nightDamp(temperature)
    end
    s.drying=0
    s.minimum=minimum
    s.wetness=math.max(minimum,s.damp,unit(nativeGroundWetness(w)))
    s.ready=true
    M.telemetry(s)
    return true
end
function M.apply(w,wetness,minimum,damp)
    if not finite(wetness) or not finite(minimum) or not finite(damp)
        or wetness<0 or wetness>1 or minimum<0 or minimum>0.25
        or damp<0 or damp>0.25 then return end
    local s=state(w)
    s.wetness,s.minimum,s.damp=wetness,minimum,damp
    s.ready=true
    M.telemetry(s)
end
MRwetnessEvent={}
local eventMt=Class(MRwetnessEvent,Event)
InitEventClass(MRwetnessEvent,"MRwetnessEvent")
function MRwetnessEvent.emptyNew() return Event.new(eventMt) end
function MRwetnessEvent.new(s)
    local e=MRwetnessEvent.emptyNew()
    e.wetness,e.minimum,e.damp=s.wetness,s.minimum,s.damp
    return e
end
function MRwetnessEvent:writeStream(streamId,connection)
    streamWriteFloat32(streamId,self.wetness)
    streamWriteFloat32(streamId,self.minimum)
    streamWriteFloat32(streamId,self.damp)
end
function MRwetnessEvent:readStream(streamId,connection)
    self.wetness=streamReadFloat32(streamId)
    self.minimum=streamReadFloat32(streamId)
    self.damp=streamReadFloat32(streamId)
    self:run(connection)
end
function MRwetnessEvent:run(connection)
    -- Clients cannot alter the server's moisture state.
    if g_server~=nil or not connection or not connection:getIsServer() then return end
    local w=currentWeather()
    if w then M.apply(w,self.wetness,self.minimum,self.damp)
    else M.pending={self.wetness,self.minimum,self.damp} end
end
function M.initialize(w)
    if not w then return end
    if g_server~=nil then M.refresh(w)
    elseif M.pending then
        M.apply(w,unpack(M.pending));M.pending=nil
    end
end
Weather.getGroundWetness=Utils.overwrittenFunction(Weather.getGroundWetness,function(w,superFunc,...)
    local s=state(w)
    if not s.ready and g_server~=nil then M.refresh(w) end
    -- Until the initial server snapshot arrives, retain native wetness.
    if s.ready then return s.wetness end
    return superFunc(w,...)
end)
Weather.update=Utils.appendedFunction(Weather.update,function(w,dt)
    if g_server==nil or not finite(dt) or dt<0 then return end
    local m=g_currentMission
    if not m or not m.environment then return end
    local s=state(w)
    local temperature=w:getCurrentTemperature()
    local scale=m:getEffectiveTimeScale()
    if finite(temperature) and finite(scale) and scale>=0 then
        if m.environment.isSunOn then
            -- Integrate each frame: speed changes and pauses do not retroactively
            -- apply the latest time scale to the entire two-second interval.
            local fx=math.max(0.1,temperature/25)^0.7
            s.drying=s.drying+0.1*fx*scale*dt/3600000
        else
            -- Keep the authoritative night state current through sunrise.
            s.damp=M.nightDamp(temperature)
            s.drying=0
        end
    end
    s.elapsed=s.elapsed+dt
    if not s.ready or s.elapsed>=M.INTERVAL_MS then
        if M.refresh(w) then
            s.elapsed=0
            if s.sentWetness~=s.wetness or s.sentMinimum~=s.minimum or s.sentDamp~=s.damp then
                g_server:broadcastEvent(MRwetnessEvent.new(s),false)
                s.sentWetness,s.sentMinimum,s.sentDamp=s.wetness,s.minimum,s.damp
            end
        end
    end
end)
Weather.sendInitialState=Utils.appendedFunction(Weather.sendInitialState,function(w,connection)
    if g_server==nil or not connection then return end
    M.initialize(w)
    local s=state(w)
    if s.ready then connection:sendEvent(MRwetnessEvent.new(s)) end
end)
-- Use the existing weather XML handle; never create/save/delete the game file.
-- Support native handles and XMLFile objects without owning their lifecycle.
local function readFloat(handle,key)
    if type(handle)=="table" and handle.getFloat then return handle:getFloat(key) end
    return getXMLFloat(handle,key)
end
local function writeFloat(handle,key,value)
    if type(handle)=="table" and handle.setFloat then handle:setFloat(key,value)
    else setXMLFloat(handle,key,value) end
end
Weather.loadFromXMLFile=Utils.appendedFunction(Weather.loadFromXMLFile,function(w,handle,key)
    local s=state(w)
    local damp=readFloat(handle,key.."#MRdampness")
    s.damp=math.min(0.25,unit(damp))
    s.ready,s.elapsed,s.drying=false,0,0
end)
Weather.saveToXMLFile=Utils.appendedFunction(Weather.saveToXMLFile,function(w,handle,key)
    if g_server==nil then return end
    local s=state(w)
    -- Include drying accumulated since the last published snapshot.
    writeFloat(handle,key.."#MRdampness",math.max(0,s.damp-s.drying))
end)
