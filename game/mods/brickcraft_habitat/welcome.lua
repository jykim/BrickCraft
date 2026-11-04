-- The habitat welcome: the rules and this world's settings, shown the first time each
-- player is in a habitat world (after "Who's playing?"), and again from the panel's
-- Rules button or /habitat help. Built from the registries, so another variant gets its
-- own: its creatures, predators (with their tips), disasters, structures, colony numbers;
-- a variant can add def.welcome (a sentence or two at the top).
return function(H)
local C=core
local E=C.formspec_escape
-- How often predators come by themselves: the variant's wave times this.
H.PACES={{id="calm",label="Calm",mult=2,about="about every 4-7 minutes"},
  {id="normal",label="Normal",mult=1,about="about every 2-4 minutes"},
  {id="wild",label="Wild",mult=.55,about="about every 1-2 minutes"}}
function H.pace_of(st)
  for _,p in ipairs(H.PACES) do if p.id==(st.pace or "normal") then return p end end
  return H.PACES[2]
end
local function list(ids,f)
  local out={}
  for _,id in ipairs(ids or {}) do out[#out+1]=f(id) end
  return table.concat(out,"\n")
end
local function text(p,w,v)
  local cr=H.creatures[v.creature]
  local P,cfg=v.plural,v.colony
  local t="<style color=#ffe27a size=18><b>Keep the "..P.." safe, and grow your own colony.</b></style>\n"..
    (v.welcome and v.welcome.."\n" or "")..
    "\n<b>The "..P.."</b>\n"..
    "They get hungry and thirsty and walk to food and water by themselves; with neither they lose hearts. "..
    "Right click one to see how it's doing. Well-fed "..P.." have babies.\n"..
    "\n<b>Predators</b> come from the edge of the world. Punch them (a sword hits harder) to chase them off.\n"..
    list(v.predators,function(id) local d=H.predators[id]; return "  - "..d.label..": "..(d.tip or "") end).."\n"..
    "\n<b>Disasters</b> start when someone calls one (/disaster or the panel), after a 10 second warning.\n"..
    list(v.disasters or H.disaster_list,function(id) local d=H.disasters[id]; return "  - "..d.label..": "..(d.warning or "") end).."\n"..
    "Disasters never break your bricks.\n"
  if v.defense then
    t=t.."\n<b>Build and defend together</b>\nSword and Bow arrive in your bag (I); drag them to the hotbar. "..
      "Use them against predators while keeping all your building supplies. No /war needed.\n"..
      "<b>Guardian cats</b>\nPlace a Cat feeder and right click it holding Churu. Each tube feeds a cat for 2 minutes. "..
      "The cat patrols nearby and chases predators away. Buy feeders and churu in /colony; your starter kit includes both.\n"
  end
  if v.cycle then
    local cc=H.cycle_config(w)
    t=t.."\n<b>Day and night</b>\n"..
      (cc.enabled and ("Day: "..cc.day.." seconds. Night: "..cc.night.." seconds. ") or "The cycle is disabled: always daytime. ")..
      (cc.lock_players and "Players rest at night; control returns at dawn. " or "Players can move and act at night. ")..
      "Night predator multiplier: "..cc.predator_multiplier..". Night disaster: "..cc.disaster..". "..
      "Change durations and night rules in /habitat > Day / night settings (or /habitat cycle).\n"
  end
  if cfg then
    t=t.."\n<b>Your colony</b>\n"..
      "Start one with "..cfg.start.." "..P.." (/colony start), or right click a wild animal and choose Domesticate & follow. "..
      "Domesticated animals get your name label and follow you home; /colony stay settles them there. "..
      (cfg.win_count and ("Your HUD shows each player's count. Reach "..cfg.win_count.." owned "..P..", including babies, to win! ") or "")..
      (cfg.hutch_bricks and ("Get more hutches in /colony: buy one for 25 clovers or build one from "..cfg.hutch_bricks.." basic bricks of any colors (/colony craft hutch). Place each hutch for four more bunny spaces. ") or "")..
      "Babies come only when the colony "..
      "is happy ("..(cfg.happy or 60).."%+) and has room. Happiness comes from homes, food (one patch feeds "..(cfg.feeds or 4)..
      "), water (one trough serves "..(cfg.waters or 6)..") and safety. Your "..P.." gather clovers; spend them in the shop:\n"..
      list(cfg.shop,function(e)
        local d=C.registered_nodes["brickcraft_habitat:"..e[1]]
        local desc=(d and d.description or e[1]):gsub("\nRight click.*$","")
        local name,about=desc:match("^([^\n]+)\n?(.*)$")
        return "  - "..name.." ("..e[2].." clovers)"..(about~="" and ": "..about:gsub("\n","; ") or "")
      end).."\n"..
      "Levels: "..list(cfg.levels,function(l) return l[2].." ("..l[1]..")" end):gsub("\n",", ")..".\n"
  end
  t=t.."\n<b>Tips</b>\n"..(v.tip or "").."\n"..
    (v.keep_in or "").."\n"..
    "Herding: right click one of your "..P.." and it follows you; /colony call brings all of them, /colony stay makes "..
    "where you stand their home. Walk up to one to shoo it along.\n"..
    "/habitat: predators, disasters, skins, food and water    /colony: your colony and shop    /skin: bunny looks"
  return t
end
function H.welcome(p)
  local w,v=H.world_at(p:get_pos())
  if not w then return end
  local st=H.state(w)
  local pace=H.pace_of(st)
  local name=p:get_player_name()
  local has=v.colony and H.creature_count(w,H.owner_of(p))>0
  local fs="formspec_version[6]size[12,11.2]bgcolor[#142936;true]"..
    "label[.6,.6;"..E((v.label.." / how it works"):upper()).."]"..
    "hypertext[.6,1;10.8,6.6;rules;"..E("<global color=#e6edf2 size=14>"..text(p,w,v)).."]"..
    "box[.6,7.8;10.8,.04;#3a5566]"..
    "label[.6,8.2;"..E("Settings for "..w.name.." (everyone here shares them)").."]"..
    "label[.6,8.8;Predators come by themselves]"..
    "style[wild;bgcolor="..(st.wild==false and "#3a5566" or "#3a7a52").."]"..
    "button[5,8.45;1.6,.7;wild;"..(st.wild==false and "Off" or "On").."]"
  for i,pc in ipairs(H.PACES) do
    fs=fs.."style[pace_"..pc.id..";bgcolor="..(pc==pace and "#f5872c" or "#3a5566").."]"..
      "button["..(6.8+(i-1)*1.55)..",8.45;1.5,.7;pace_"..pc.id..";"..pc.label.."]"
  end
  fs=fs.."label[.6,9.45;"..E(st.wild==false and "Predators only come when someone calls them." or
      "How often: "..pace.label.." ("..pace.about..")").."]"
  local skin=(v.skins or H.skin_list)[1]
  if v.colony then
    fs=fs..(has and "button[.6,10.1;3.4,.8;colony;My colony]" or
      "style[start;bgcolor=#f5872c]button[.6,10.1;3.4,.8;start;Start my colony ("..v.colony.start..")]")
  end
  if skin then fs=fs.."button[4.2,10.1;3.4,.8;skin;"..E("Be a "..H.skins[skin].label).."]" end
  fs=fs.."style[go;bgcolor=#3a7a52]button_exit[7.8,10.1;3.6,.8;go;Let's go!]"
  C.show_formspec(name,"brickcraft_habitat:welcome",fs)
end
C.register_on_player_receive_fields(function(p,formname,fields)
  if formname~="brickcraft_habitat:welcome" then return end
  local name=p:get_player_name()
  local w,v=H.world_at(p:get_pos())
  if not w or fields.go or fields.quit then return true end
  local st=H.state(w)
  if fields.wild then
    st.wild=st.wild==false; H.save(w)
    H.tell(w,H.label_of(H.owner_of(p)).." turned predators "..(st.wild and "on" or "off")..".")
  end
  for _,pc in ipairs(H.PACES) do
    if fields["pace_"..pc.id] then
      st.pace=pc.id; st.wild=true; H.save(w); H.reset_wave(w)
      H.tell(w,H.label_of(H.owner_of(p)).." set predators to "..pc.label.." ("..pc.about..").")
    end
  end
  if fields.start then local _,msg=H.start_colony(p); C.chat_send_player(name,msg) end
  if fields.colony then H.colony_panel(p); return true end
  if fields.skin then
    local id=(v.skins or H.skin_list)[1]
    H.set_skin(p,id); C.chat_send_player(name,"You're "..H.skins[id].label.."! (/skin for others, /skin off)")
  end
  H.welcome(p)
  return true
end)
-- First time in a habitat world: once the player has picked who they are and has been
-- there a few seconds (so the game's own pickers are done).
local here_since={}
function H.welcome_check(p,w)
  local name=p:get_player_name()
  if not w or not brickcraft.playing_as(p) then here_since[name]=nil; return end
  local key="brickcraft_habitat_welcomed_"..w.id
  if p:get_meta():get_int(key)==1 then return end
  here_since[name]=here_since[name] or H.now()
  if H.now()-here_since[name]>=4 then
    p:get_meta():set_int(key,1); here_since[name]=nil
    H.welcome(p)
  end
end
C.register_on_leaveplayer(function(p) here_since[p:get_player_name()]=nil end)
end
