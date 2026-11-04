-- Shared active-play clock: prepare by day, watch the colony survive the night.
return function(H)
local C=core
local storage=brickcraft.storage
H.clock={elapsed=tonumber(storage:get_string("habitat_clock")) or 0}
local sleeping={}
local lighting={}
local save_wait,sky_wait=0,0

function H.cycle_config(w)
  local v=H.variant_of(w)
  if not (v and v.cycle) then return nil end
  local cfg={enabled=true,day=v.cycle.day,night=v.cycle.night,lock_players=true,predator_multiplier=3,disaster="random"}
  for k,value in pairs(v.cycle) do cfg[k]=value end
  for k,value in pairs(H.state(w).cycle_settings or {}) do cfg[k]=value end
  return cfg
end
function H.cycle_status(w)
  local cfg=H.cycle_config(w)
  if not cfg then return nil end
  if not cfg.enabled then return {enabled=false,night=false,remaining=0,cycle=1,timeofday=.48} end
  local day,night=cfg.day,cfg.night
  local total=day+night
  local elapsed=math.max(0,H.clock.elapsed-(H.state(w).cycle_start or 0))
  local t=elapsed%total
  local dark=t>=day
  return {enabled=true,night=dark,remaining=math.ceil((dark and total or day)-t),
    cycle=math.floor(elapsed/total)+1,
    timeofday=dark and (.75+.5*(t-day)/night)%1 or .25+.5*t/day}
end
function H.actions_blocked(p)
  if not (p and p.is_player and p:is_player()) then return false end
  local w=H.world_at(p:get_pos())
  local phase=w and H.cycle_status(w)
  return phase and phase.night and H.cycle_config(w).lock_players or false
end
function H.night_multiplier(w)
  local phase=H.cycle_status(w)
  return phase and phase.night and H.cycle_config(w).predator_multiplier or 1
end
function H.cycle_line(w)
  local s=H.cycle_status(w)
  local cfg=H.cycle_config(w)
  if not cfg.enabled then return "Day/night disabled · Always daytime" end
  local danger=cfg.disaster=="none" and "no disaster" or cfg.disaster=="random" and "one random disaster" or "one "..H.disasters[cfg.disaster].label:lower()
  return s.night and ("NIGHT · "..s.remaining.."s until dawn · "..(cfg.lock_players and "Actions locked" or "Players can act")..
    " · "..cfg.predator_multiplier.."x predators + "..danger)
    or ("DAY · "..s.remaining.."s until night · Build, domesticate and prepare your defenses")
end

local function restore_interact(name)
  local key="habitat_sleep_"..name
  if storage:get_string(key)=="1" then
    local privs=C.get_player_privs(name); privs.interact=true
    C.set_player_privs(name,privs)
  end
  storage:set_string(key,"")
end
local function wake(p)
  local name=p:get_player_name()
  local s=sleeping[name]
  if s then
    p:set_physics_override(s.physics)
    sleeping[name]=nil
  end
  restore_interact(name)
end
function H.sleep_step(p)
  local name=p:get_player_name()
  if not H.actions_blocked(p) then
    if sleeping[name] then wake(p) end
    return
  end
  local s=sleeping[name]
  if not s then
    s={pos=vector.copy(p:get_pos()),physics=p:get_physics_override()}
    sleeping[name]=s
    local privs=C.get_player_privs(name)
    -- Remember the one privilege we change so a crash cannot strand a player.
    storage:set_string("habitat_sleep_"..name,privs.interact and "1" or "0")
    privs.interact=nil; C.set_player_privs(name,privs)
    p:set_physics_override({speed=0,jump=0,gravity=0})
    C.close_formspec(name,"")
    C.chat_send_player(name,"Night: rest and watch your defenses. You can act again at dawn.")
  end
  p:set_pos(s.pos)
  p:add_velocity(vector.multiply(p:get_velocity(),-1))
end

function H.night_events(w)
  local phase=H.cycle_status(w)
  if not phase then return end
  local st,v=H.state(w),H.variant_of(w)
  local cfg=H.cycle_config(w)
  if not phase.night then
    if st.cycle_phase=="night" then
      local active=H.active[w.id]
      if active and active.night_cycle then H.stop_disaster(w) end
      H.tell(w,"Dawn! You can move, build and care for your bunnies again.","#ffe27a")
      H.reset_wave(w)
    end
    st.cycle_phase="day"
    return
  end
  if not st.spawned then return end
  if not st.night_event or st.night_event.cycle~=phase.cycle then
    local choices=v.disasters or H.disaster_list
    local disaster
    if cfg.disaster=="random" then
      if #choices>0 then disaster=choices[math.random(#choices)] end
    elseif cfg.disaster~="none" then disaster=cfg.disaster end
    st.night_event={cycle=phase.cycle,disaster=disaster}
    st.cycle_phase="night"
    H.tell(w,"Night falls! "..H.cycle_line(w),"#c8b6ff")
    if cfg.predator_multiplier>0 and st.wild~=false and v.predators and #v.predators>0 then
      H.spawn_predator(w,v.predators[math.random(#v.predators)])
    end
    H.reset_wave(w)
    H.save(w)
  end
  local event=st.night_event
  -- A disaster already underway finishes first; retry this one until it can start.
  if event.disaster and not event.started and not H.active[w.id] then
    if H.start_disaster(w,event.disaster) then
      event.started=true
      H.active[w.id].night_cycle=phase.cycle
      -- Fit the warning and the whole disaster into the remaining night.
      local ctx=H.active[w.id]
      ctx.def=table.copy(ctx.def)
      ctx.delay=math.min(ctx.delay,math.max(0,phase.remaining-1))
      ctx.def.duration=math.min(ctx.def.duration,math.max(1,phase.remaining-ctx.delay))
      if ctx.def.peak then ctx.def.peak=math.min(ctx.def.peak,ctx.def.duration/2) end
      H.save(w)
    end
  end
end

function H.cycle_step(dtime)
  -- Other habitat checks keep their deterministic daytime; the cycle check opts in.
  if C.settings:get_bool("brickcraft_habitat_test",false) and
    not C.settings:get_bool("brickcraft_cycle_test_only",false) then return end
  local worlds,first={},nil
  for _,p in ipairs(C.get_connected_players()) do
    local w,v=H.world_at(p:get_pos())
    if w and v.cycle then
      worlds[w.id]=w
      if H.cycle_config(w).enabled then first=first or w end
    end
  end
  if first then H.clock.elapsed=H.clock.elapsed+dtime end
  for _,p in ipairs(C.get_connected_players()) do H.sleep_step(p) end
  for _,w in pairs(worlds) do H.night_events(w) end
  sky_wait=sky_wait-dtime
  if sky_wait<=0 then
    sky_wait=.2
    C.set_timeofday(first and H.cycle_status(first).timeofday or .48)
    for _,p in ipairs(C.get_connected_players()) do
      local name=p:get_player_name()
      local w=H.world_at(p:get_pos())
      local phase=w and H.cycle_status(w)
      if phase then
        lighting[name]=lighting[name] or {ratio=p:get_day_night_ratio()}
        p:override_day_night_ratio(C.time_to_day_night_ratio(phase.timeofday))
      elseif lighting[name] then
        p:override_day_night_ratio(lighting[name].ratio); lighting[name]=nil
      end
    end
  end
  save_wait=save_wait-dtime
  if save_wait<=0 then save_wait=10; storage:set_string("habitat_clock",tostring(H.clock.elapsed)) end
end

function H.set_cycle_settings(w,values)
  local cfg=H.cycle_config(w)
  if not cfg then return false,"This habitat has no day/night cycle." end
  local function number(key,low,high,label)
    local n=tonumber(values[key]~=nil and values[key] or cfg[key])
    if not n or n~=n or n<low or n>high or n%1~=0 then
      return nil,label.." must be a whole number from "..low.." to "..high.."."
    end
    return n
  end
  for _,r in ipairs({{"day",10,3600,"Day duration"},{"night",5,600,"Night duration"},{"predator_multiplier",0,10,"Predator multiplier"}}) do
    local n,err=number(r[1],r[2],r[3],r[4])
    if not n then return false,err end
    cfg[r[1]]=n
  end
  for _,key in ipairs({"enabled","lock_players"}) do
    local value=values[key]
    if value~=nil then
      if value==true or value=="true" then cfg[key]=true
      elseif value==false or value=="false" then cfg[key]=false
      else return false,"Invalid checkbox setting." end
    end
  end
  local disaster=values.disaster or cfg.disaster
  local v=H.variant_of(w)
  local allowed=disaster=="random" or disaster=="none"
  for _,id in ipairs(v.disasters or H.disaster_list) do if id==disaster then allowed=true end end
  if not allowed then return false,"Choose a disaster from the list." end
  cfg.disaster=disaster
  local st=H.state(w)
  local active=H.active[w.id]
  if active and active.night_cycle then H.stop_disaster(w,true) end
  st.cycle_settings=cfg
  st.cycle_start=H.clock.elapsed
  st.night_event=nil; st.cycle_phase="day"
  H.save(w); H.reset_wave(w)
  for _,p in ipairs(H.players_in(w)) do H.sleep_step(p) end
  return true,"Day/night settings saved for "..w.name..". A fresh day starts now."
end

local drafts={}
local function default_settings(w)
  local v=H.variant_of(w)
  local cfg={enabled=true,lock_players=true,predator_multiplier=3,disaster="random"}
  for k,value in pairs(v.cycle) do cfg[k]=value end
  return cfg
end
function H.cycle_panel(p,error_text)
  local w,v=H.world_at(p:get_pos())
  if not (w and v.cycle) then return end
  local name=p:get_player_name()
  local draft=drafts[name]
  if not draft or draft.world~=w.id then
    draft={world=w.id,values=H.cycle_config(w)}; drafts[name]=draft
  end
  local cfg=draft.values
  local ids,labels={"random","none"},{"Random","None"}
  for _,id in ipairs(v.disasters or H.disaster_list) do
    ids[#ids+1]=id; labels[#labels+1]=H.disasters[id].label
  end
  draft.choices={}
  local selected=1
  for i,id in ipairs(ids) do
    draft.choices[labels[i]]=id
    if id==cfg.disaster then selected=i end
  end
  local fs="formspec_version[6]size[10,9.5]bgcolor[#142936;true]"..
    "label[.6,.6;"..C.formspec_escape(w.name.." / DAY AND NIGHT").."]"..
    "textarea[.6,1.05;8.8,.7;;;Shared by everyone here. Change settings while controls are unlocked.]"..
    "checkbox[.6,1.9;cfg_enabled;Enable day/night cycle;"..tostring(cfg.enabled).."]"..
    "field[.6,2.8;4.2,.7;cfg_day;Day seconds (10-3600);"..C.formspec_escape(tostring(cfg.day)).."]"..
    "field[5.2,2.8;4.2,.7;cfg_night;Night seconds (5-600);"..C.formspec_escape(tostring(cfg.night)).."]"..
    "field_close_on_enter[cfg_day;false]field_close_on_enter[cfg_night;false]field_close_on_enter[cfg_predators;false]"..
    "field[.6,4;4.2,.7;cfg_predators;Night predators (0-10x);"..C.formspec_escape(tostring(cfg.predator_multiplier)).."]"..
    "label[5.2,3.7;Night disaster (one)]"..
    "dropdown[5.2,4;4.2,.7;cfg_disaster;"..table.concat(labels,",")..";"..selected.."]"..
    "checkbox[.6,5.3;cfg_lock;Rest at night: lock movement and actions;"..tostring(cfg.lock_players).."]"..
    "label[.6,6;0x = no night packs. None = no night disaster.]"..
    "label[.6,6.5;Save starts a new day. Cycle off = always daytime.]"..
    "textarea[.6,7;8.8,.85;;;"..C.formspec_escape(error_text or "Default: 270s day / 30s night / 3x predators / random disaster / rest").."]"..
    "button[.6,8.1;2.7,.8;defaults;Restore defaults]"..
    "style[save;bgcolor=#3a7a52]button[3.65,8.1;2.7,.8;save;Save settings]"..
    "button[6.7,8.1;2.7,.8;cancel;Cancel]"
  C.show_formspec(name,"brickcraft_habitat:cycle",fs)
end
C.register_on_player_receive_fields(function(p,formname,fields)
  if formname~="brickcraft_habitat:cycle" then return end
  local name=p:get_player_name()
  local w=H.world_at(p:get_pos())
  local draft=drafts[name]
  if not w or not draft or draft.world~=w.id then drafts[name]=nil; return true end
  if fields.cancel or fields.quit then
    drafts[name]=nil
    if fields.cancel then H.panel(p) end
    return true
  end
  local keys={cfg_enabled="enabled",cfg_day="day",cfg_night="night",cfg_predators="predator_multiplier",cfg_lock="lock_players"}
  for field,key in pairs(keys) do if fields[field]~=nil then draft.values[key]=fields[field] end end
  if fields.cfg_disaster then draft.values.disaster=draft.choices[fields.cfg_disaster] or "invalid" end
  if fields.defaults then draft.values=default_settings(w); H.cycle_panel(p); return true end
  if fields.save then
    local ok,msg=H.set_cycle_settings(w,draft.values)
    if ok then drafts[name]=nil; H.tell(w,msg); H.panel(p)
    else H.cycle_panel(p,msg) end
  end
  return true
end)

C.register_on_joinplayer(function(p) restore_interact(p:get_player_name()) end)
C.register_on_leaveplayer(function(p)
  wake(p); lighting[p:get_player_name()]=nil; drafts[p:get_player_name()]=nil
end)
C.register_on_shutdown(function()
  for _,p in ipairs(C.get_connected_players()) do
    wake(p)
    local saved=lighting[p:get_player_name()]
    if saved then p:override_day_night_ratio(saved.ratio) end
  end
  storage:set_string("habitat_clock",tostring(H.clock.elapsed))
end)
C.register_allow_player_inventory_action(function(p)
  if H.actions_blocked(p) then return 0 end
end)
-- Insert before existing callbacks so menus/chat cannot bypass the nighttime lock.
C.register_on_mods_loaded(function()
  table.insert(C.registered_on_player_receive_fields,1,function(p)
    if H.actions_blocked(p) then return true end
  end)
  table.insert(C.registered_on_chatcommands,1,function(name)
    local p=C.get_player_by_name(name)
    if H.actions_blocked(p) then C.chat_send_player(name,"Rest until dawn to use commands."); return true end
  end)
  table.insert(C.registered_on_chat_messages,1,function(name)
    local p=C.get_player_by_name(name)
    if H.actions_blocked(p) then C.chat_send_player(name,"Rest until dawn to talk or give orders."); return true end
  end)
end)
end
