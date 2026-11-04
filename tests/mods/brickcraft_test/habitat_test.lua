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
  eagle_ent:_hit(dad,{dmg=1})
  assert(not fenced._carried and not fenced._dead,"dropped")
  sleep(2)
  -- Caught again, it's carried away for good.
  wait(40,function() return fenced._dead end,function() return "the eagle never carried it off" end)
  log("an eagle carried a bunny off (a hit made it drop it once)")
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
