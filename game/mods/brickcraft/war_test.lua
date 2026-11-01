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

  -- A cannonball nobody fired hits Dad.
  dad:set_pos({x=-5,y=0,z=-2}); sleep(.6)
  W.fire({x=-9,y=0,z=-2},{x=14,y=1,z=0})
  wait(3,function() return hp(dad)==dad_hp-3 end,function() return "stray ball: Dad "..hp(dad) end)
  log("STRAY: a cannonball with no shooter hits too")

  -- The Brick Knight: five sword strikes knock it down; it gets up at its spot.
  local kn_item=dinv:get_stack("main",4)
  kn_item:get_definition().on_place(kn_item,dad,{type="node",under={x=-3,y=-1,z=-5},above={x=-3,y=0,z=-5}})
  local knight
  for _,o in ipairs(C.get_objects_inside_radius({x=-3,y=-.5,z=-5},.6)) do
    if o:get_luaentity() and o:get_luaentity().name=="brickcraft:knight" then knight=o:get_luaentity() end
  end
  assert(knight,"knight put up")
  dad:set_pos({x=-5,y=0,z=-5}); sleep(1.2)
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
  assert(knight._down and W.on(dad).kos==2,"knight down, Dad's 2nd knockout")
  sleep(3.3)
  assert(not knight._down and knight._hp==10,"knight back up with full hearts")
  log("KNIGHT: down after 5 strikes, back up 3 s later")

  -- Leaving war: bricks back exactly, cannon and knight gone.
  war(DAD,"")
  assert(not W.on(dad) and items(dinv,"main")==dad_bricks and dinv:get_size("war_stash")==0,"Dad's bricks back")
  assert(not cannon.object:get_pos() and not knight.object:get_pos(),"cannon and knight go with him")
  -- Switching player mid-war ends it first: Leona's bricks stay Leona's.
  form(kid,"brickcraft:style",{style_explorer="x"})
  assert(not W.on(kid) and kinv:get_size("war_stash")==0,"switching player ends war")
  form(kid,"brickcraft:style",{style_daughter="x"})
  assert(items(kinv,"main")==kid_bricks,"Leona's bricks back after switching mid-war")
  log("BRICKS: leaving war and switching player mid-war give every brick back")

  -- War Lab: made at start, walls up, knights stand when someone comes.
  wait(60,function() local w=W.lab(); return w and w.lab_built end,function() return "War Lab not built" end)
  local lab=W.lab()
  assert(C.get_node({x=lab.x+9,y=1,z=lab.z-7}).name=="brickcraft:coral","War Lab cover walls")
  kid:set_pos(brickcraft.home_pos(kid,lab))
  wait(10,function()
    local n=0
    for _,o in ipairs(C.get_objects_inside_radius({x=lab.x+18,y=0,z=lab.z-4},6)) do
      if o:get_luaentity() and o:get_luaentity().name=="brickcraft:knight" then n=n+1 end
    end
    return n==5
  end,function() return "War Lab knights not up" end)
  log(("LAB: War Lab (experimental) at %d,%d with walls and 5 Brick Knights"):format(lab.x,lab.z))
  kid:set_pos({x=-1,y=0,z=-1})

  -- Leave a scene to look at: both in war, a cannon and a knight.
  war(DAD,""); war(KID,"")
  dad:set_pos({x=-6,y=0,z=0}); face(dad,EAST)
  cannon_item=dinv:get_stack("main",2)
  cannon_item:get_definition().on_place(cannon_item,dad,{type="node",under={x=-4,y=-1,z=0},above={x=-4,y=0,z=0}})
  kn_item=dinv:get_stack("main",4)
  kn_item:get_definition().on_place(kn_item,dad,{type="node",under={x=-1,y=-1,z=1},above={x=-1,y=0,z=1}})
  kid:set_pos({x=-1,y=0,z=-1})
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
