-- Opt-in balance check (tools/sim_siege.py): virtual sieges with nobody in war. The Red
-- Army against the castle's archers (and, in some runs, blue knights standing in for
-- players' squads), each run with its own balance (brickcraft.war.tune), up to LIMIT
-- seconds. An observer hovers high over the castle, out of war, so the area stays active.
local C=core
local W=brickcraft.war
local LIMIT=tonumber(C.settings:get("brickcraft_siege_sim_limit") or "") or 150
local function log(msg) C.log("action","BRICKCRAFT SIM "..msg) end
local co
local function sleep(t) C.after(t,function() local ok,err=coroutine.resume(co); if not ok then error(err) end end); coroutine.yield() end
-- name, balance changes, blue knights in the courtyard
local RUNS={}
for part in (C.settings:get("brickcraft_siege_sim_runs") or "base"):gmatch("[^;]+") do
  local r={name=part,tune={},blues=0}
  for k,v in part:gmatch("([%w_]+)=([%d%.]+)") do
    if k=="blues" then r.blues=tonumber(v) else r.tune[k]=tonumber(v) end
  end
  RUNS[#RUNS+1]=r
end
local DEFAULT={}
for k,v in pairs(W.tune) do DEFAULT[k]=v end

local function battle(w,run,watcher)
  for k,v in pairs(DEFAULT) do W.tune[k]=v end
  for k,v in pairs(run.tune) do W.tune[k]=v end
  W.reset_castle(w)
  for ent in pairs(W._things()) do if ent._team=="blue" and not ent._archer and ent.object:get_pos() then ent.object:remove() end end
  sleep(1)
  W.siege_army(w)
  local id
  for i,a in pairs(W.armies) do if a.lab==w then id=i end end
  assert(id,"no army")
  for i=1,run.blues do
    local a=i*2*math.pi/run.blues
    W.spawn_knight({x=w.x+math.floor(math.cos(a)*4+.5),y=0,z=w.z+math.floor(math.sin(a)*3+.5)},"blue")
  end
  local start=C.get_us_time()
  local first,taken,outcome
  local red0
  local stats
  while true do
    watcher:set_pos({x=w.x,y=34,z=w.z-20}); watcher:set_velocity({x=0,y=0,z=0})
    local t=(C.get_us_time()-start)/1e6
    local red,inside,archers,cannons,walls,foot,far=0,0,0,0,0,0,0
    for ent in pairs(W._things()) do
      local p=ent.object:get_pos()
      if p and not ent._down then
        if ent._army==id and ent.name=="brickcraft:knight" and not ent._boss then
          red=red+1
          local m=math.max(math.abs(p.x-w.x),math.abs(p.z-w.z))
          if m<8.5 and p.y<3 then inside=inside+1
          elseif p.y>=3 then walls=walls+1
          elseif m<=14 then foot=foot+1 else far=far+1 end
        elseif ent._army==id and ent.name=="brickcraft:cannon" then cannons=cannons+1
        elseif ent._archer==w.id then archers=archers+1 end
      end
    end
    red0=red0 or red
    local army=W.armies[id]
    -- Nobody's in war here: as if players were, it mustn't go home, and its Commander's
    -- plan (guard him, with no players to fight) is charge instead.
    if army then army.alone=nil; if army.order.mode~="charge" then army.order={mode="charge",at=army.order.at} end end
    local tower=0
    for _,c in ipairs({{11,0,-7},{11,4,-3},{3,0,-11},{7,4,-11}}) do
      if C.get_node({x=w.x+c[1],y=c[2],z=w.z+c[3]}).name=="brickcraft:siege_tower" then tower=tower+1 end
    end
    stats=("red knights %d/%d (up on walls %d, at the walls %d, back %d), red cannons %d, archers %d/12, Commander %s, castle damage %d, tower ends %d/4"):format(
      red,red0,walls,foot,far,cannons,archers,army and army.boss._hp.."/20" or "out",#W.castle_damage(w),tower)
    if math.floor(t)%20==0 then log(("  %s at %.0f s: %s"):format(run.name,t,stats)) end
    if inside>0 and not first then first=t end
    if not army then outcome="castle holds (Commander knocked out)" end
    if red==0 and cannons==0 and army then outcome="castle holds (army out)" end
    if inside>=12 then taken=t; outcome="Red Army takes the courtyard (12 in)" end
    if t>=LIMIT then outcome="nobody won in "..LIMIT.." s" end
    if outcome then
      log(("RUN %s: %s at %.0f s; first red knight in at %s; %s"):format(run.name,outcome,t,
        first and ("%.0f s"):format(first) or "never",stats))
      break
    end
    sleep(1)
  end
  W.reset_castle(w)
end

local function run(watcher)
  local w
  while not w do w=W.castle(); if w and not w.castle_built then w=nil end; if not w then sleep(1) end end
  watcher:set_physics_override({gravity=0,speed=0})
  watcher:set_pos({x=w.x,y=34,z=w.z-20}); watcher:set_look_vertical(1)
  sleep(3)
  for _,r in ipairs(RUNS) do battle(w,r,watcher) end
  log("DONE")
  C.request_shutdown("BrickCraft siege simulated",false,1)
end
C.register_on_joinplayer(function(player)
  C.after(2,function()
    if co then return end
    co=coroutine.create(function() run(player) end)
    local ok,err=coroutine.resume(co)
    if not ok then error(err) end
  end)
end)
