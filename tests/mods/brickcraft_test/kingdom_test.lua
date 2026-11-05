-- Disposable real-engine regression checks for Bunny Kingdom, including live actors.
local C=core
local H=brickcraft.habitat
local K=H.kingdom
local co
local function log(s) C.log("action","BRICKCRAFT KINGDOM "..s) end
local function sleep(t)
  C.after(t,function() local ok,err=coroutine.resume(co); if not ok then error(err) end end)
  coroutine.yield()
end
local function wait(t,check,label)
  local deadline=H.now()+t
  while not check() do assert(H.now()<deadline,"Timed out: "..label); sleep(.2) end
end
local function actors(w,role)
  local list={}
  for e in pairs(K.actors) do if e._world==w.id and (not role or e._role==role) then list[#list+1]=e end end
  return list
end
local function cleanup(w,role)
  for _,e in ipairs(actors(w,role)) do e.object:remove() end
end
local function run(p)
  assert(K.enter(p))
  local w
  wait(65,function()
    w=H.world_at(p:get_pos()); return w and w.habitat=="kingdom" and H.state(w).built
  end,"kingdom setup")
  local s=K.state(w)
  local function pos(x,y,z) return {x=w.x+x,y=y,z=w.z+z} end
  wait(20,function() return K.count(w,"guard")==3 and K.count(w,"worker")==2 end,"blue roster")
  assert(H.cycle_config(w).lock_players==false,"kingdom stays playable at night")
  assert(H.cycle_config(w).predator_multiplier==0,"no unrelated predator packs")
  assert(C.get_node(pos(-8,2,12)).name=="brickcraft_habitat:castle_stone","castle wall: "..C.get_node(pos(-8,2,12)).name)
  assert(C.get_node(pos(-15,0,2)).name=="brickcraft_habitat:shop","shop")
  assert(C.get_node(pos(26,7,30)).name=="brickcraft_habitat:river","waterfall")
  assert(C.get_node(pos(0,20,33)).name=="brickcraft_habitat:statue_gold","king statue crown")
  assert(s.nights==0,"no free dawn credit on entry")
  log("castle, crowned statue, shop, farm, waterfall, unlocked cycle and blue roster")

  -- Gathering is spatial, replenishable, bounded, and cannot be spammed.
  p:set_pos(pos(-15,.1,-5))
  local before=s.food
  assert(K.gather(p,pos(-15,0,-6)))
  assert(s.food==before+4,"food increases")
  assert(not K.gather(p,pos(-15,0,-6)),"gather cooldown")
  assert(not K.gather(p,pos(26,-1,-6)),"distant gathering rejected")
  s.wood,s.stone,s.food,s.water=200,200,200,200
  p:set_pos(pos(0,.1,-10)); p:set_look_horizontal(0)
  assert(K.action(p,"tower")); assert(#s.towers==1,"tower tracked")
  p:set_pos(pos(5,.1,-10))
  assert(K.action(p,"wall")); assert(#s.walls==1,"wall tracked")
  local stone=s.stone
  s.wood=0; assert(not K.action(p,"tower")); assert(s.stone==stone,"failed purchase atomic")
  s.wood=200
  assert(K.action(p,"slinger")); assert(K.action(p,"bomber"))
  K.step(w,.5)
  assert(K.count(w,"guard","sling")==1 and K.count(w,"guard","acorn")==1,"ranged blue defenders")
  K.runtime[w.id].raid=999; K.runtime[w.id].disaster=999
  local worker=actors(w,"worker")[1]
  worker._destination=pos(-11,0,-8); worker._cargo=nil
  worker.object:set_pos(pos(-11,.1,-8)); worker._think=0
  worker:on_step(.3,{})
  assert(worker._cargo=="food","worker harvests a real patch")
  worker.object:set_pos(pos(0,.1,9)); worker._think=0
  local food=s.food
  worker:on_step(.3,{})
  assert(s.food==food+2 and not worker._cargo,"worker delivers food to keep")
  log("gather range/cooldown, paid construction, atomic shop, specialist recruits and worker deliveries")

  -- Towers shoot real enemies with line of sight, and normal sword code can hit them.
  cleanup(w,"guard")
  -- Temporarily park roster counts so the heartbeat doesn't restore it during a shot.
  s.guards,s.slingers,s.bombers=0,0,0
  local tower=s.towers[1]
  local obj=K.spawn(w,"enemy",vector.offset(tower,2,-2,0),false,"spear")
  local e=obj:get_luaentity()
  e.on_step=function() end; obj:set_acceleration({x=0,y=0,z=0}); obj:set_velocity({x=0,y=0,z=0})
  local hp=e._hp
  K.runtime[w.id].tower=1; K.step(w,.5)
  assert(e._hp<hp,"tower damages enemy")
  p:set_pos(vector.offset(obj:get_pos(),0,0,-2))
  hp=e._hp
  C.registered_items["brickcraft:sword"].on_use(ItemStack("brickcraft:sword"),p,{type="object",ref=obj})
  assert(e._hp<hp or e._gone,"normal sword hits kingdom enemy")
  cleanup(w,"enemy")
  log("tower fire and existing war sword work on kingdom enemies")

  -- Each themed weapon uses the same actual raycast/cooldown path as a left click.
  for _,id in ipairs({"carrot_lance","radish_hammer","berry_sling","acorn_launcher","cabbage_shield"}) do
    p:set_pos(pos(0,.1,-15)); p:set_look_horizontal(0); p:set_look_vertical(0)
    obj=K.spawn(w,"enemy",pos(0,.1,-13),false,"spear"); e=obj:get_luaentity()
    e.on_step=function() end; obj:set_acceleration({x=0,y=0,z=0})
    hp=e._hp
    assert(K.attack(p,id),id.." fires")
    assert(e._hp<hp or e._gone,id.." hits")
    assert(not K.attack(p,id),"cooldown applies")
    cleanup(w,"enemy"); sleep(1.9)
  end
  p:get_inventory():set_stack("main",p:get_wield_index(),"brickcraft_habitat:cabbage_shield")
  p:set_pos(pos(0,.1,9)); s.hp=100
  K.damage_castle(w,4); assert(s.hp==98,"shield blocks two damage near keep")
  p:get_inventory():set_stack("main",p:get_wield_index(),"brickcraft:separator")
  K.damage_castle(w,4); assert(s.hp==94,"without shield full damage lands")
  assert(K.action(p,"repair")); assert(s.hp==100,"repair caps castle HP")
  p:get_inventory():set_stack("main",p:get_wield_index(),"brickcraft_habitat:cabbage_shield")
  K.damage_castle(w,2,true); assert(s.hp==98,"shield cannot block supply shortages")
  p:get_inventory():set_stack("main",p:get_wield_index(),"brickcraft:separator")
  log("five themed weapons, cooldowns, shield protection and paid repairs")

  -- Enemy loadouts and actual melee/ranged combat against the keep.
  assert(K.wave(w,false)>0); local weapons={}
  for _,enemy in ipairs(actors(w,"enemy")) do weapons[enemy._weapon]=true end
  assert(weapons.spear and weapons.sling and weapons.acorn,"red army weapon choices")
  cleanup(w,"enemy")
  obj=K.spawn(w,"enemy",pos(0,.1,7),false,"spear"); e=obj:get_luaentity()
  s.hp=100
  wait(5,function() return s.hp<100 end,"red attacker damages castle")
  cleanup(w,"enemy")
  log("mixed red army loadouts and castle attack")

  -- Real clock transitions launch zombies, count dawns once, and end the round.
  H.state(w).cycle_start=H.clock.elapsed-151
  K.step(w,.5)
  assert(H.cycle_status(w).night and not H.actions_blocked(p),"night controls unlocked")
  assert(K.count(w,"enemy")>0,"night wave")
  for _,enemy in ipairs(actors(w,"enemy")) do assert(enemy._zombie,"night attackers are zombies") end
  cleanup(w,"enemy")
  for i=1,3 do
    H.state(w).cycle_start=H.clock.elapsed
    K.step(w,.5)
    assert(s.nights==i,"dawn credit")
    if i<3 then H.state(w).cycle_start=H.clock.elapsed-151; K.step(w,.5); cleanup(w,"enemy") end
  end
  assert(s.status=="won","three-night victory")
  assert(K.wave(w,false)==0,"finished games stop spawning")
  assert(K.action(p,"restart")); s=K.state(w)
  K.damage_castle(w,100); assert(s.status=="lost","castle defeat")
  assert(not K.action(p,"guard"),"no purchases after defeat")
  assert(K.action(p,"restart")); s=K.state(w)
  assert(s.status=="playing" and s.hp==100,"restart recovers kingdom")
  assert(H.start_disaster(w,"snow")); H.stop_disaster(w,true)
  assert(H.start_disaster(w,"tsunami")); H.stop_disaster(w,true)
  assert(H.start_disaster(w,"asteroids")); H.stop_disaster(w,true)
  H.save(w)
  local saved=C.deserialize(brickcraft.storage:get_string("habitat_"..w.id))
  assert(saved.kingdom.hp==100 and #saved.kingdom.towers==1,"economy and defenses serialized")
  log("zombie night, three dawns, victory, defeat, restart, disasters and saved state")
  log("PASS: Bunny Kingdom tower defense checked")
  if C.settings:get_bool("brickcraft_kingdom_preview",false) then
    p:set_pos(pos(0,15,-24)); p:set_velocity({x=0,y=0,z=0})
    p:set_physics_override({gravity=0})
    p:set_look_horizontal(0); p:set_look_vertical(.33)
    C.close_formspec(p:get_player_name(),"")
    C.after(50,function() C.request_shutdown("Bunny Kingdom preview complete",false,1) end)
  else C.request_shutdown("Bunny Kingdom verified",false,1) end
end
C.register_on_joinplayer(function(p)
  if p:get_player_name()~="HabitatDad" then return end
  C.after(3,function()
    co=coroutine.create(function() run(p) end)
    local ok,err=coroutine.resume(co); if not ok then error(err) end
  end)
end)
