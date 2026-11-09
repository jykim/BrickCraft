-- Opt-in check (tools/test_habitat.py): a dedicated server and one real client in a world
-- named "Bunnyland". It becomes the Bunnyland habitat by its name: the giant bunny statue
-- goes up, carrot patches and water troughs are put out and 8 bunnies hop out. A hungry
-- bunny eats from a patch. A wolf catches a bunny in the open but not one behind a fence
-- two bricks high; punches chase a wolf away. An eagle snatches a bunny in the open but
-- not one under a roof. A flood covers low ground, spoils food on the ground and leaves a
-- sealed bunker dry, then drains; asteroids and an earthquake run and end. A bunny skin
-- goes on and off; the panel's kit gives food and water. A second habitat, registered here
-- from definitions only, gets its own creatures: the framework is general.
local C=core
local DAD="HabitatDad"
local H=brickcraft.habitat
local function log(msg) C.log("action","BRICKCRAFT HABITAT "..msg) end
local co
local function sleep(t) C.after(t,function() local ok,err=coroutine.resume(co); if not ok then error(err) end end); coroutine.yield() end
local function wait(limit,check,what)
  local start=C.get_us_time()
  while not check() do
    assert(C.get_us_time()-start<limit*1e6,"timed out: "..what())
    sleep(.2)
  end
end

-- A variant made only of definitions: the bunny creature, no statue, one predator.
H.register_variant("meadow",{label="Meadow",plural="bunnies",creature="bunny",count=3,max=4,
  sources={{"carrot_patch",0,26}},kit={carrot_patch=1},predators={"wolf"},disasters={"flood"},skins={"gray"}})

local function bunnies(w)
  local list={}
  for ent in pairs(H.live) do
    local q=ent.object:get_pos()
    if q and not ent._dead and brickcraft.world_at(q)==w then list[#list+1]=ent end
  end
  return list
end
-- Holds a bunny at a spot: it stands, full, until let go.
local function park(ent,pos)
  ent.object:set_pos(pos); ent.object:set_velocity({x=0,y=0,z=0})
  ent._food,ent._water=100,100
end
local function ring(c,r,h,roof,name)
  for x=-r,r do for z=-r,r do
    if math.max(math.abs(x),math.abs(z))==r then for y=0,h-1 do C.set_node({x=c.x+x,y=c.y+y,z=c.z+z},{name=name or "brickcraft:navy"}) end end
    if roof then C.set_node({x=c.x+x,y=c.y+h,z=c.z+z},{name=name or "brickcraft:navy"}) end
  end end
end
local function clear(c,r,h)
  for x=-r,r do for z=-r,r do for y=0,h do C.remove_node({x=c.x+x,y=c.y+y,z=c.z+z}) end end end
end
local function hunters() local n=0; for _ in pairs(H.hunters) do n=n+1 end; return n end
local function kill_hunters() for e in pairs(H.hunters) do e._gone=true; H.hunters[e]=nil; e.object:remove() end end

local function eagle_regressions(w,dad,roofed)
  local saved_pos=roofed.object:get_pos()
  -- Low ceilings in the bunny's rounded cell and roofs higher than eight blocks.
  local shelter={x=w.x-30,y=0,z=w.z-17}
  clear(shelter,1,15)
  for _,height in ipairs({1,12}) do
    local ceiling=vector.offset(shelter,0,height,0)
    C.set_node(ceiling,{name="brickcraft:navy"})
    park(roofed,vector.offset(shelter,0,.5,0))
    assert(H.sheltered(roofed.object:get_pos()),"roof at height "..height.." shelters bunny")
    local eagle_ent=C.add_entity(vector.offset(shelter,0,.8,0),"brickcraft_habitat:eagle"):get_luaentity()
    eagle_ent._prey=roofed -- already diving when the bunny reaches shelter
    H.flyer_step(eagle_ent,H.predators.eagle,.2)
    assert(not roofed._carried,"roof prevents pickup during a dive")
    kill_hunters()
    C.remove_node(ceiling)
  end
  -- Adults and babies keep their size through pickup and rescue.
  for _,is_baby in ipairs({false,true}) do
    roofed._baby=is_baby; roofed:_dress()
    local expected=is_baby and 6 or 10
    park(roofed,vector.offset(shelter,0,.5,0))
    local eagle_ent=C.add_entity(vector.offset(shelter,0,.8,0),"brickcraft_habitat:eagle"):get_luaentity()
    eagle_ent._prey=roofed
    H.flyer_step(eagle_ent,H.predators.eagle,.2)
    assert(roofed._carried,"bunny picked up in the open")
    local carried_size=roofed.object:get_properties().visual_size
    local eagle_size=eagle_ent.object:get_properties().visual_size
    assert(math.abs(carried_size.x*eagle_size.x-expected)<.001 and
    math.abs(carried_size.y*eagle_size.y-expected)<.001,"carried bunny keeps its world size")
    eagle_ent:_hit(dad,{dmg=1})
    assert(roofed.object:get_properties().visual_size.x==expected,"rescued bunny keeps its original size")
    kill_hunters()
  end
  roofed._baby=nil; roofed:_dress()
  park(roofed,saved_pos)
  kill_hunters()
  log("low and tall roofs block eagle pickups; adults and babies keep their size when carried and rescued")
end

local function colony_regressions(w,dad)
  local v=H.variants.bunny
  local owner=H.owner_of(dad)
  local site={x=w.x-25,y=.5,z=w.z-25}
  clear(vector.round(site),7,5)
  dad:set_pos(vector.offset(site,0,0,2))
  local wild=H.spawn_creature("bunny",site,{baby=true})
  local function submit(fields)
    for _,f in ipairs(C.registered_on_player_receive_fields) do
      if f(dad,"brickcraft_habitat:domesticate",fields) then return end
    end
    error("domestication form was not handled")
  end
  wild:on_rightclick(dad)
  assert(not wild._owner,"opening domestication panel doesn't claim a bunny")
  submit({cancel=true,quit=true})
  assert(not wild._owner,"cancel leaves bunny wild")
  wild:on_rightclick(dad); submit({domesticate=true,quit=true})
  assert(wild._owner==owner and wild._follow==DAD,"domesticated bunny belongs to and follows player")
  assert(wild.object:get_properties().nametag==H.label_of(owner),"baby receives owner's label after domestication")
  assert(H.creature_count(w,owner)==1,"domestication starts a colony with the adopted bunny")
  assert(not H.domesticate(wild,dad),"cannot domesticate twice")
  local rival=H.spawn_creature("bunny",vector.offset(site,1,0,0),{owner="test_rival"})
  assert(not H.domesticate(rival,dad) and rival._owner=="test_rival","cannot steal another player's bunny")
  local far=H.spawn_creature("bunny",vector.offset(site,15,0,0))
  assert(not H.domesticate(far,dad) and not far._owner,"cannot domesticate remotely")
  local unavailable=H.spawn_creature("bunny",site)
  unavailable._carried=true
  assert(not H.domesticate(unavailable,dad),"cannot domesticate an eagle's prey")
  unavailable._carried=nil
  local saved=wild:get_staticdata()
  wild.object:remove()
  wild=C.add_entity(site,"brickcraft_habitat:bunny",saved):get_luaentity()
  assert(wild._owner==owner and wild.object:get_properties().nametag==H.label_of(owner),"ownership and label survive entity reload")
  local notices=0
  local tell=H.tell
  H.tell=function(world,msg,color)
    if msg:find(" wins!",1,true) then notices=notices+1 end
    tell(world,msg,color)
  end
  for i=2,20 do H.spawn_creature("bunny",vector.offset(site,(i%4)*.2,0,0),{owner=owner}) end
  for i=2,21 do H.spawn_creature("bunny",vector.offset(site,3,0,(i%4)*.2),{owner="test_rival"}) end
  local c=H.colony(w,owner)
  H.colony(w,"test_rival")
  H.colony_tick(w,v)
  assert(not c.won and H.colony(w,"test_rival").won,"20 does not win; a different player's 21 does")
  assert(notices==1,"one win announcement per player")
  local scores=H.score_line(w,v)
  assert(scores:find(H.label_of(owner)..": 20/21",1,true) and scores:find("test_rival: 21/21 WON!",1,true),"player scores stay separate and exclude wild bunnies")
  local max=v.colony.max; v.colony.max=20
  assert(not H.domesticate(unavailable,dad),"cannot exceed colony limit")
  v.colony.max=max
  unavailable:on_rightclick(dad); submit({domesticate=true,quit=true})
  assert(c.won and notices==2,"21st bunny wins immediately through domestication")
  H.colony_tick(w,v); H.colony_tick(w,v)
  assert(notices==2,"win announcement is not repeated")
  local stored=C.deserialize(brickcraft.storage:get_string("habitat_"..w.id))
  assert(stored.colonies[owner].won,"victory is saved")
  unavailable.object:remove()
  H.colony_tick(w,v)
  assert(c.won and H.creature_count(w,owner)==20,"victory survives later losses")
  -- A birth that takes the population from 20 to 21 wins too.
  c.won=nil
  for i,id in ipairs({"hutch","hutch","hutch","hutch","hutch","hutch","carrot_patch","carrot_patch","water_trough"}) do
    local q={x=site.x-4+(i%6),y=0,z=site.z+3+math.floor(i/6)}
    C.set_node(q,{name="brickcraft_habitat:"..id}); H.claim(q,dad)
  end
  H.tally(w,true)
  c.next_birth=0
  H.colony_tick(w,v)
  assert(H.creature_count(w,owner)==21 and c.won and notices==3,"a birth at 20 wins at 21")
  H.tell=tell
  assert(H.stay(dad),"domesticated colony can settle at home")
  sleep(2)
  local has_scores=false
  for _,hud in pairs(dad:hud_get_all()) do
    if hud.text and hud.text:find("Players:",1,true) and hud.text:find("21/21",1,true) and hud.text:find("YOU WON!",1,true) then has_scores=true end
  end
  assert(has_scores,"actual player HUD shows counts and victory")
  H.colony_panel(dad)
  C.close_formspec(DAD,"brickcraft_habitat:colony")
  log("domestication labels and ownership persist; player counts stay separate; 21 wins by adoption or birth")
end

local function hutch_regressions(w,dad)
  local inv=dad:get_inventory()
  local owner=H.owner_of(dad)
  local c=H.colony(w,owner)
  local snapshot={}
  for _,list in ipairs({"main","pieces","war_stash"}) do
    snapshot[list]=inv:get_list(list)
    if inv:get_size(list)>0 then inv:set_list(list,{}) end
  end
  inv:add_item("main","brickcraft:coral 3")
  inv:add_item("pieces","brickcraft:sky 4")
  local money=c.clovers
  assert(not H.craft_hutch(dad),"seven bricks cannot build a hutch")
  assert(brickcraft.count_of(dad,"brickcraft:coral")==3 and brickcraft.count_of(dad,"brickcraft:sky")==4,"failed craft keeps all bricks")
  inv:add_item("pieces","brickcraft:sky 1")
  -- A full output bag cannot consume the input materials.
  for i=1,inv:get_size("main") do inv:set_stack("main",i,ItemStack("brickcraft_habitat:water_trough 99")) end
  inv:add_item("pieces","brickcraft:coral 3")
  assert(not H.craft_hutch(dad),"full bag refuses hutch without charging")
  assert(brickcraft.count_of(dad,"brickcraft:coral")==3 and brickcraft.count_of(dad,"brickcraft:sky")==5,"full bag keeps bricks")
  inv:set_list("main",{})
  local ok,msg=C.registered_chatcommands.colony.func(DAD,"craft hutch")
  assert(ok,msg)
  assert(brickcraft.count_of(dad,"brickcraft_habitat:hutch")==1,"command builds hutch")
  assert(brickcraft.count_of(dad,"brickcraft:coral")==0 and brickcraft.count_of(dad,"brickcraft:sky")==0,"craft consumes exactly eight mixed bricks")
  assert(c.clovers==money,"brick recipe costs no clovers")
  local capacity=H.colony_status(w,H.variants.bunny,owner).cap
  local q={x=w.x-32,y=0,z=w.z-25}
  C.remove_node(q)
  local stack=C.registered_items["brickcraft_habitat:hutch"].on_place(ItemStack("brickcraft_habitat:hutch"),dad,
    {type="node",under=vector.offset(q,0,-1,0),above=q})
  assert(stack:is_empty() and C.get_node(q).name=="brickcraft_habitat:hutch","crafted hutch can be placed")
  H.tally(w,true)
  assert(C.get_meta(q):get_string("owner")==owner and H.colony_status(w,H.variants.bunny,owner).cap==capacity+4,"placed hutch belongs to player and adds four spaces")
  inv:add_item("main","brickcraft:coral 8")
  for _,f in ipairs(C.registered_on_player_receive_fields) do
    if f(dad,"brickcraft_habitat:colony",{craft_hutch=true}) then break end
  end
  assert(brickcraft.count_of(dad,"brickcraft_habitat:hutch")==2,"colony button repeatedly builds more hutches")
  c.clovers=25
  assert(H.buy(dad,"hutch") and c.clovers==0,"existing clover purchase still works")
  assert(brickcraft.count_of(dad,"brickcraft_habitat:hutch")==3,"players can buy or build housing")
  H.clock.elapsed=270
  inv:add_item("main","brickcraft:coral 8")
  assert(not H.craft_hutch(dad) and brickcraft.count_of(dad,"brickcraft:coral")==8,"night refuses crafting without consuming bricks")
  H.clock.elapsed=0
  c.clovers=money
  for list,items in pairs(snapshot) do inv:set_list(list,items) end
  C.close_formspec(DAD,"brickcraft_habitat:colony")
  log("hutches can be bought or repeatedly built from eight mixed bricks; placement adds four breeding spaces")
end

local function cycle_regressions(w,dad)
  local v=H.variants.bunny
  assert(v.cycle.day==270 and v.cycle.night==30,"five-minute cycle with thirty-second night")
  H.clock.elapsed=0
  assert(not H.cycle_status(w).night and H.cycle_status(w).remaining==270,"day begins with preparation time")
  assert(not H.actions_blocked(dad),"daytime controls enabled")
  H.clock.elapsed=269.9
  assert(not H.cycle_status(w).night,"night does not start early")
  H.clock.elapsed=270
  assert(H.cycle_status(w).night and H.cycle_status(w).remaining==30,"night lasts thirty seconds")
  assert(H.night_multiplier(w)==3,"night has triple predators")
  local before=dad:get_physics_override()
  local privs=C.get_player_privs(DAD)
  local had_interact=privs.interact
  H.sleep_step(dad)
  assert(dad:get_physics_override().speed==0 and dad:get_physics_override().jump==0,"player frozen")
  assert(not C.get_player_privs(DAD).interact,"night blocks building, digging and combat at engine level")
  local fixed=dad:get_pos()
  dad:set_pos(vector.offset(fixed,2,0,0)); H.sleep_step(dad)
  assert(vector.distance(fixed,dad:get_pos())<.01,"player cannot move during night")
  assert(not H.start_colony(dad) and not H.call(dad) and not H.stay(dad) and not H.buy(dad,"hutch"),"night locks colony actions")
  assert(C.registered_on_player_receive_fields[1](dad,"brickcraft_habitat:panel",{wild=true}),"night blocks menu actions")
  assert(C.registered_on_chatcommands[1](DAD,"habitat","wild off"),"night blocks commands")
  assert(C.registered_allow_player_inventory_actions[#C.registered_allow_player_inventory_actions](dad)==0,"night blocks inventory moves")
  local candidate=H.spawn_creature("bunny",vector.offset(fixed,1,0,0))
  assert(not H.domesticate(candidate,dad),"night blocks domestication")
  local oldwild=H.state(w).wild
  H.state(w).wild=true
  kill_hunters()
  local calls=0
  local start_disaster=H.start_disaster
  H.start_disaster=function(world,id) calls=calls+1; return start_disaster(world,id) end
  H.night_events(w)
  assert(hunters()==3*H.pack_size(w),"dusk spawns three times the regular predator pack")
  assert(calls==1 and H.active[w.id],"one disaster begins at nightfall")
  local event=H.state(w).night_event
  assert(H.disasters[event.disaster] and event.started,"night chooses an actual random disaster")
  local ctx=H.active[w.id]
  assert(ctx.delay+ctx.def.duration<=30,"night disaster fits thirty seconds including warning")
  H.night_events(w); H.night_events(w)
  assert(calls==1 and hunters()==3*H.pack_size(w),"repeated ticks do not duplicate disaster or pack")
  H.stop_disaster(w,true); H.night_events(w)
  assert(calls==1 and not H.active[w.id],"completed disaster cannot repeat in the same night")
  local stored=C.deserialize(brickcraft.storage:get_string("habitat_"..w.id))
  assert(stored.night_event.started and stored.night_event.cycle==1,"night event marker is persisted")
  H.clock.elapsed=300
  H.night_events(w); H.sleep_step(dad)
  assert(not H.cycle_status(w).night and H.cycle_status(w).cycle==2,"dawn after thirty seconds")
  assert(dad:get_physics_override().speed==before.speed and dad:get_physics_override().jump==before.jump,"dawn restores original physics")
  assert(C.get_player_privs(DAD).interact==had_interact,"dawn restores original interaction permission")
  assert(not H.actions_blocked(dad) and H.night_multiplier(w)==1,"daytime actions and predator counts restored")
  -- A second night queues its random disaster behind an existing event, once only.
  H.start_disaster=start_disaster
  H.start_disaster(w,"earthquake")
  H.start_disaster=function(world,id) calls=calls+1; return start_disaster(world,id) end
  H.clock.elapsed=570
  kill_hunters(); H.night_events(w)
  assert(calls==1 and not H.state(w).night_event.started,"night queues behind active disaster")
  H.stop_disaster(w,true); H.night_events(w)
  assert(calls==2 and H.state(w).night_event.cycle==2,"next night starts one new random disaster")
  -- Dawn cleans up even a shortened event that still has time left in its last tick.
  H.clock.elapsed=600; H.night_events(w)
  assert(not H.active[w.id],"dawn cleans up the night's disaster")
  H.start_disaster=start_disaster
  -- Never grant interact to a player who did not have it before sleeping.
  privs=C.get_player_privs(DAD); privs.interact=nil; C.set_player_privs(DAD,privs)
  H.clock.elapsed=870; H.sleep_step(dad)
  H.clock.elapsed=900; H.sleep_step(dad)
  assert(not C.get_player_privs(DAD).interact,"sleep does not grant new permissions")
  privs.interact=had_interact; C.set_player_privs(DAD,privs)
  H.state(w).wild=oldwild
  H.clock.elapsed=0
  kill_hunters()
  candidate.object:remove()
  -- Exercise the same heartbeat used in live play, including the sky and dawn.
  H.clock.elapsed=1170
  H.cycle_step(.5)
  assert(H.actions_blocked(dad) and not C.get_player_privs(DAD).interact,"heartbeat enters the night lock")
  assert(C.get_timeofday()>.75 and C.get_timeofday()<.8,"heartbeat advances sky into night")
  H.cycle_step(30)
  assert(not H.actions_blocked(dad) and C.get_player_privs(DAD).interact==had_interact,"heartbeat wakes the player after thirty real-time seconds")
  assert(not H.active[w.id],"heartbeat cleans up night disaster at dawn")
  H.clock.elapsed=0
  kill_hunters()
  log("five-minute cycles lock actions for thirty seconds; nights have triple packs and exactly one random disaster")
end

local function cycle_settings_regressions(w,dad)
  local function submit(fields)
    for _,f in ipairs(C.registered_on_player_receive_fields) do
      if f(dad,"brickcraft_habitat:cycle",fields) then return end
    end
    error("cycle settings form was not handled")
  end
  H.clock.elapsed=0
  local privs=C.get_player_privs(DAD)
  assert(H.set_cycle_settings(w,{day=20,night=5,predator_multiplier=2,lock_players=false,disaster="none"}),"custom settings accepted")
  assert(H.cycle_status(w).remaining==20,"saving begins a fresh configured day")
  local old_start=H.state(w).cycle_start
  for _,bad in ipairs({{day=0},{day="invalid"},{night=4},{night=5.5},{predator_multiplier=11},{disaster="invalid"},{enabled="invalid"}}) do
    assert(not H.set_cycle_settings(w,bad),"invalid settings rejected")
  end
  assert(H.cycle_config(w).day==20 and H.state(w).cycle_start==old_start,"invalid input leaves settings and phase unchanged")
  local other={id=999,habitat="bunny",x=0,z=0}
  assert(H.cycle_config(other).day==270 and H.cycle_config(other).lock_players,"settings do not affect another habitat")
  kill_hunters()
  local wild=H.state(w).wild; H.state(w).wild=true
  H.clock.elapsed=20
  assert(H.cycle_status(w).night and H.cycle_status(w).remaining==5,"custom durations drive phase")
  assert(not H.actions_blocked(dad) and H.night_multiplier(w)==2,"night actions can be enabled and multiplier changed")
  H.night_events(w)
  assert(hunters()==2*H.pack_size(w) and not H.active[w.id],"custom night has twofold predators and no disaster")
  kill_hunters()
  assert(H.set_cycle_settings(w,{enabled=false}),"cycle can be disabled")
  H.clock.elapsed=100
  H.night_events(w)
  assert(not H.cycle_status(w).night and H.cycle_line(w):find("disabled",1,true) and hunters()==0,"disabled cycle stays in daytime")
  assert(H.set_cycle_settings(w,{enabled=true,day=10,night=5,predator_multiplier=0,lock_players=true,disaster="flood"}),"fixed disaster and zero predators accepted")
  H.clock.elapsed=110
  H.sleep_step(dad); H.night_events(w)
  assert(H.active[w.id] and H.active[w.id].def.id=="flood" and hunters()==0,"fixed flood occurs without predators")
  local active=H.active[w.id]
  H.night_events(w)
  assert(H.active[w.id]==active,"fixed disaster starts only once")
  assert(not C.get_player_privs(DAD).interact,"custom rest rule locks player")
  assert(H.set_cycle_settings(w,{enabled=false}),"disabling while resting restores daytime")
  assert(not H.active[w.id] and C.get_player_privs(DAD).interact==privs.interact,"disabling cleans up night and restores permissions")
  assert(C.registered_chatcommands.habitat.func(DAD,"cycle"),"settings accessible by command")
  submit({cfg_enabled="true",cfg_day="40",cfg_night="10",cfg_predators="0",cfg_lock="false",cfg_disaster="None",save=true})
  local cfg=H.cycle_config(w)
  assert(cfg.enabled and cfg.day==40 and cfg.night==10 and cfg.predator_multiplier==0 and not cfg.lock_players and cfg.disaster=="none","actual settings form applies fields")
  local stored=C.deserialize(brickcraft.storage:get_string("habitat_"..w.id))
  assert(stored.cycle_settings.day==40 and stored.cycle_settings.lock_players==false,"custom settings persist")
  H.cycle_panel(dad); submit({cfg_enabled="false"}); submit({cancel=true})
  assert(H.cycle_config(w).enabled,"cancel discards draft changes")
  H.cycle_panel(dad); submit({defaults=true}); submit({save=true})
  cfg=H.cycle_config(w)
  assert(cfg.enabled and cfg.day==270 and cfg.night==30 and cfg.predator_multiplier==3 and cfg.lock_players and cfg.disaster=="random","restore defaults works through form")
  H.state(w).cycle_start=0
  H.state(w).wild=wild
  H.clock.elapsed=0
  H.save(w)
  C.close_formspec(DAD,"brickcraft_habitat:panel")
  log("habitat cycle settings validate, persist, cancel and reset; custom durations and night events work independently")
end

local function run(dad)
  for _,f in ipairs(C.registered_on_player_receive_fields) do if f(dad,"brickcraft:style",{style_dad="x"}) then break end end
  local w
  brickcraft.make_world("Bunnyland","dad",function(made) w=made end)
  wait(60,function() return w and w.built end,function() return "world not built" end)
  wait(15,function() return w.habitat=="bunny" end,function() return "named Bunnyland but not a habitat" end)
  dad:set_pos({x=w.x,y=1,z=w.z+18}); dad:set_look_horizontal(0)
  local st=H.state(w)
  wait(60,function() return st.built and st.spawned end,function() return "statue or bunnies not out" end)
  wait(10,function() return #bunnies(w)==8 end,function() return "bunnies: "..#bunnies(w) end)
  log("8 bunnies hopped out")
  -- The statue: plinth, head, ear tips 27 up.
  C.load_area({x=w.x-8,y=-1,z=w.z+29},{x=w.x+8,y=30,z=w.z+45})
  assert(C.get_node({x=w.x,y=0,z=w.z+37}).name=="brickcraft_habitat:statue_gold","plinth")
  assert(C.get_node({x=w.x,y=14,z=w.z+35}).name=="brickcraft_habitat:statue_cream","head")
  assert(C.get_node({x=w.x+2,y=15,z=w.z+32}).name=="brickcraft_habitat:statue_navy","an eye")
  assert(C.get_node({x=w.x-2,y=26,z=w.z+36}).name:find("statue"),"an ear tip")
  assert(C.get_item_group(C.get_node({x=w.x,y=0,z=w.z+37}).name,"brick")==0,"statue bricks can't be collected")
  log("the giant bunny statue stands 27 bricks high")
  -- The floor is a meadow with ponds and clover.
  assert(H.state(w).meadow,"meadow laid")
  assert(C.get_node({x=w.x+3,y=-1,z=w.z+3}).name:find("^brickcraft_habitat:meadow"),"meadow floor")
  assert(C.get_node({x=w.x+14,y=-1,z=w.z+6}).name=="brickcraft_habitat:pond","a pond")
  local clovers=#C.find_nodes_in_area({x=w.x-24,y=0,z=w.z-24},{x=w.x+24,y=0,z=w.z+24},{"brickcraft_habitat:clover"})
  assert(clovers>=10,"clover patches: "..clovers)
  log("the floor is a meadow with ponds and "..clovers.." clover patches")
  local patch={x=w.x-8,y=0,z=w.z+26}
  assert(C.get_node(patch).name=="brickcraft_habitat:carrot_patch","a carrot patch")
  assert(C.get_node({x=w.x,y=0,z=w.z+25}).name=="brickcraft_habitat:water_trough","a water trough")
  local food,water=H.supplies(w,true)
  assert(food==3+clovers and water>2,"supplies "..food.."/"..water) -- patches and troughs, clover and ponds

  -- Bunnyland's Korean word story: every numbered word belongs to the player's separate
  -- storybook. Correct ordering unlocks a four-step recipe and its usable bunny reward.
  local story=H.word_story
  assert(story and #story.words==20 and #story.sentences==4,"word story registered")
  local function story_entities(kind)
    local n=0
    for _,o in ipairs(C.get_objects_inside_radius({x=w.x,y=8,z=w.z},80)) do
      local e=o:get_luaentity()
      if e and e.name=="brickcraft_habitat:"..kind then n=n+1 end
    end
    return n
  end
  story.ensure(w)
  wait(5,function() return story_entities("story_word")==20 and story_entities("story_glow")>=4 end,
    function() return "story objects words/glows "..story_entities("story_word").."/"..story_entities("story_glow") end)
  local function fields(form,data)
    for _,f in ipairs(C.registered_on_player_receive_fields) do if f(dad,form,data) then return true end end
  end
  for i=1,#story.words do story.collect(dad,w,i) end
  for n,sen in ipairs(story.sentences) do
    assert(fields("brickcraft_habitat:word_story",{["open_"..n]=true}),"open story sentence "..n)
    for _,i in ipairs(sen.words) do assert(fields("brickcraft_habitat:word_sentence",{["add_"..i]=true}),"add word "..i) end
    assert(fields("brickcraft_habitat:word_sentence",{check=true}),"check sentence "..n)
  end
  local ss=story.state(dad,w)
  for n=1,4 do assert(ss.complete[n],"sentence "..n.." completed") end
  story.ensure(w)
  wait(5,function() return story_entities("story_recipe")==4 end,
    function() return "recipe markers "..story_entities("story_recipe") end)
  for i=1,4 do story.recipe_collect(dad,w,i,dad:get_pos()) end
  ss=story.state(dad,w)
  assert(ss.recipe_step==4 and ss.rewarded,"recipe completed and rewarded")
  assert(brickcraft.count_of(dad,story.reward)==1,"magic carrot soup received")
  local fed=bunnies(w)[1]; fed._food,fed._water,fed._hp=1,2,3
  local soup=C.registered_items[story.reward].on_use(ItemStack(story.reward),dad,{type="object",ref=fed.object})
  assert(soup:is_empty() and fed._food==100 and fed._water==100 and fed._hp==10,"magic soup restores a bunny")
  log("glowing Korean words make four sentences; following the recipe rewards restorative soup")

  if C.settings:get_bool("brickcraft_cycle_test_only",false) then
    cycle_regressions(w,dad); cycle_settings_regressions(w,dad); log("PASS"); return
  end
  if C.settings:get_bool("brickcraft_colony_test_only",false) then
    colony_regressions(w,dad); hutch_regressions(w,dad); log("PASS"); return
  end
  eagle_regressions(w,dad,bunnies(w)[1])
  if C.settings:get_bool("brickcraft_eagle_test_only",false) then log("PASS"); return end

  -- A hungry bunny goes and eats.
  local list=bunnies(w)
  local b=list[1]
  park(b,{x=patch.x+4,y=.5,z=patch.z}); b._food=20
  wait(20,function() return b._food>90 end,function() return "never ate: food "..math.floor(b._food) end)
  assert(C.get_meta(patch):get_int("units")==5,"a carrot eaten")
  log("a hungry bunny ate a carrot")

  -- Everyone else waits out of the way, inside a big pen on the far side.
  local pen={x=w.x+16,y=0,z=w.z-17}
  clear(pen,4,4)
  -- Two put down in the very same spot step apart instead of standing inside each other.
  local b2,b3=list[2],list[3]
  park(b2,{x=pen.x,y=.5,z=pen.z}); park(b3,{x=pen.x,y=.5,z=pen.z})
  local function gap() return H.flat(b2.object:get_pos(),b3.object:get_pos()) end
  wait(10,function() return gap()>=.44 end,function() return "still overlapping: "..string.format("%.2f",gap()) end)
  log(string.format("two bunnies in one spot stepped apart (%.2f)",gap()))
  for i=2,#list do park(list[i],{x=pen.x+(i%3)-1,y=.5,z=pen.z+math.floor(i/3)-1}) end
  ring(pen,3,2,true)

  -- A wolf in the open catches a bunny.
  local open={x=w.x-16,y=0,z=w.z-17}
  clear(open,4,4)
  park(b,{x=open.x,y=.5,z=open.z})
  local lost=st.lost or 0
  local wolf=C.add_entity({x=open.x+6,y=.5,z=open.z},"brickcraft_habitat:wolf"):get_luaentity()
  wait(30,function() return b._dead end,function() return "the wolf never caught the bunny (hp "..b._hp..")" end)
  assert(H.state(w).lost==lost+1,"lost counted")
  log("a wolf caught a bunny in the open")
  kill_hunters()

  -- A lion coming in over the north hills (trees, terraces, the statue) gets to a bunny.
  local lb=list[4]
  park(lb,{x=w.x,y=.5,z=w.z+20})
  local lion=H.spawn_predator(w,"lion",{angle=math.pi/2,n=1})
  local trace={}
  local t0=C.get_us_time()
  wait(60,function()
    local q=lion.object:get_pos()
    if q and (C.get_us_time()-t0)/1e6>#trace*3 then trace[#trace+1]=C.pos_to_string(vector.subtract(q,{x=w.x,y=0,z=w.z}),1) end
    return lb._dead or lb._hp<10
  end,function() return "the lion never reached the bunny: "..table.concat(trace," ") end)
  assert(lion._next_pounce,"the lion pounced")
  log("a lion from the north hills pounced on a bunny: "..table.concat(trace," "))
  kill_hunters()

  -- Behind a fence two bricks high it can't.
  local fenced=list[2]
  local yard={x=w.x-16,y=0,z=w.z-17}
  park(fenced,{x=yard.x,y=.5,z=yard.z})
  ring(yard,2,2,false)
  wolf=C.add_entity({x=yard.x+6,y=.5,z=yard.z},"brickcraft_habitat:wolf"):get_luaentity()
  sleep(12)
  assert(not fenced._dead and fenced._hp==10,"the fence kept the wolf out (hp "..fenced._hp..")")
  local wp=wolf.object:get_pos()
  assert(math.max(math.abs(wp.x-yard.x),math.abs(wp.z-yard.z))>2,"the wolf stayed outside: "..C.pos_to_string(vector.subtract(wp,yard),1))
  log("a fence two bricks high kept the wolf out")
  -- Punches chase it away.
  for _=1,6 do if not wolf._gone then wolf:_hit(dad,{dmg=1}) end end
  assert(wolf._gone and hunters()==0,"the wolf ran off")
  log("punches chased the wolf away")
  -- One that keeps pressing against the wall gives up and goes.
  local presser=C.add_entity({x=yard.x+4,y=.5,z=yard.z},"brickcraft_habitat:wolf"):get_luaentity()
  wait(40,function() return presser._gone or presser._caught>=2 end,function() return "it never gave up (pressed "..math.floor(presser._pressed or 0).." s)" end)
  log("a wolf pressing against the fence gave up")
  kill_hunters()
  -- A fence piece put down right on a wolf: it hops out, to the side away from the bunny.
  local wedged=C.add_entity({x=yard.x+3,y=-.45,z=yard.z},"brickcraft_habitat:wolf"):get_luaentity()
  sleep(.3)
  wedged.object:set_pos({x=yard.x+3,y=-.45,z=yard.z})
  C.set_node({x=yard.x+3,y=0,z=yard.z},{name="brickcraft_habitat:fence"})
  park(fenced,{x=yard.x,y=.5,z=yard.z})
  local function in_fence() local q=wedged.object:get_pos(); return C.get_item_group(C.get_node(vector.round(q)).name,"habitat_fence")>0 end
  wait(8,function() return not in_fence() end,function() return "the wolf stayed in the fence: "..C.pos_to_string(vector.subtract(wedged.object:get_pos(),yard),1) end)
  assert(wedged.object:get_pos().x>yard.x+2.4,"still outside the wall")
  log("a wolf with a fence put down on it got out of it, still outside")
  C.remove_node({x=yard.x+3,y=0,z=yard.z})
  kill_hunters()

  -- An eagle: the fenced bunny is in the open sky, so it's snatched...
  local eagle_ent=H.spawn_predator(w,"eagle")
  assert(eagle_ent,"an eagle")
  eagle_ent.object:set_pos({x=yard.x,y=16,z=yard.z+6})
  wait(40,function() return fenced._carried or fenced._dead end,function() return "the eagle never caught it" end)
  -- Hit while it carries the bunny off, it lets go.
  assert(fenced._carried and eagle_ent._carrying==fenced,"carried off")
  local carried_size=fenced.object:get_properties().visual_size
  local eagle_size=eagle_ent.object:get_properties().visual_size
  assert(math.abs(carried_size.x*eagle_size.x-10)<.001 and
    math.abs(carried_size.y*eagle_size.y-10)<.001,"carried bunny keeps its world size")
  eagle_ent:_hit(dad,{dmg=1})
  assert(not fenced._carried and not fenced._dead,"dropped")
  assert(fenced.object:get_properties().visual_size.x==10,"dropped bunny returns to its normal scale")
  sleep(2)
  assert(not fenced._dead and fenced.object:get_pos(),"the dropped bunny lives")
  log("an eagle carried a bunny off and dropped it when hit")
  -- Not hit, it carries one away for good.
  kill_hunters()
  local prey2=list[5]
  park(prey2,{x=yard.x,y=.5,z=yard.z})
  eagle_ent=H.spawn_predator(w,"eagle",{n=1})
  eagle_ent.object:set_pos({x=yard.x,y=16,z=yard.z+6})
  wait(40,function() return prey2._dead end,function() return "the eagle never carried it off" end)
  log("an eagle carried a bunny away")
  fenced=prey2 -- the next checks use a live bunny from here
  fenced=list[2]
  kill_hunters()
  -- ...but one under a roof isn't.
  local roofed=list[3]
  park(roofed,{x=yard.x,y=.5,z=yard.z})
  ring(yard,2,2,true)
  eagle_ent=H.spawn_predator(w,"eagle")
  eagle_ent.object:set_pos({x=yard.x,y=16,z=yard.z+6})
  sleep(12)
  assert(not roofed._dead,"the roof hid the bunny")
  log("a roof hid a bunny from the eagle")
  kill_hunters()


  -- A flood: low ground under water, a carrot patch on the ground spoiled, the sealed
  -- bunker dry; then it drains.
  local ok=H.start_disaster(w,"flood")
  assert(ok,"flood started")
  H.active[w.id].delay=0
  wait(25,function() return H.active[w.id] and H.active[w.id].data.level==2 end,function() return "flood didn't rise" end)
  assert(C.get_node({x=w.x+4,y=1,z=w.z-26}).name=="brickcraft_habitat:flood","open ground flooded")
  assert(C.get_node({x=yard.x,y=0,z=yard.z}).name=="air" and C.get_node({x=yard.x,y=1,z=yard.z}).name=="air","the bunker stays dry")
  assert(C.get_node({x=w.x+8,y=0,z=w.z+26}).name=="brickcraft_habitat:carrot_patch_empty","food on the ground spoiled")
  log("a flood rose; food on the ground spoiled, the sealed bunker stayed dry")
  H.stop_disaster(w)
  assert(C.get_node({x=w.x+4,y=1,z=w.z-26}).name=="air" and C.get_node({x=w.x+4,y=0,z=w.z-26}).name=="air","drained")
  log("the flood drained")

  -- Asteroids and an earthquake run and end.
  local meteors,boulders=0,0
  assert(H.start_disaster(w,"asteroids")); H.active[w.id].delay=0
  for _=1,30 do
    sleep(.2)
    for _,o in ipairs(C.get_objects_inside_radius({x=w.x,y=20,z=w.z},90)) do
      local e=o:get_luaentity(); if e and e.name=="brickcraft_habitat:meteor" then meteors=meteors+1 end
    end
  end
  assert(meteors>0,"asteroids fell")
  H.stop_disaster(w)
  assert(H.start_disaster(w,"earthquake")); H.active[w.id].delay=0
  for _=1,30 do
    sleep(.2)
    for _,o in ipairs(C.get_objects_inside_radius({x=w.x,y=10,z=w.z},90)) do
      local e=o:get_luaentity(); if e and e.name=="brickcraft_habitat:boulder" then boulders=boulders+1 end
    end
  end
  assert(boulders>0,"boulders rolled")
  H.stop_disaster(w)
  assert(not H.active[w.id],"over")
  log("asteroids fell and an earthquake rolled boulders")

  -- Skins and the panel's kit.
  assert(H.set_skin(dad,"snow"))
  assert(dad:get_properties().mesh=="brickcraft_habitat_bunny_person.obj","bunny skin on")
  sleep(1.5)
  assert(dad:get_properties().textures[1]=="brickcraft_habitat_skin_snow.png","still on")
  H.set_skin(dad,nil)
  assert(dad:get_properties().mesh~="brickcraft_habitat_bunny_person.obj","own look back")
  for _,f in ipairs(C.registered_on_player_receive_fields) do if f(dad,"brickcraft_habitat:panel",{kit="x"}) then break end end
  assert(brickcraft.count_of(dad,"brickcraft_habitat:carrot_patch")==4 and brickcraft.count_of(dad,"brickcraft_habitat:water_trough")==2,"the kit")
  log("a bunny skin went on and off; the kit gave food and water")
  -- The welcome: rules and settings. Calm makes predators come half as often.
  H.welcome(dad)
  for _,f in ipairs(C.registered_on_player_receive_fields) do if f(dad,"brickcraft_habitat:welcome",{pace_calm="x"}) then break end end
  assert(H.state(w).pace=="calm" and H.pace_of(H.state(w)).mult==2,"pace calm")
  for _,f in ipairs(C.registered_on_player_receive_fields) do if f(dad,"brickcraft_habitat:welcome",{wild="x"}) then break end end
  assert(H.state(w).wild==false,"predators off")
  for _,f in ipairs(C.registered_on_player_receive_fields) do if f(dad,"brickcraft_habitat:welcome",{go="x"}) then break end end
  log("the welcome screen explains the rules; its settings turn predators calm and off")

  -- Dad's own colony: 5 bunnies, his name on them; a second start is refused; hutches,
  -- food and water he places are his; a happy colony with room has a baby; the shop sells.
  local site={x=w.x+10,y=0,z=w.z-26}
  dad:set_pos(vector.offset(site,0,.5,0))
  sleep(.5)
  local ok2,msg=H.start_colony(dad)
  assert(ok2,msg)
  local mine=function() local n=0; for e in pairs(H.live) do if e._owner=="dad" and e.object:get_pos() then n=n+1 end end; return n end
  assert(mine()==5,"5 in the colony: "..mine())
  assert(not H.start_colony(dad),"only one colony at a time")
  assert(brickcraft.count_of(dad,"brickcraft_habitat:hutch")==2,"starter hutches")
  assert(brickcraft.count_of(dad,"brickcraft_habitat:fence")==32 and brickcraft.count_of(dad,"brickcraft_habitat:fence_gate")==1,"starter fence and gate")
  -- A colony from before the fence gets it the next time its owner is there.
  local cc=H.colony(w,"dad")
  cc.kit_given=nil
  brickcraft.take(dad,"brickcraft_habitat:fence 32"); brickcraft.take(dad,"brickcraft_habitat:fence_gate 1")
  wait(5,function() return brickcraft.count_of(dad,"brickcraft_habitat:fence")==32 end,function() return "no fence top-up" end)
  assert(brickcraft.count_of(dad,"brickcraft_habitat:hutch")==2,"no second hutches")
  for i,id in ipairs({"hutch","hutch","carrot_patch","carrot_patch","water_trough"}) do
    local q={x=site.x-3+i,y=0,z=site.z+3}
    C.set_node(q,{name="brickcraft_habitat:"..id}); H.claim(q,dad)
  end
  H.tally(w,true)
  local s=H.colony_status(w,H.variants.bunny,"dad")
  assert(s.pop==5 and s.cap==8 and s.happy>=60,"status "..s.pop.."/"..s.cap.." happy "..s.happy)
  local c=H.colony(w,"dad"); c.next_birth=0
  wait(10,function() return mine()==6 end,function() return "no baby: "..H.colony_status(w,H.variants.bunny,"dad").advice end)
  log("Dad's colony of 5 had a baby ("..s.happy.."% happy)")
  -- Herding: called, they follow Dad 8 blocks; told to stay, that's their home.
  assert(H.call(dad),"call")
  dad:set_pos(vector.offset(site,-8,.5,0))
  local near=function()
    local n=0
    for e in pairs(H.live) do local q=e.object:get_pos(); if e._owner=="dad" and q and H.flat(q,dad:get_pos())<3.5 then n=n+1 end end
    return n
  end
  wait(20,function() return near()>=5 end,function() return "only "..near().." followed" end)
  assert(H.stay(dad) and H.colony(w,"dad").home,"stay")
  for e in pairs(H.live) do assert(e._follow==nil,"still following") end
  log("called, "..near().." bunnies followed Dad; told to stay, that's their home")
  c.clovers=30
  assert(H.buy(dad,"hutch") and math.floor(c.clovers)<=5,"bought a hutch")
  assert(not H.buy(dad,"nursery"),"can't afford a nursery")
  H.colony_panel(dad)
  log("the colony shop sells hutches for clovers")

  -- What builders can do for a colony (brickcraft.assist): read it, fence it, herd it.
  local said={}
  local function say(t) said[#said+1]=t end
  local helper
  for _,h in ipairs(brickcraft.assist.helpers) do if h.name=="habitat" then helper=h end end
  assert(helper and helper.context(DAD):find("Their colony",1,true),"the builder sees the colony")
  assert(helper.step(DAD,"colony status",say,{is_owner=true}) and said[#said]:find("happy"),"status")
  local home=H.colony_home(w,"dad") -- its nearest hutch to where it was told to stay
  dad:set_pos(vector.offset(home,0,.5,-6))
  local fences=brickcraft.count_of(dad,"brickcraft_habitat:fence")
  assert(helper.step(DAD,"fence the colony",say,{is_owner=true}),"fence step")
  local used=fences-brickcraft.count_of(dad,"brickcraft_habitat:fence")
  local ring=#C.find_nodes_in_area(vector.offset(home,-4,-1,-4),vector.offset(home,4,2,4),{"group:habitat_fence"})
  assert(used>=20 and ring>=used,"fence ring: used "..used..", ring "..ring.." ("..said[#said]..")")
  log("asked, a builder put "..ring.." fence pieces round Dad's colony: "..said[#said])
  -- Herding: the bunnies follow the builder (here Dad stands in for it) home, through the gate.
  local stray={}
  for e in pairs(H.live) do if e._owner=="dad" and e.object:get_pos() then stray[#stray+1]=e end end
  local out=vector.offset(home,0,.5,-8)
  for i,e in ipairs(stray) do park(e,vector.offset(out,(i%3)-1,0,math.floor(i/3))) end
  dad:set_pos(vector.offset(out,0,0,-2))
  assert(helper.step(DAD,"herd the bunnies home",say,{is_owner=true,bot=dad,go=function() end}),"herd step")
  sleep(3)
  dad:set_pos(vector.offset(home,0,.5,0))
  wait(40,function()
    for _,e in ipairs(stray) do local q=e.object:get_pos(); if q and H.flat(q,home)>4 then return false end end
    return true
  end,function() local far=0; for _,e in ipairs(stray) do local q=e.object:get_pos(); if q and H.flat(q,home)>4 then far=far+1 end end; return far.." still outside" end)
  log("herded: "..#stray.." bunnies followed through the gate into the fence; "..said[#said])

  -- Clearing every brick: the workshop's arch and floor mosaic go (the floor turns to
  -- meadow); the statue and fences stay.
  assert(C.get_item_group(C.get_node({x=w.x+4,y=0,z=w.z-7}).name,"brick")>0,"the arch is there")
  local cleared
  H.clear_bricks(w,function(n) cleared=n end)
  wait(30,function() return cleared end,function() return "not cleared" end)
  assert(C.get_node({x=w.x+4,y=0,z=w.z-7}).name=="air","the arch went")
  assert(C.get_node({x=w.x,y=-1,z=w.z-6}).name=="brickcraft_habitat:meadow","the mosaic became meadow")
  assert(C.get_node({x=w.x,y=0,z=w.z+37}).name=="brickcraft_habitat:statue_gold","the statue stays")
  assert(cleared<2000,"only bricks, not the hills: "..cleared)
  assert(#C.find_nodes_in_area({x=w.x-46,y=-1,z=w.z-46},{x=w.x+46,y=10,z=w.z+46},{"brickcraft:grass"})>1000,"the hills stay")
  assert(#C.find_nodes_in_area(vector.offset(home,-4,-1,-4),vector.offset(home,4,2,4),{"group:habitat_fence"})>=20,"fences stay")
  log("cleared "..cleared.." bricks; statue and fences stay")

  -- Build and defend without stashing the building inventory or joining PvP.
  kill_hunters()
  local arena={x=w.x+22,y=0,z=w.z+12}
  clear(arena,6,8)
  dad:set_pos(vector.offset(arena,0,1,-4))
  H.defense_kit(dad)
  local inv=dad:get_inventory()
  local bricks=brickcraft.count_of(dad,"brickcraft:navy")
  assert(brickcraft.count_of(dad,"brickcraft:sword")==1,"defense sword provided")
  assert(brickcraft.count_of(dad,"brickcraft:bow")==1,"defense bow provided")
  assert(not brickcraft.war.start(dad),"Bunnyland keeps combined building and defense")
  assert(not brickcraft.war.on(dad) and inv:get_size("war_stash")==0,"no PvP or stash")
  assert(brickcraft.count_of(dad,"brickcraft:navy")==bricks,"building supplies kept")
  local wolf=H.spawn_predator(w,"wolf")
  wolf.on_step=function() end
  wolf.object:set_acceleration({x=0,y=0,z=0})
  wolf.object:set_velocity({x=0,y=0,z=0})
  wolf.object:set_pos(vector.offset(dad:get_pos(),0,0,2))
  local hp=wolf._hp
  C.registered_items["brickcraft:sword"].on_use(ItemStack("brickcraft:sword"),dad,{type="object",ref=wolf.object})
  assert(wolf._hp==hp-2,"sword works while building")
  assert(not brickcraft.war.hit(bunnies(w)[1].object,dad,"sword"),"defense cannot hurt bunnies")
  wolf.object:set_pos(vector.offset(dad:get_pos(),0,.8,5))
  wolf.object:set_velocity({x=0,y=0,z=0})
  dad:set_look_horizontal(0); dad:set_look_vertical(0)
  hp=wolf._hp
  assert(brickcraft.war.shoot_arrow(dad),"building player shoots an arrow")
  assert(not brickcraft.war.shoot_arrow(dad),"arrow cooldown applies")
  wait(4,function() return wolf._hp<hp end,function() return "arrow missed predator" end)
  kill_hunters()
  log("Sword and Bow work beside building supplies without war or friendly fire")

  -- A stocked feeder lures one cat, which drives a nearby wolf away.
  local feeder=vector.offset(arena,0,0,0)
  C.set_node(feeder,{name="brickcraft_habitat:cat_feeder"})
  local fd=C.registered_nodes["brickcraft_habitat:cat_feeder"]
  local tube=fd.on_rightclick(feeder,{},dad,ItemStack("brickcraft_habitat:churu 2"))
  assert(tube:get_count()==1,"stocking consumes one churu")
  fd.on_timer(feeder)
  local cat=H.cats[C.pos_to_string(feeder)]
  assert(cat,"stocked feeder lures a cat")
  fd.on_timer(feeder)
  assert(H.cats[C.pos_to_string(feeder)]==cat,"no duplicate guardian")
  wolf=H.spawn_predator(w,"wolf")
  wolf.on_step=function(self) self.object:set_velocity({x=0,y=0,z=0}) end
  wolf.object:set_pos(vector.offset(cat.object:get_pos(),0,0,1))
  wolf.object:set_acceleration({x=0,y=0,z=0}); wolf.object:set_velocity({x=0,y=0,z=0})
  wait(12,function() return wolf._gone end,function() return "cat did not repel wolf" end)
  C.get_meta(feeder):set_int("fed_until",0)
  fd.on_timer(feeder)
  assert(not H.cats[C.pos_to_string(feeder)],"cat leaves when churu runs out")
  tube=fd.on_rightclick(feeder,{},dad,tube)
  assert(tube:is_empty(),"refill consumes remaining tube")
  fd.on_timer(feeder)
  assert(H.cats[C.pos_to_string(feeder)],"refill lures another guardian")
  C.remove_node(feeder)
  assert(not H.cats[C.pos_to_string(feeder)],"removing feeder dismisses guardian")
  assert(H.buy(dad,"churu"),"churu available from colony shop")
  log("Churu feeders lure one guardian, repel wolves, expire, refill and clean up")

  -- A second variant from definitions only.
  local m
  brickcraft.make_world("Meadow test","dad",function(made) m=made end)
  wait(60,function() return m and m.built end,function() return "meadow world not built" end)
  H.make_habitat(m,"meadow")
  dad:set_pos({x=m.x,y=1,z=m.z+18})
  wait(40,function() return H.state(m).spawned and #bunnies(m)==3 end,function() return "meadow bunnies "..#bunnies(m) end)
  assert(C.get_node({x=m.x,y=0,z=m.z+26}).name=="brickcraft_habitat:carrot_patch","meadow's patch")
  log("a second habitat from definitions only got its own bunnies")
  dad:set_pos({x=w.x,y=1,z=w.z+18})
  sleep(3)
  log("PASS: Bunnyland keeps its bunnies safe")
  C.request_shutdown("BrickCraft habitat checked",false,1)
end

local started=false
C.register_on_joinplayer(function(player)
  C.after(2,function()
    if started or player:get_player_name()~=DAD then return end
    started=true
    co=coroutine.create(function() run(player) end)
    local ok,err=coroutine.resume(co)
    if not ok then error(err) end
  end)
end)
