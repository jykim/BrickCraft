-- Opt-in check (tools/test_siege.py): a dedicated server and one real client hold the Siege
-- Castle. The castle is built; a Red Army of 50 knights, a Commander and 4 red cannons comes
-- for a player in war there; only Red Army cannonballs crack (then break) the walls, only
-- others' knock siege towers apart; the bow and the castle's cannons (no cannonballs needed)
-- hit; builders put up siege towers; red knights get into the castle; knocking out the
-- Commander beats the army.
local C=core
local DAD="SiegeDad"
local W=brickcraft.war
local function log(msg) C.log("action","BRICKCRAFT SIEGE "..msg) end
local co
local function sleep(t) C.after(t,function() local ok,err=coroutine.resume(co); if not ok then error(err) end end); coroutine.yield() end
local function wait(limit,check,what)
  local start=C.get_us_time()
  while not check() do
    assert(C.get_us_time()-start<limit*1e6,"timed out: "..what())
    sleep(.1)
  end
end
local function node(w,x,y,z) return C.get_node({x=w.x+x,y=y,z=w.z+z}).name end

local function run(dad)
  for _,f in ipairs(C.registered_on_player_receive_fields) do if f(dad,"brickcraft:style",{style_dad="x"}) then break end end
  wait(60,function() local w=W.castle(); return w and w.castle_built end,function() return "Siege Castle not built" end)
  local w=W.castle()
  C.load_area({x=w.x-24,y=-4,z=w.z-24},{x=w.x+24,y=8,z=w.z+24})
  assert(node(w,0,3,10)=="brickcraft:castle_wall" and node(w,9,4,0)=="brickcraft:castle_wall","the walls")
  assert(node(w,0,1,-10)=="brickcraft:castle_gate" and node(w,0,3,-10)=="brickcraft:castle_wall","the gate in the south wall")
  assert(node(w,0,5,10)=="brickcraft:castle_wall" and node(w,1,5,10)=="air","battlements")
  assert(node(w,-7,0,8)=="brickcraft:castle_wall" and node(w,-3,4,8)=="brickcraft:castle_wall" and node(w,-7,1,8)=="air","stairs")
  assert(node(w,-14,0,11)=="air","the workshop's stacks are gone")
  assert(node(w,0,-2,14)=="brickcraft:water" and node(w,-14,-1,0)=="brickcraft:water" and node(w,0,-4,14)=="brickcraft:baseplate" and
    node(w,0,-1,-14)=="brickcraft:baseplate" and node(w,14,-1,0)=="brickcraft:baseplate","a moat on the north and west only")
  assert(node(w,0,6,6)=="brickcraft:castle_wall" and node(w,-6,6,-5)=="brickcraft:castle_wall" and node(w,6,6,-5)=="brickcraft:castle_wall","the keep and two inner towers")
  assert(node(w,4,2,-3)=="brickcraft:castle_wall" and node(w,4,3,-3)=="air" and node(w,-7,5,-3)=="brickcraft:castle_wall","stairs up the inner towers")
  local light=C.get_node_light({x=w.x,y=1,z=w.z+2},.5)
  assert(light and light>=10,"the courtyard is lit at noon, got "..tostring(light))
  log(("CASTLE: walls, battlements, a gate and stairs at %d,%d"):format(w.x,w.z))

  -- Dad goes to war in the castle; the Red Army comes.
  C.registered_chatcommands.war.func(DAD,"")
  local s=W.on(dad)
  dad:set_pos(brickcraft.home_pos(dad,w))
  local army,id
  wait(10,function() for i,a in pairs(W.armies) do if a.lab==w then army,id=a,i end end; return army end,function() return "no Red Army came" end)
  local knights,cannons=0,{}
  for ent in pairs(W._things()) do
    if ent._army==id and ent.name=="brickcraft:knight" and not ent._boss then knights=knights+1 end
    if ent._army==id and ent.name=="brickcraft:cannon" then cannons[#cannons+1]=ent end
  end
  assert(knights>=50 and #cannons==4 and army.boss._boss,("50 knights, a Commander, 4 cannons: %d knights, %d cannons"):format(knights,#cannons))
  log(("ARMY: a Red Commander, %d knights and %d red cannons"):format(knights,#cannons))
  local archers={}
  for ent in pairs(W._things()) do if ent._archer==w.id then archers[#archers+1]=ent end end
  assert(#archers==12,"12 castle archers, got "..#archers)
  -- The north wall's archer shoots a Red Knight held below it.
  local archer
  for _,a in ipairs(archers) do local q=a.object:get_pos(); if q.z-w.z<-9.5 and q.x-w.x<-5 then archer=a end end
  local red
  for ent in pairs(W._things()) do if ent._army==id and ent.name=="brickcraft:knight" and not ent._boss and not ent._build then red=ent end end
  local spot={x=archer.object:get_pos().x,y=-.5,z=w.z-15}
  local rhp=red._hp
  wait(15,function()
    red.object:set_pos(spot); red.object:set_velocity({x=0,y=0,z=0}); red._stun=C.get_us_time()/1e6+1
    return red._hp<rhp or red._down
  end,function() return "the archer never hit the Red Knight" end)
  log(("ARCHERS: 12 castle archers; one on the south wall shot a Red Knight below (%d/6)"):format(math.max(0,red._hp)))

  -- Only the Red Army's cannonballs crack the castle: a crack first, then a hole.
  -- (on a corner tower: the red cannons aim at people, the archers on the walls among them)
  local wall={x=w.x+11,y=1,z=w.z+11}
  local from,v={x=w.x+14,y=1,z=w.z+11},{x=-15,y=0,z=0}
  W.fire(from,v,nil,nil,"blue")
  sleep(.6); assert(C.get_node(wall).name=="brickcraft:castle_wall","blue doesn't break the castle")
  W.fire(from,v,nil,nil,"red")
  wait(2,function() return C.get_node(wall).name=="brickcraft:castle_wall_cracked" end,function() return "no crack: "..C.get_node(wall).name end)
  W.fire(from,v,nil,nil,"red")
  wait(2,function() return C.get_node(wall).name=="air" end,function() return "no hole: "..C.get_node(wall).name end)
  log("WALLS: a red cannonball cracked the wall, the next knocked it out; blue ones don't")
  local tower={x=w.x+20,y=0,z=w.z+20}
  C.set_node(tower,{name="brickcraft:siege_tower"})
  W.fire({x=w.x+20,y=.2,z=w.z+16},{x=0,y=0,z=15},nil,nil,"red")
  sleep(.6); assert(C.get_node(tower).name=="brickcraft:siege_tower","red doesn't break its siege tower")
  W.fire({x=w.x+20,y=.2,z=w.z+16},{x=0,y=0,z=15},nil,nil,"blue")
  wait(2,function() return C.get_node(tower).name=="air" end,function() return "siege tower still up" end)
  log("TOWERS: a blue cannonball knocked a siege tower block out; a red one doesn't")

  -- The bow: an arrow into a red knight right ahead.
  local function keep_up() s.hp,s.lives=W.max_hp,3 end
  local target
  for ent in pairs(W._things()) do if ent._army==id and ent.name=="brickcraft:knight" and not ent._boss and not ent._build then target=ent end end
  -- On the courtyard's flat ground, 4 apart, Dad aiming at its middle.
  dad:set_pos({x=w.x-4,y=-.5,z=w.z-3}); dad:set_look_horizontal(3*math.pi/2); dad:set_look_vertical(.13)
  sleep(.5)
  target.object:set_pos({x=w.x,y=-.5,z=w.z-3}); target.object:set_velocity({x=0,y=0,z=0}); target._stun=C.get_us_time()/1e6+3
  local hp=target._hp
  W.shoot_arrow(dad)
  wait(2,function() return target._hp<hp or target._down end,function() return "the arrow missed" end)
  log("BOW: an arrow hit a Red Knight")

  -- A castle cannon fires with no cannonballs of Dad's.
  keep_up(); dad:set_pos(vector.offset(brickcraft.home_pos(dad,w),0,0,0)); sleep(.5)
  local gun
  for ent in pairs(W._things()) do if ent._castle==w.id then gun=ent end end
  assert(gun,"castle cannons up")
  dad:set_pos(vector.offset(gun.object:get_pos(),-.0,.5,0)); s.ammo=0
  local before=0
  for _,o in ipairs(C.get_objects_inside_radius(gun.object:get_pos(),3)) do if o:get_luaentity() and o:get_luaentity().name=="brickcraft:cannonball" then before=before+1 end end
  gun:on_rightclick(dad)
  local after=0
  for _,o in ipairs(C.get_objects_inside_radius(gun.object:get_pos(),3)) do if o:get_luaentity() and o:get_luaentity().name=="brickcraft:cannonball" then after=after+1 end end
  assert(after>before and s.ammo==0,"the castle cannon fired without cannonballs")
  log("CASTLE CANNON: fired with no cannonballs")

  -- A red cannon: five sword strikes put it out.
  local rc=cannons[1]
  for _=1,5 do W.hit(rc.object,dad,"sword") end
  assert(not rc.object:get_pos(),"red cannon knocked out")
  log("RED CANNON: knocked out by Dad")

  -- The siege: Dad waits in the courtyard (his hearts kept up) while the army builds its
  -- towers and breaks in.
  dad:set_pos(brickcraft.home_pos(dad,w))
  local built,inside,on_wall=0,nil,nil
  local t0=C.get_us_time()
  wait(240,function()
    keep_up()
    if not W.armies[id] then error("the army left") end
    built=0
    for ent in pairs(W._things()) do
      local p=ent.object:get_pos()
      if p and ent._army==id and ent.name=="brickcraft:knight" and not ent._boss and not ent._down then
        local m=math.max(math.abs(p.x-w.x),math.abs(p.z-w.z))
        if m<8.5 and p.y<3 then inside=inside or (C.get_us_time()-t0)/1e6 end
        if p.y>3.8 and m<=11 then on_wall=on_wall or (C.get_us_time()-t0)/1e6 end
      end
    end
    for _,c in ipairs({{11,0,-7},{11,4,-3},{3,0,-11},{7,4,-11}}) do
      if node(w,c[1],c[2],c[3])=="brickcraft:siege_tower" then built=built+1 end
    end
    return inside and (on_wall or built>=1)
  end,function()
    return ("inside %s, on the wall %s, tower blocks %d"):format(tostring(inside),tostring(on_wall),built)
  end)
  log(("SIEGE: red knights in the courtyard after %.0f s%s; siege tower ends up: %d of 4"):format(inside,
    on_wall and (", on the walls after %.0f s"):format(on_wall) or "",built))

  -- Knock out the Commander and the army is beaten.
  for _=1,10 do W.hit(army.boss.object,dad,"sword") end
  assert(not W.armies[id],"beating the Commander beats the army")
  log("VICTORY: knocking out the Commander beat the Red Army")

  -- Dad's builder mends the castle when he says so.
  local holes={{x=w.x+2,y=1,z=w.z+9},{x=w.x+2,y=2,z=w.z+9},{x=w.x+3,y=1,z=w.z+9}} -- the north wall, by the moat
  C.set_node(holes[1],{name="air"}); C.set_node(holes[2],{name="air"}); C.set_node(holes[3],{name="brickcraft:castle_wall_cracked"})
  dad:set_pos({x=w.x,y=-.5,z=w.z+3})
  local heard={}
  assert(W.command(DAD,"Please fix the holes in the wall",function(t) heard[#heard+1]=t end) and heard[1]:find("On it"),"the fix order: "..tostring(heard[1]))
  wait(120,function()
    keep_up()
    for _,h in ipairs(holes) do if C.get_node(h).name~="brickcraft:castle_wall" then return false end end
    return true
  end,function() return ("not mended: %s %s %s, %d damaged blocks left"):format(C.get_node(holes[1]).name,C.get_node(holes[2]).name,
    C.get_node(holes[3]).name,#W.castle_damage(w)) end)
  log(("REPAIR: Dad's builder mended the holes and the crack he showed it (%d other damaged blocks to go)"):format(#W.castle_damage(w)))
  -- /resetcastle: new again, no Red Army there.
  C.set_node(holes[1],{name="air"})
  assert(C.registered_chatcommands.resetcastle.func(DAD,""),"/resetcastle")
  assert(#W.castle_damage(w)==0 and C.get_node(holes[1]).name=="brickcraft:castle_wall","the castle is whole")
  for _,a in pairs(W.armies) do assert(a.lab~=w,"no Red Army left in the castle") end
  log("RESET: /resetcastle put the castle back new and sent the Red Army away")
  -- A scene to look at: the next army coming, Dad on the north wall.
  sleep(17)
  dad:set_pos({x=w.x-4,y=4.5,z=w.z+9}); dad:set_look_horizontal(0); dad:set_look_vertical(.25)
  log("SCENE")
  sleep(14)
  log("PASS: the Siege Castle holds a siege")
  C.request_shutdown("BrickCraft siege checked",false,1)
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
