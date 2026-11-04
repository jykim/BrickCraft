-- Opt-in balance check (tools/sim_habitat.py): virtual players raise Bunnyland colonies,
-- each in its own world, all against the same schedule of predators and disasters, with
-- no client connected (the worlds are force-loaded). Strategies:
--   none        the starter kit put down by the colony, nothing more
--   chase       no building; chases predators off (8 s to react, a punch every 1.5 s)
--   reasonable  a closed ring of the kit's fence pieces around the colony, the kit inside,
--               buys what the advisor asks for (hutches, food, water, a lookout,
--               a nursery) and chases predators like chase
--   strong      reasonable, but a brick wall two high and a roof over the whole yard:
--               a sealed bunker
-- Survival = bunnies alive at the end / every bunny the colony ever had (5 + births).
-- Settings: brickcraft_habitat_sim_runs ("none;chase;reasonable;strong"),
-- brickcraft_habitat_sim_minutes, brickcraft_habitat_sim_tune ("wolf.speed=3.5 colony.birth=40 ..."),
-- brickcraft_habitat_sim_seed.
local C=core
local H=brickcraft.habitat
local V=H.variants.bunny
local MINUTES=tonumber(C.settings:get("brickcraft_habitat_sim_minutes") or "") or 12
local SEED=tonumber(C.settings:get("brickcraft_habitat_sim_seed") or "") or 1
local function log(msg) C.log("action","BRICKCRAFT HSIM "..msg) end
local co
local function sleep(t) C.after(t,function() local ok,err=coroutine.resume(co); if not ok then error(err) end end); coroutine.yield() end
local RUNS={}
for part in (C.settings:get("brickcraft_habitat_sim_runs") or "none;chase;reasonable;strong"):gmatch("[^;]+") do RUNS[#RUNS+1]=part end
-- Balance changes: "<predator|creature|disaster|colony>.<key>=<number>", or wave.min / wave.max.
for k1,k2,v in (C.settings:get("brickcraft_habitat_sim_tune") or ""):gmatch("([%w_]+)%.([%w_]+)=([%d%.]+)") do
  if k1=="wave" then V.wave[k2=="min" and 1 or 2]=tonumber(v)
  else
    local t=k1=="colony" and V.colony or H.predators[k1] or H.creatures[k1] or H.disasters[k1]
    assert(t,"nothing called "..k1)
    t[k2]=tonumber(v)
  end
  log("tune "..k1.."."..k2.."="..v)
end

local causes={}
local lost_hook=H.colony_lost
H.colony_lost=function(w,ent,how)
  causes[ent._owner]=causes[ent._owner] or {}
  local k=(how or "lost"):gsub("^was ",""):gsub(" an? "," "):gsub("^had nothing to drink","thirst"):gsub("^starved","hunger")
  causes[ent._owner][k]=(causes[ent._owner][k] or 0)+1
  return lost_hook(w,ent,how)
end

local function set(q,name,owner)
  C.set_node(q,{name=name})
  if owner then C.get_meta(q):set_string("owner",owner) end
end
local function forceload(w)
  for x=w.x-48,w.x+48,16 do for z=w.z-48,w.z+48,16 do for y=-16,32,16 do
    C.forceload_block({x=x,y=y,z=z},true)
  end end end
end
local R=6 -- the yard: fence at ±R around the site
-- Interior spots for things the player puts down, in order.
local SPOTS={}
for r=2,R-1 do for x=-r,r do for z=-r,r do
  if math.max(math.abs(x),math.abs(z))==r and (x+z)%2==0 then SPOTS[#SPOTS+1]={x=x,z=z} end
end end end
local function put_down(run,id)
  for i=run.next_spot,#SPOTS do
    local q={x=run.site.x+SPOTS[i].x,y=0,z=run.site.z+SPOTS[i].z}
    if C.get_node(q).name=="air" then
      set(q,"brickcraft_habitat:"..id,run.owner); run.next_spot=i+1; return true
    end
  end
end
local function buy_and_place(run,id)
  local c=H.colony(run.w,run.owner)
  for _,e in ipairs(V.colony.shop) do
    if e[1]==id and (c.clovers or 0)>=e[2] then
      c.clovers=c.clovers-e[2]
      if put_down(run,id) then run.bought[id]=(run.bought[id] or 0)+1; return true end
      c.clovers=c.clovers+e[2]
    end
  end
end
local function manage(run)
  H.tally(run.w,true)
  local s=H.colony_status(run.w,V,run.owner)
  if s.pop==0 then return end
  if s.cap<=s.pop+1 then buy_and_place(run,"hutch")
  elseif s.food<1 then buy_and_place(run,"carrot_patch")
  elseif s.water<1 then buy_and_place(run,"water_trough")
  elseif s.lookouts==0 then buy_and_place(run,"lookout")
  elseif s.nursery==0 then buy_and_place(run,"nursery")
  elseif s.cap<s.pop+4 then buy_and_place(run,"hutch") end
end
-- The player chasing predators that come near the colony.
local function chase(run,dt)
  for ent in pairs(H.hunters) do
    local q=ent.object:get_pos()
    if q and H.flat(q,run.site)<16 then
      run.seen[ent]=(run.seen[ent] or 0)+dt
      if run.seen[ent]>8 and (run.hit[ent] or 0)<=0 and not ent._gone then
        run.hit[ent]=1.5
        ent:_hit(nil,{dmg=1},{x=0,y=2,z=0})
        run.punches=run.punches+1
      end
      run.hit[ent]=(run.hit[ent] or 0)-dt
    end
  end
end

local function setup(run,w)
  run.w=w; run.owner="sim_"..run.name
  w.habitat="bunny"; brickcraft.save_worlds()
  local st=H.state(w); st.built=true; st.spawned=true; st.wild=false; H.save(w)
  forceload(w)
  run.site={x=w.x,y=0,z=w.z-12}
  C.load_area({x=w.x-48,y=-2,z=w.z-48},{x=w.x+48,y=30,z=w.z+48})
  -- A clear, flat yard on the baseplate.
  for x=-R-2,R+2 do for z=-R-2,R+2 do for y=0,6 do C.remove_node({x=run.site.x+x,y=y,z=run.site.z+z}) end end end
  if run.name~="none" and run.name~="chase" then
    for x=-R,R do for z=-R,R do
      local edge=math.max(math.abs(x),math.abs(z))==R
      -- Reasonable: the kit's fence pieces. Strong: a brick wall two high.
      if edge and run.name=="strong" then for y=0,1 do set({x=run.site.x+x,y=y,z=run.site.z+z},"brickcraft:navy") end
      elseif edge then set({x=run.site.x+x,y=0,z=run.site.z+z},"brickcraft_habitat:fence") end
      if run.name=="strong" then set({x=run.site.x+x,y=2,z=run.site.z+z},"brickcraft:navy") end
    end end
  end
  run.next_spot=1
  H.found_colony(w,V,run.owner,{x=run.site.x,y=0,z=run.site.z})
  for id,n in pairs(V.colony.kit) do for _=1,n do put_down(run,id) end end
  run.bought,run.seen,run.hit,run.punches={}, {}, {}, 0
end

local function run_all()
  local runs={}
  for i,name in ipairs(RUNS) do
    local w
    brickcraft.make_world("Sim "..name,"sim",function(made) w=made end)
    while not (w and w.built) do sleep(.5) end
    runs[i]={name=name}
    setup(runs[i],w)
  end
  sleep(2)
  math.randomseed(SEED)
  -- The schedule: a predator every wave seconds, a disaster every ~4 minutes.
  local events={}
  local w1,w2=V.wave[1],V.wave[2]
  local t=40
  while t<MINUTES*60-20 do
    events[#events+1]={t=t,pred=V.predators[math.random(#V.predators)],a=math.random()*2*math.pi}
    t=t+w1+math.random()*(w2-w1)
  end
  local order={"flood","asteroids","earthquake"}
  for i=#order,2,-1 do local j=math.random(i); order[i],order[j]=order[j],order[i] end
  local k=0
  for dt=150,MINUTES*60-60,240 do k=k+1; events[#events+1]={t=dt+math.random(-30,30),dis=order[(k-1)%3+1]} end
  table.sort(events,function(a,b) return a.t<b.t end)
  for _,e in ipairs(events) do log("schedule "..math.floor(e.t).." s: "..(e.pred or e.dis)) end
  local start=H.now()
  local ei=1
  local manage_wait=0
  while H.now()-start<MINUTES*60 do
    local now=H.now()-start
    while events[ei] and events[ei].t<=now do
      local e=events[ei]
      for _,r in ipairs(runs) do
        if e.pred then
          -- The same side for every world; the pack as big as that colony draws.
          H.spawn_predator(r.w,e.pred,{angle=e.a})
        else H.start_disaster(r.w,e.dis) end
      end
      log(math.floor(now).." s: "..(e.pred or e.dis))
      ei=ei+1
    end
    for _,r in ipairs(runs) do
      H.colony_tick(r.w,V)
      if r.name~="none" then chase(r,1) end
    end
    manage_wait=manage_wait-1
    if manage_wait<=0 then
      manage_wait=5
      for _,r in ipairs(runs) do if r.name=="reasonable" or r.name=="strong" then manage(r) end end
    end
    if math.floor(now)%60==0 then
      local parts={}
      for _,r in ipairs(runs) do parts[#parts+1]=r.name.." "..H.creature_count(r.w,r.owner) end
      log("minute "..math.floor(now/60)..": "..table.concat(parts,", "))
    end
    sleep(1)
  end
  for _,r in ipairs(runs) do
    local c=H.colony(r.w,r.owner)
    local alive=H.creature_count(r.w,r.owner)
    local cs={}
    for why,n in pairs(causes[r.owner] or {}) do cs[#cs+1]=why.." "..n end
    table.sort(cs)
    local bought={}
    for id,n in pairs(r.bought) do bought[#bought+1]=id.." "..n end
    table.sort(bought)
    log(string.format("RESULT %-10s survival %3d%%  alive %2d  born %2d  lost %2d  best %2d  punches %d  bought [%s]  lost to [%s]",
      r.name,math.floor(100*alive/math.max(1,c.born or 0)+.5),alive,c.born or 0,c.lost or 0,c.best or 0,r.punches,
      table.concat(bought,", "),table.concat(cs,", ")))
  end
  log("PASS: simulated "..MINUTES.." minutes")
  C.request_shutdown("BrickCraft habitat sim done",false,1)
end
C.after(3,function()
  co=coroutine.create(run_all)
  local ok,err=coroutine.resume(co)
  if not ok then error(err) end
end)
