-- Opt-in check (tools/test_td.py): a dedicated server and one real client play Tower
-- Defense. The field is laid out (roads, pads, the castle's three gates and their doors,
-- the fork's lever); a game starts with someone there; towers built through the menu and
-- straight on fire at a wave and beat it; a barricade stops a knight until it's broken;
-- frost and tar slow, spikes hurt, Shield Knights take half an arrow; a knight at a gate
-- costs the castle hearts; the lever turns the north road; barracks call footmen; spells,
-- attacks and sending knights work, each from its own side; out of hearts the castle falls
-- and a new game starts on a fresh field.
local C=core
local DAD="TDDad"
local W=brickcraft.war
local TD=W.td
local function log(msg) C.log("action","BRICKCRAFT TD "..msg) end
local co
local function sleep(t) C.after(t,function() local ok,err=coroutine.resume(co); if not ok then error(err) end end); coroutine.yield() end
local function wait(limit,check,what)
  local start=C.get_us_time()
  while not check() do
    assert(C.get_us_time()-start<limit*1e6,"timed out: "..what())
    sleep(.1)
  end
end
local function t() return C.get_us_time()/1e6 end
local function node(w,x,y,z) return C.get_node({x=w.x+x,y=y,z=w.z+z}).name end
local function pad_near(g,x,z)
  local best,bd
  for k in pairs(TD.PAD) do
    local px,pz=k:match("^(-?%d+),(-?%d+)$")
    px,pz=tonumber(px),tonumber(pz)
    local d=(px-x)^2+(pz-z)^2
    if not g.towers[k] and (not bd or d<bd) then best,bd=k,d end
  end
  return best
end
local function fields(player,f)
  for _,fn in ipairs(C.registered_on_player_receive_fields) do if fn(player,"brickcraft:td",f) then return end end
end
-- An enemy put on the south road at x,z (relative), heading for waypoint wp.
local function enemy_at(g,kind,x,z,wp)
  local e=TD.spawn_enemy(g,"south",kind)
  e.object:set_pos({x=g.w.x+x,y=-.5,z=g.w.z+z}); e.object:set_velocity({x=0,y=0,z=0})
  e._wp=wp
  return e
end
local function gone(e) return not e.object:get_pos() or e._down end
local function clear(g) for _,e in ipairs(TD.enemies(g)) do W._things()[e]=nil; e.object:remove() end end

local function run(dad)
  for _,f in ipairs(C.registered_on_player_receive_fields) do if f(dad,"brickcraft:style",{style_dad="x"}) then break end end
  wait(90,function() local w=TD.world(); return w and w.td_built end,function() return "Tower Defense world not built" end)
  local w=TD.world()
  C.load_area({x=w.x-40,y=-2,z=w.z-40},{x=w.x+40,y=8,z=w.z+40})
  assert(node(w,0,-1,-18)=="brickcraft:td_road" and node(w,-34,-1,6)=="brickcraft:td_road" and node(w,0,-1,30)=="brickcraft:td_road","roads")
  assert(node(w,30,-1,-38)=="brickcraft:red_camp" and node(w,0,-1,38)=="brickcraft:red_camp","portals")
  assert(node(w,10,1,1)=="brickcraft:castle_gate" and node(w,-9,2,-1)=="brickcraft:castle_gate" and node(w,1,1,-10)=="brickcraft:castle_gate","three gates")
  assert(node(w,10,0,0)=="air" and node(w,-10,1,0)=="air" and node(w,0,0,-9)=="air" and node(w,0,2,-10)=="brickcraft:castle_gate","doors in them")
  assert(node(w,0,3,10)=="brickcraft:castle_wall" and node(w,0,9,7)=="brickcraft:castle_flag","the castle")
  assert(node(w,TD.LEVER.x,0,TD.LEVER.z)=="brickcraft:td_lever_west","the fork's lever")
  assert(node(w,30,3,30)=="air" and node(w,20,-1,-30)=="brickcraft:td_grass","the field is flat")
  local pads=0
  for _ in pairs(TD.PAD) do pads=pads+1 end
  assert(pads>=60,"pads: "..pads)
  log(("FIELD: 4 portals, 5 roads, %d gold pads, a castle with gates south, east and west at %d,%d"):format(pads,w.x,w.z))

  dad:set_pos(brickcraft.home_pos(dad,w))
  wait(10,function() return TD.games[w.id] end,function() return "no game started" end)
  local g=TD.games[w.id]
  assert(g.phase=="build" and g.gold==120 and g.hp==TD.castle_hp,"a new game: "..g.phase.." "..g.gold)
  local archers=0
  for ent in pairs(W._things()) do if ent._archer==w.id then archers=archers+1 end end
  assert(archers==8,"8 archers, got "..archers)
  log("GAME: a game started with someone there: 120 gold, 20 castle hearts, 8 archers")

  -- Through the menu, as a click would: a Frost Tower on the pad by the south road's
  -- middle stretch.
  local k=pad_near(g,8,-22)
  local px,pz=k:match("^(-?%d+),(-?%d+)$")
  local pad={x=w.x+tonumber(px),y=-1,z=w.z+tonumber(pz)}
  assert(TD.menu(dad,pad),"the pad's menu")
  fields(dad,{tower_frost="Frost"})
  assert(g.towers[k] and g.towers[k].kind=="frost" and g.gold==60 and C.get_node(vector.offset(pad,0,2,0)).name=="brickcraft:td_top_frost",
    "a frost tower from the menu: "..g.gold)
  -- Its menu again: upgrade.
  g.gold=500
  assert(TD.menu(dad,vector.offset(pad,0,1,0)),"the tower's menu")
  fields(dad,{upgrade="Up"})
  assert(g.towers[k].level==2 and g.gold==440 and C.get_node(vector.offset(pad,0,3,0)).name=="brickcraft:td_top_frost","upgraded: "..g.gold)
  log("MENU: a Frost Tower built from the pad's menu, then upgraded to level 2 from its own")
  -- Arrow and cannon towers along the south road.
  for _,at in ipairs({{26,-30},{0,-30},{-20,-30},{16,-22},{-10,-22},{12,-14}}) do
    assert(TD.build_tower(g,pad_near(g,at[1],at[2]),"arrow",DAD),"arrow tower at "..at[1]..","..at[2])
  end
  assert(TD.build_tower(g,pad_near(g,4,-22),"cannon",DAD),"cannon tower")
  log(("TOWERS: 6 arrow towers and a cannon tower on the south road; %d gold left"):format(g.gold))

  -- Wave 1, called early: it walks the south road and is beaten.
  local before=g.gold
  fields(dad,{next="x"}) -- (no menu open: does nothing)
  assert(C.registered_chatcommands.td.func(DAD,"next"),"/td next")
  local wave_t=t()
  local walker
  wait(10,function() walker=TD.enemies(g)[1]; return walker end,function() return "no knight came" end)
  wait(15,function() return gone(walker) or walker._wp>=4 end,function() return "it didn't walk the road: waypoint "..walker._wp end)
  wait(90,function() return g.phase=="build" and g.wave==1 end,function() return ("wave 1: %s, %d enemies, %d queued"):format(g.phase,#TD.enemies(g),#g.queue) end)
  assert(g.gold>before,"gold for knockouts and the wave")
  log(("WAVE 1: 3 knights walked the south road; beaten in %.0f s, castle %d/20, gold %d -> %d"):format(t()-wave_t,g.hp,before,g.gold))

  -- Barricade: a knight stops at it and breaks it.
  g.next=t()+999
  for k2,_ in pairs(g.towers) do g.towers[k2].stun=t()+999 end -- (towers out, to watch)
  assert(TD.road_work(g,"-20,-18","barricade",DAD)==false,"no road there")
  assert(TD.road_work(g,"6,-18","barricade",DAD),"a barricade")
  assert(node(w,6,1,-19)=="brickcraft:td_barricade" and node(w,6,0,-17)=="brickcraft:td_barricade","across the road")
  local e=enemy_at(g,"red",12,-18,7)
  wait(15,function() local b=g.bars["6,-18"] or g.bars["6,-19"] or g.bars["6,-17"]; return not b or b.hp<12 end,function() return "not battered: "..tostring(e.object:get_pos() and e.object:get_pos().x-w.x) end)
  assert(e.object:get_pos().x-w.x>6,"held by the barricade")
  wait(60,function() return gone(e) or e.object:get_pos().x-w.x<5 end,function() return "never got through" end)
  log("BARRICADE: a knight stopped at it, broke it and went on")
  clear(g)

  -- Frost slows; tar slows; spikes hurt; arrows hurt a Shield Knight half as much.
  for k2,_ in pairs(g.towers) do g.towers[k2].stun=nil end
  local f=g.towers[k]
  e=enemy_at(g,"shield",f.x,-26,5)
  wait(5,function() return (e._slow or 0)>t() and e._slow_k<1 end,function() return "not slowed by frost" end)
  log(("FROST: a Shield Knight by the Frost Tower walks at %.0f%%"):format(e._slow_k*100))
  local hp=e._hp
  W.hit(e.object,nil,"arrow",{x=1,y=0,z=0},"blue")
  assert(hp-e._hp==1,"an arrow takes 1 off a Shield Knight, took "..(hp-e._hp))
  clear(g)
  assert(TD.road_work(g,"14,-26","spikes",DAD) and TD.road_work(g,"18,-26","tar",DAD),"spikes and tar")
  for k2,_ in pairs(g.towers) do g.towers[k2].stun=t()+999 end
  e=enemy_at(g,"red",10,-26,5)
  hp=e._hp
  wait(10,function() return e._hp<hp or gone(e) end,function() return "the spikes didn't spring" end)
  log(("ARMOR, SPIKES: an arrow took 1 off a Shield Knight; a knight on spikes went %d -> %d"):format(hp,math.max(0,e._hp)))
  clear(g)
  e=enemy_at(g,"scout",16,-26,5)
  wait(5,function() return (e._slow or 0)>t() end,function() return "the tar didn't slow it" end)
  log("TAR: a scout in the tar was slowed")
  clear(g)

  -- At the gate: the castle loses hearts.
  e=enemy_at(g,"shield",0,-14,8)
  wait(10,function() return g.hp==TD.castle_hp-2 end,function() return "no leak: "..g.hp end)
  log("GATE: a Shield Knight got to the south gate: castle 18/20")

  -- The lever sends the north road the other way.
  local n1=TD.spawn_enemy(g,"north","red")
  assert(n1._lane[3].x<w.x,"north goes west first")
  assert(TD.menu(dad,{x=w.x+TD.LEVER.x,y=0,z=w.z+TD.LEVER.z}) and g.fork=="east" and node(w,TD.LEVER.x,0,TD.LEVER.z)=="brickcraft:td_lever_east","the lever")
  local n2=TD.spawn_enemy(g,"north","red")
  assert(n2._lane[3].x>w.x,"and then east")
  clear(g)
  log("LEVER: right clicking the lever turned the north road from west to east")

  -- Barracks: footmen at the road, and they stop a knight.
  local bk=pad_near(g,20,-14)
  assert(TD.build_tower(g,bk,"barracks",DAD),"barracks")
  g.towers[bk].t=0
  wait(5,function() return #g.towers[bk].men>=1 end,function() return "no footmen" end)
  local man=g.towers[bk].men[1]
  e=enemy_at(g,"red",man.object:get_pos().x-w.x+4,-18,7)
  wait(20,function() return gone(e) or (e._hp<e._max) end,function() return "the footman didn't fight" end)
  log("BARRACKS: a footman came to the road and fought a knight")
  clear(g)

  -- Spells (a defender's), then Dad switches to attacking: sends and attacks.
  g.gold=500
  local rain=TD.spawn_enemy(g,"south","red")
  hp=rain._hp
  assert(TD.cast(g,"rain",DAD,"south"),"arrow rain")
  wait(3,function() return rain._hp<hp or gone(rain) end,function() return "the rain missed" end)
  local was=g.hp
  assert(TD.cast(g,"ice",DAD) and (rain._slow or 0)>t() or gone(rain),"ice storm")
  assert(TD.cast(g,"mend",DAD) and g.hp==math.min(TD.castle_hp,was+3),"mend")
  assert(not TD.cast(g,"rain",DAD,"south"),"arrow rain needs to wait")
  assert(TD.cast(g,"help",DAD,"west"),"reinforcements")
  log(("SPELLS: Arrow Rain hit a knight on the south road, Ice Storm, Mend (castle %d/20), Reinforcements on the west road"):format(g.hp))
  clear(g)
  C.registered_chatcommands.war.func(DAD,"")
  assert(C.registered_chatcommands.td.func(DAD,""),"/td opens the panel")
  fields(dad,{switch="x"})
  assert(TD.sides[DAD]=="attack","attacking now")
  wait(3,function() return W.on(dad).team=="red" end,function() return "not on the red team: "..W.on(dad).team end)
  g.chest=400
  g.wave=2
  local chest=g.chest
  fields(dad,{road="West"}) -- the dropdown
  fields(dad,{send_shield="x"})
  fields(dad,{send_ram="x"})
  assert(g.chest==chest-55 and #g.queue==2,"sent: "..g.chest.." "..#g.queue)
  wait(4,function() return #TD.enemies(g)==2 end,function() return "they didn't come" end)
  for _,en in ipairs(TD.enemies(g)) do assert(en._road=="west","on the west road") end
  assert(TD.attack(g,"drums",DAD) and TD.enemies(g)[1]._slow_k==1.5,"war drums")
  assert(TD.attack(g,"catapult",DAD),"catapult")
  local stunned=0
  for _,tw in pairs(g.towers) do if (tw.stun or 0)>t() then stunned=stunned+1 end end
  assert(stunned>=1,"a tower out")
  assert(TD.attack(g,"sappers",DAD,"south") and node(w,14,-1,-26)=="brickcraft:td_road","sappers cleared the spikes")
  assert(TD.attack(g,"banner",DAD),"banner")
  log("ATTACK: as an attacker on the red team, Dad sent a Shield Knight and a Ram down the west road, beat the War Drums, threw a catapult stone, sent sappers and raised the banner")
  fields(dad,{switch="x"})
  wait(3,function() return W.on(dad).team=="blue" end,function() return "not back on blue" end)
  clear(g)

  -- Out of hearts, the castle falls; a new game starts on a fresh field.
  g.hp=1
  enemy_at(g,"red",0,-14,8)
  wait(10,function() return g.phase=="over" end,function() return "the castle didn't fall: "..g.hp end)
  log("FALL: the last heart lost, the castle fell")
  g.next=t()
  wait(5,function() return TD.games[w.id]~=g end,function() return "no new game" end)
  g=TD.games[w.id]
  assert(g.gold==120 and next(g.towers)==nil and C.get_node(vector.offset(pad,0,1,0)).name=="air" and node(w,6,0,-18)=="air","a fresh field")
  log("NEW GAME: towers, barricades and traps gone, 120 gold again")

  -- A scene: Dad on the south wall over the roads.
  dad:set_pos({x=w.x-3,y=4.5,z=w.z-9}); dad:set_look_horizontal(math.pi); dad:set_look_vertical(.35)
  sleep(6)
  log("PASS: Tower Defense plays")
  C.request_shutdown("BrickCraft tower defense checked",false,1)
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
