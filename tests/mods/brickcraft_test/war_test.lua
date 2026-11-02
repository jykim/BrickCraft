-- Opt-in check (tools/test_war.py): a dedicated server and two real clients play war.
-- Sword, kick, shove and cannon land on a player in war (and not on one who isn't), push
-- them as their own client moves them, knock them out home; the Brick Knight falls and gets
-- up; leaving war (or switching player mid-war) gives every brick back.
local C=core
local DAD,KID="WarDad","WarLeona"
local W=brickcraft.war
local function log(msg) C.log("action","BRICKCRAFT WAR "..msg) end
local function form(player,formname,fields)
  for _,handler in ipairs(C.registered_on_player_receive_fields) do
    if handler(player,formname,fields) then return end
  end
end
local function items(inv,list)
  local out={}
  for i,stack in ipairs(inv:get_list(list)) do out[i]=stack:to_string() end
  return table.concat(out,"|")
end
-- The steps run in a coroutine; sleep(t) waits t seconds of game time.
local co
local function sleep(t) C.after(t,function() local ok,err=coroutine.resume(co); if not ok then error(err) end end); coroutine.yield() end
local function wait(limit,check,what)
  local start=C.get_us_time()
  while not check() do
    assert(C.get_us_time()-start<limit*1e6,"timed out: "..what())
    sleep(.05)
  end
end
local function face(p,yaw) p:set_look_horizontal(yaw); p:set_look_vertical(0) end
local EAST,WEST=3*math.pi/2,math.pi/2 -- looking toward +x, -x
local function flat(a,b) return math.sqrt((a.x-b.x)^2+(a.z-b.z)^2) end

local function run(dad,kid)
  form(dad,"brickcraft:style",{style_dad="x"}); form(kid,"brickcraft:style",{style_daughter="x"})
  local dinv,kinv=dad:get_inventory(),kid:get_inventory()
  local dad_bricks,kid_bricks=items(dinv,"main"),items(kinv,"main")
  local war=C.registered_chatcommands.war.func

  -- Dad goes to war: the kit in his hotbar, his bricks put away.
  war(DAD,"")
  assert(dinv:get_stack("main",1):get_name()=="brickcraft:sword" and dinv:get_stack("main",4):get_name()=="brickcraft:knight","war kit in the hotbar")
  assert(items(dinv,"war_stash")==dad_bricks,"bricks wait in the stash")
  local sword=dinv:get_stack("main",1)
  local function strike(target) return sword:get_definition().on_use(sword,dad,{type="object",ref=target}) end
  local function kick(target)
    local boot=dinv:get_stack("main",3)
    boot:get_definition().on_use(boot,dad,{type="object",ref=target})
  end
  local function shove(target)
    for _,f in ipairs(C.registered_on_rightclickplayers) do f(target,dad) end
  end
  local function hp(p) return W.on(p) and W.on(p).hp end

  dad:set_pos({x=-5,y=0,z=-2}); kid:set_pos({x=-3.5,y=0,z=-2}); face(dad,EAST); face(kid,WEST)
  sleep(3.2) -- the joining shield
  strike(kid)
  assert(kid:get_pos().x<-3.4 and not W.on(kid),"Leona isn't in war: the sword does nothing")
  log("PEACE: a player not in war can't be hit")

  war(KID,"")
  assert(kinv:get_stack("main",2):get_name()=="brickcraft:cannon","Leona has the kit")
  sleep(3.2)
  local function knocked(what,from,check)
    wait(3,function() return check(kid:get_pos()) end,function() return what.." moved Leona from "..C.pos_to_string(from,1).." to "..C.pos_to_string(kid:get_pos(),1) end)
  end
  local from=kid:get_pos()
  strike(kid)
  assert(hp(kid)==8,"sword: 1 heart, got "..hp(kid))
  knocked("sword",from,function(p) return p.x-from.x>.8 end)
  log(("SWORD: Leona 8/10, pushed %.1f nodes by her own client"):format(flat(kid:get_pos(),from)))
  strike(kid); assert(hp(kid)==8,"the sword has a cooldown")

  sleep(1.2)
  dad:set_pos({x=-5,y=0,z=-2}); kid:set_pos({x=-3.5,y=0,z=-2}); sleep(.6)
  from=kid:get_pos()
  local high=from.y
  kick(kid)
  assert(hp(kid)==7,"kick: half a heart")
  wait(3,function() high=math.max(high,kid:get_pos().y); return high-from.y>.8 and kid:get_pos().x-from.x>2 end,
    function() return ("kick: up %.1f, along %.1f"):format(high-from.y,kid:get_pos().x-from.x) end)
  log(("KICK: Leona 7/10, flew %.1f up and %.1f away"):format(high-from.y,kid:get_pos().x-from.x))

  -- The kick's flight has to be over: a teleport right after can swallow the shove.
  sleep(1.5)
  dad:set_pos({x=-5,y=0,z=-2}); kid:set_pos({x=-3.5,y=0,z=-2}); sleep(1)
  from=kid:get_pos()
  shove(kid)
  assert(hp(kid)==7,"a shove doesn't hurt")
  knocked("shove",from,function(p) return p.x-from.x>1.2 end)
  log(("SHOVE: pushed %.1f nodes, still 7/10"):format(kid:get_pos().x-from.x))

  -- A cannon behind Dad fires past him (the shooter) at Leona.
  local cannon_item=dinv:get_stack("main",2)
  cannon_item:get_definition().on_place(cannon_item,dad,{type="node",under={x=-7,y=-1,z=-2},above={x=-7,y=0,z=-2}})
  local cannon
  for _,o in ipairs(C.get_objects_inside_radius({x=-7,y=-.5,z=-2},.6)) do
    if o:get_luaentity() and o:get_luaentity().name=="brickcraft:cannon" then cannon=o:get_luaentity() end
  end
  assert(cannon and cannon._owner==DAD,"cannon set up")
  sleep(1)
  dad:set_pos({x=-5.5,y=0,z=-2.6}); kid:set_pos({x=0,y=0,z=-2}); face(kid,WEST); sleep(.6)
  face(dad,EAST)
  local dad_hp=hp(dad)
  cannon:on_rightclick(dad)
  wait(3,function() return hp(kid)<7 end,function() return "cannonball didn't reach Leona" end)
  assert(hp(kid)==4 and hp(dad)==dad_hp,"cannon: 1½ hearts to Leona, none to Dad, got "..hp(kid))
  log("CANNON: a cannonball flew past Dad and hit Leona, 4/10")

  -- Two more strikes knock her out: home, full hearts, shielded; Dad scores.
  sleep(.5); strike(kid); sleep(.5)
  strike(kid)
  assert(hp(kid)==10 and W.on(dad).kos==1,"knocked out with full hearts again, Dad has 1 knockout")
  local home=brickcraft.home_pos(kid)
  wait(3,function() return flat(kid:get_pos(),home)<.6 end,function() return "Leona not home" end)
  dad:set_pos(vector.offset(home,-1.5,0,0)); face(dad,EAST); sleep(.6)
  strike(kid)
  assert(hp(kid)==10,"the shield after a knockout")
  log("KNOCKOUT: Leona back at her start spot with 10/10, shielded")
  -- Low on hearts she is slow and pale; three knockouts and her war is over.
  local ks=W.on(kid)
  assert(ks.lives==2,"2 lives left after a knockout, got "..ks.lives)
  ks.shield,ks.hp=0,4; sleep(.5); strike(kid)
  assert(hp(kid)==2 and kid:get_physics_override().speed<1 and kid:get_properties().textures[1]:find("colorize"),"hurt: slow and pale")
  for _=1,2 do W.on(kid).shield,W.on(kid).hp=0,1; sleep(.5); strike(kid) end
  assert(not W.on(kid) and items(kinv,"main")==kid_bricks,"out of lives: out of the war, bricks back")
  assert(kid:get_physics_override().speed==1 and not kid:get_properties().textures[1]:find("colorize"),"herself again out of war")
  war(KID,""); assert(W.on(kid).lives==3,"back in with 3 lives")
  log("LIVES: hurt Leona went slow and pale; her third knockout ended her war; back in with 3 lives")

  -- A cannonball nobody fired hits Dad.
  dad:set_pos({x=-5,y=0,z=-2}); sleep(.6)
  W.fire({x=-9,y=0,z=-2},{x=14,y=1,z=0})
  wait(3,function() return hp(dad)==dad_hp-3 end,function() return "stray ball: Dad "..hp(dad) end)
  log("STRAY: a cannonball with no shooter hits too")

  -- A practice knight (War Lab's): five sword strikes knock it down; it gets up at its spot.
  local knight=W.spawn_knight({x=-3,y=0,z=-5},nil)
  assert(knight and knight._hp==10,"practice knight put up")
  dad:set_pos({x=-5,y=0,z=-5}); sleep(1.2)
  local kos=W.on(dad).kos
  for i=1,5 do
    local was=knight.object:get_pos()
    strike(knight.object)
    if i==1 then
      local d=dad:get_pos()
      sleep(.3)
      assert(flat(knight.object:get_pos(),d)>flat(was,d)+.2,"the knight is pushed away from Dad")
    end
    knight.object:set_pos(knight._home); sleep(.45)
  end
  assert(knight._down and W.on(dad).kos==kos+1,"knight down, a knockout for Dad")
  sleep(3.3)
  assert(not knight._down and knight._hp==10,"knight back up with full hearts")
  knight.object:remove()
  log("KNIGHT: practice knight down after 5 strikes, back up 3 s later")

  -- Cannonballs: firing from your hands uses one; none left, no shot; a pile gives 3.
  local s=W.on(dad)
  local cannon_tool=dinv:get_stack("main",2)
  local function hand_fire() cannon_tool:get_definition().on_use(cannon_tool,dad,{type="nothing"}) end
  dad:set_pos({x=-5,y=0,z=-8}); face(dad,EAST); sleep(.9)
  local ammo=s.ammo
  hand_fire()
  assert(s.ammo==ammo-1,"a shot from the hands uses a cannonball")
  sleep(.9)
  -- Looking at the ground a few blocks ahead, the shot still flies off in an arc.
  dad:set_look_vertical(.5); sleep(.3)
  local ball=W.fire_from(dad)
  assert(ball,"fired looking down")
  local start,far=dad:get_pos(),0
  wait(4,function()
    local q=ball:get_pos()
    if q then far=math.max(far,flat(q,start)) end
    return not q
  end,function() return "ball still flying" end)
  assert(far>6,("looking down, the ball still flies (%.1f blocks)"):format(far))
  face(dad,EAST)
  ammo=s.ammo+1
  sleep(.9)
  s.ammo=0; hand_fire()
  assert(s.ammo==0,"no cannonballs, no shot")
  W.drop_ammo(dad:get_pos())
  wait(3,function() return s.ammo>=3 end,function() return "pile not picked up: "..s.ammo end)
  log(("AMMO: hand cannon fired, even looking down (flew %.0f blocks), empty refuses, a pile picked up gives %d"):format(far,s.ammo))

  -- Dad's blue knight fights a Red Knight (away from the players).
  local kn_item=dinv:get_stack("main",4)
  kn_item:get_definition().on_place(kn_item,dad,{type="node",under={x=14,y=-1,z=-14},above={x=14,y=0,z=-14}})
  local blue
  for ent in pairs(brickcraft.war._things()) do if ent._team=="blue" and ent._owner==DAD then blue=ent end end
  assert(blue and blue._hp==10,"a blue knight for Dad")
  strike(blue.object); assert(blue._hp==10,"Dad can't hurt his own knight")
  local red=W.spawn_knight({x=19,y=0,z=-14},"red")
  assert(red._hp==6 and red._name=="Red Knight","a red knight")
  wait(15,function() return red._hp<6 end,function() return ("red untouched: blue at %s, red at %s"):format(
    C.pos_to_string(blue.object:get_pos(),1),C.pos_to_string(red.object:get_pos(),1)) end)
  log(("ALLY: Dad's blue knight walked up and hit the Red Knight (%d/6)"):format(red._hp))
  red.object:remove()
  -- Left click with the Knight tool takes it back.
  kn_item:get_definition().on_use(kn_item,dad,{type="object",ref=blue.object})
  assert(not blue.object:get_pos(),"Dad took his knight back")

  -- A Red Knight goes for a player in war.
  kid:set_pos({x=8,y=0,z=-14}); sleep(3.3)
  local khp=W.on(kid).hp
  red=W.spawn_knight({x=12,y=0,z=-14},"red")
  wait(15,function() return W.on(kid).hp<khp end,function() return "red knight never hit Leona, at "..C.pos_to_string(red.object:get_pos() or {x=0,y=0,z=0},1) end)
  log(("RED: a Red Knight charged and hit Leona (%d/10)"):format(W.on(kid).hp))
  red.object:remove()

  -- /battle: a Commander and 4 knights. Knock out the Commander and the army falls.
  kid:set_pos(brickcraft.home_pos(kid)); sleep(.5)
  dad:set_pos({x=0,y=0,z=-14}); face(dad,EAST); sleep(.8)
  local ok=C.registered_chatcommands.battle.func(DAD,"")
  assert(ok,"battle called")
  local id,army=next(W.armies)
  assert(army and army.boss._boss and army.boss._hp==20,"a Red Commander with 20 hearts")
  local members=0
  for ent in pairs(brickcraft.war._things()) do if ent._army==id then members=members+1 end end
  assert(members==5,"a Commander and 4 knights, got "..members)
  -- It lobs cannonballs at Dad within a few seconds.
  local dhp=s.hp
  wait(12,function() return s.hp<dhp end,function() return "the Commander never hit Dad" end)
  log(("ARMY: Red Commander and 4 knights; the Commander's cannonball hit Dad (%d/10)"):format(s.hp))
  for _=1,10 do W.hit(army.boss.object,dad,"sword") end
  assert(not W.armies[id] and W.on(dad).kos>=3,"beating the Commander beats the army")
  sleep(2.5)
  local left=0
  for ent in pairs(brickcraft.war._things()) do if ent._army==id and ent.object:get_pos() then left=left+1 end end
  assert(left==0,"the whole army is gone, "..left.." left")
  log("VICTORY: knocking out the Commander beat the Red Army")

  -- Orders. Dad's AI builder ("Dad bot") is his commander in war mode.
  local heard={}
  local function said(t) heard[#heard+1]=t end
  dad:set_pos({x=0,y=0,z=-14}); sleep(.5)
  -- An order with no knights calls a squad up first.
  assert(W.command(DAD,"protect me",said),"guard order")
  assert(W.orders(DAD).mode=="guard" and heard[#heard]:find("4 knights came"),"guard order brought knights: "..heard[#heard])
  local mine={}
  for ent in pairs(brickcraft.war._things()) do if ent._team=="blue" and ent._owner==DAD then mine[#mine+1]=ent end end
  assert(#mine==4,"4 blue knights came with the order, got "..#mine)
  assert(W.command(DAD,"more knights",said) and heard[#heard]:find("already have"),"no more than 4 knights")
  local function tell_bot(words)
    for _,f in ipairs(C.registered_on_chat_messages) do f(DAD,"Dad bot, "..words) end
    sleep(.6)
  end
  tell_bot("attack the commander from the right")
  local o=W.orders(DAD)
  assert(o and o.mode=="flank" and o.target=="commander" and o.side=="right","Dad bot took the flank order: "..(o and o.mode or "none"))
  tell_bot("hold your ground")
  assert(W.orders(DAD).mode=="hold","hold order")
  sleep(1)
  local spots={}
  for i,k in ipairs(mine) do spots[i]=k.object:get_pos() end
  dad:set_pos({x=10,y=0,z=-14}); sleep(3)
  for i,k in ipairs(mine) do assert(flat(k.object:get_pos(),spots[i])<2,"knight "..i.." holds its spot") end
  tell_bot("retreat!")
  assert(W.orders(DAD).mode=="retreat","retreat order")
  wait(10,function()
    for _,k in ipairs(mine) do if flat(k.object:get_pos(),dad:get_pos())>3.5 then return false end end
    return true
  end,function() return "knights didn't fall back to Dad" end)
  log("ORDERS: Dad bot took orders (flank right on the commander, hold, retreat); knights held, then fell back to Dad")
  -- The Red Commander plans for its army (built-in tactics here: brickcraft_war_ai off).
  local rid
  ok=C.registered_chatcommands.battle.func(DAD,""); assert(ok,"second battle")
  for id in pairs(W.armies) do rid=id end
  local first=W.armies[rid].order.mode
  wait(20,function() return (W.armies[rid].plan_n or 0)>=1 end,function() return "the Red Commander never planned" end)
  log(("RED PLAN: the Red Commander changed its order from %s to %s%s"):format(first,W.armies[rid].order.mode,
    W.armies[rid].order.mode=="flank" and " "..W.armies[rid].order.side or ""))
  -- Dad bot fights too: a commander lobbing cannonballs while Dad's knights are up, a
  -- soldier with its sword when they're gone.
  local bot
  for _,ent in pairs(C.luaentities) do
    if ent.name=="brickcraft:ai_builder" and ent._worker and not ent._worker.jms and ent.object:get_pos() then bot=ent end
  end
  assert(bot,"Dad bot is up")
  local boss=W.armies[rid].boss
  bot.object:set_pos(vector.offset(dad:get_pos(),1,0,0))
  boss.object:set_pos(vector.offset(dad:get_pos(),12,0,0))
  for ent in pairs(brickcraft.war._things()) do
    if ent._army==rid and not ent._boss then ent.object:set_pos(vector.offset(dad:get_pos(),14,0,2)) end
  end
  local f=W.bot_fight(dad,bot.object)
  assert(f and f.role=="commander","with knights up Dad bot commands: "..(f and f.role or "no fight"))
  wait(8,function() return bot._lobbed end,function() return "Dad bot never threw a cannonball" end)
  for ent in pairs(brickcraft.war._things()) do if ent._team=="blue" and ent._owner==DAD then ent.object:remove() end end
  sleep(.2)
  f=W.bot_fight(dad,bot.object)
  assert(f and f.role=="soldier" and f.to,"with no knights Dad bot goes in with its sword: "..(f and f.role or "no fight"))
  log("BOT FIGHTS: Dad bot lobbed cannonballs as commander, then went in as a soldier when his knights were gone")
  -- The sword Dad holds shows in his hand.
  wait(2,function() local d=W.on(dad); return d.held_item=="brickcraft:sword" and d.held:get_attach()==dad end,
    function() return "Dad's sword isn't in his hand: "..tostring(W.on(dad).held_item) end)
  log("WEAPON: Dad's sword shows in his hand")
  -- Teams: Dad's knights leave blue Leona alone; once she's green, they go for her.
  local team=C.registered_chatcommands.team.func
  W.on(kid).shield=0; kid:set_pos(vector.offset(dad:get_pos(),1.5,0,0))
  assert(W.command(DAD,"more knights",said),"Dad's knights back")
  local was=hp(kid); sleep(3); assert(hp(kid)==was,"knights leave a teammate alone")
  team(KID,"green")
  assert(W.on(kid).team=="green" and kid:get_nametag_attributes().color.g>200,"Leona is green")
  was=hp(kid)
  wait(12,function() return hp(kid)~=nil and hp(kid)<was end,function() return "Dad's knights never went for green Leona" end)
  log(("TEAMS: Dad's knights left blue Leona alone; on the green team they went for her (%d/10)"):format(hp(kid) or 0))
  team(KID,"blue"); W.on(kid).hp=10
  -- (Dad's knights and bot may have beaten the army already.)
  if W.armies[rid] then for _=1,10 do W.hit(W.armies[rid].boss.object,dad,"sword") end end
  sleep(2)

  -- Leaving war: bricks back exactly, cannon and knight gone.
  war(DAD,"")
  assert(not W.on(dad) and items(dinv,"main")==dad_bricks and dinv:get_size("war_stash")==0,"Dad's bricks back")
  assert(not cannon.object:get_pos(),"the cannon goes with him")
  -- Switching player mid-war ends it first: Leona's bricks stay Leona's.
  form(kid,"brickcraft:style",{style_explorer="x"})
  assert(not W.on(kid) and kinv:get_size("war_stash")==0,"switching player ends war")
  form(kid,"brickcraft:style",{style_daughter="x"})
  assert(items(kinv,"main")==kid_bricks,"Leona's bricks back after switching mid-war")
  log("BRICKS: leaving war and switching player mid-war give every brick back")

  -- War Lab: made at start, walls up, knights stand when someone comes.
  wait(60,function() local w=W.lab(); return w and w.lab_built end,function() return "War Lab not built" end)
  local lab=W.lab()
  C.load_area({x=lab.x+8,y=0,z=lab.z-8},{x=lab.x+10,y=2,z=lab.z-6})
  assert(C.get_node({x=lab.x+9,y=1,z=lab.z-7}).name=="brickcraft:coral","War Lab cover walls")
  war(KID,"")
  kid:set_pos(brickcraft.home_pos(kid,lab))
  wait(10,function()
    local n=0
    for _,o in ipairs(C.get_objects_inside_radius({x=lab.x+18,y=0,z=lab.z-4},6)) do
      local e=o:get_luaentity()
      if e and e.name=="brickcraft:knight" and not e._team then n=n+1 end
    end
    return n==5
  end,function() return "War Lab knights not up" end)
  log(("LAB: War Lab (experimental) at %d,%d with walls and 5 Brick Knights"):format(lab.x,lab.z))
  wait(10,function()
    for _,army in pairs(W.armies) do if army.lab==lab then return true end end
  end,function() return "no Red Army came to War Lab" end)
  log("LAB ARMY: a Red Army marched into War Lab for Leona (in war)")
  kid:set_pos({x=-1,y=0,z=-1})

  -- Leave a scene to look at: both in war, a cannon and a knight.
  war(DAD,"")
  dad:set_pos({x=-6,y=0,z=0}); face(dad,EAST)
  cannon_item=dinv:get_stack("main",2)
  cannon_item:get_definition().on_place(cannon_item,dad,{type="node",under={x=-4,y=-1,z=0},above={x=-4,y=0,z=0}})
  kn_item=dinv:get_stack("main",4)
  kn_item:get_definition().on_place(kn_item,dad,{type="node",under={x=-1,y=-1,z=1},above={x=-1,y=0,z=1}})
  kid:set_pos({x=-3,y=0,z=-1}); face(kid,WEST) -- looking at Dad, his sword in hand
  log("PASS: war mode works between two players")
  sleep(8)
  C.request_shutdown("BrickCraft war checked",false,1)
end

local started=false
C.register_on_joinplayer(function()
  C.after(2,function()
    local dad,kid=C.get_player_by_name(DAD),C.get_player_by_name(KID)
    if started or not dad or not kid then return end
    started=true
    co=coroutine.create(function() run(dad,kid) end)
    local ok,err=coroutine.resume(co)
    if not ok then error(err) end
  end)
end)
