-- Opt-in check (tools/test_kart.py): a dedicated server and one real client race on the
-- Kart Circuit. The track is laid out (start line and gantry with its lights, the bridge
-- open over the lower road with pillars, the kicker, boost pads, the flat field, buildings
-- and trees between the roads); with someone there the grid has 8 karts and banana bunches; Dad gets in and CPU racers fill the
-- grid; three red lights, then green; a kart drives, climbs, turns; a banana dropped in
-- front of a kart spins it out, a thrown one lands on the track ahead; a spin on the
-- bridge's edge sends a kart off the track and it's put back; bunches give bananas;
-- boost pads speed a kart up; the kicker throws it in the air and a long ramp a long way;
-- Space jumps it over a banana and a crate (a crate stops a kart that doesn't, and a kart
-- on or in one gets off); E, or 3 s stuck, puts a kart back on the road; the side of a raised road
-- stops a kart on the grass, and so does a building; the minimap is on in a kart; holding a brick in a kart places nothing; everyone finishes
-- the lap, the results come, and the grid is ready again. Dad's AI builder stays off the
-- track, in its seat in the middle.
local C=core
local DAD="KartDad"
local K=brickcraft.kart
local S,N,HALF=K.S,K.N,K.HALF
local function log(msg) C.log("action","BRICKCRAFT KART "..msg) end
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
local function node(w,x,y,z) return C.get_node({x=w.x+math.floor(x+.5),y=y,z=w.z+math.floor(z+.5)}).name end
-- A kart taken out of the race for a check: put at sample j, lat cells right of the middle,
-- doing nothing (input) until it's given back.
local function place(k,w,j,lat,input)
  local s=S[j]
  local rx,rz=s.tz,-s.tx
  k._input=input or {}
  k._p={x=w.x+s.x+rx*lat,y=s.h-.5,z=w.z+s.z+rz*lat}
  k._yaw=math.atan2(-s.tx,s.tz)
  k._i,k._vl,k._vt,k._vy,k._air,k._spin,k._fell,k._boost,k._drift=j,0,0,0,false,nil,nil,nil,nil
  k.object:set_pos(k._p)
end
-- Of samples js, the one furthest from every racer but k; and no bananas lying about.
local function quiet(g,w,k,js)
  for b in pairs(K.bananas()) do if b.object:get_pos() then b.object:remove() end; K.bananas()[b]=nil end
  local best,far
  for _,i in ipairs(js) do
    local d=1e9
    for _,o in ipairs(g.karts) do if o~=k then d=math.min(d,(o._p.x-w.x-S[i].x)^2+(o._p.z-w.z-S[i].z)^2) end end
    if not far or d>far then best,far=i,d end
  end
  return best
end
local function first(f) for j=1,N do if f(S[j],j) then return j end end end

local function run(dad)
  for _,f in ipairs(C.registered_on_player_receive_fields) do if f(dad,"brickcraft:style",{style_dad="x"}) then break end end
  wait(90,function() local w=K.world(); return w and w.kart_built end,function() return "Kart Circuit not built" end)
  local w=K.world()
  C.load_area({x=w.x-44,y=-2,z=w.z-44},{x=w.x+44,y=10,z=w.z+44})
  -- The track.
  local s1=S[1]
  assert(node(w,s1.x,-1,s1.z)=="brickcraft:kart_start","the start line")
  local rx,rz=s1.tz,-s1.tx
  assert(node(w,s1.x+rx*(HALF+1),2,s1.z+rz*(HALF+1))=="brickcraft:kart_gantry" and node(w,s1.x,5,s1.z)=="brickcraft:kart_gantry","the gantry")
  for _,l in ipairs(K.LIGHTS) do assert(C.get_node({x=w.x+l.x,y=l.y,z=w.z+l.z}).name=="brickcraft:kart_light_off","lights off") end
  local top=first(function(s) return s.open and s.h>=4.9 end)
  assert(top,"a bridge")
  local deck=node(w,S[top].x,4,S[top].z)
  assert(deck:find("^brickcraft:kart_") and node(w,S[top].x,2,S[top].z)=="air","the bridge's deck, open under it: "..deck)
  local under=first(function(s) return s.h<.1 and (s.x-S[top].x)^2+(s.z-S[top].z)^2<9 end)
  assert(under and node(w,S[under].x,-1,S[under].z):find("^brickcraft:kart_") and node(w,S[under].x,1,S[under].z)=="air","the lower road under the bridge")
  local pillars=0
  for z=-44,44 do for x=-44,44 do if node(w,x,1,z)=="brickcraft:kart_pillar" then pillars=pillars+1 end end end
  assert(pillars>=10,"pillars: "..pillars)
  local kick=first(function(s,j) return s.h>1.3 and S[j%N+1].h<.2 end)
  assert(kick,"no kicker")
  local up,down=node(w,S[kick-2].x,0,S[kick-2].z),node(w,S[kick%N+4].x,0,S[kick%N+4].z)
  assert(up:find("^brickcraft:kart_") and down=="air","the kicker: "..up.." then "..down)
  local boost=first(function(s) return s.boost end)
  assert(node(w,S[boost].x,-1,S[boost].z)=="brickcraft:kart_boost","a boost pad")
  assert(node(w,0,-1,0)=="brickcraft:kart_grass" and node(w,0,3,0)=="air" and node(w,43,5,-43)=="air","the field is flat")
  local houses,trees=0,0
  for _,pc in ipairs(K.PIECES) do
    if pc[1]=="house" then houses=houses+1; assert(node(w,pc[2],1,pc[3]):find("^brickcraft:kart_wall_"),"a building's wall")
    else trees=trees+1; assert(node(w,pc[2],0,pc[3])=="brickcraft:kart_trunk","a tree's trunk") end
  end
  assert(houses>=12 and trees>=5,("buildings %d, trees %d"):format(houses,trees))
  log(("SCENERY: %d buildings and %d trees between the roads"):format(houses,trees))
  log(("TRACK: %d cells round, a start gantry, a bridge %.0f high over the lower road on %d pillars, a kicker, boost pads, at %d,%d"):format(N/2,S[top].h,pillars,w.x,w.z))

  -- The grid.
  dad:set_pos(brickcraft.home_pos(dad,w))
  wait(10,function() local g=K.game(); return g and #g.karts==8 end,function() return "no grid" end)
  local g=K.game()
  assert(g.phase=="lobby","lobby: "..g.phase)
  local boxes=0
  for _,o in pairs(C.luaentities) do if o.name=="brickcraft:kart_bunch" then boxes=boxes+1 end end
  assert(boxes==12,"12 banana bunches, got "..boxes)
  -- Dad gets in, as a right click would.
  local mine=g.karts[1]
  mine.object:get_luaentity().on_rightclick(mine,dad)
  assert(dad:get_attach()==mine.object and K.riding(DAD)==mine,"Dad in the kart")
  wait(3,function() return g.phase=="join" end,function() return "no join: "..g.phase end)
  -- What he holds places nothing while he's in it.
  local stack=ItemStack("brickcraft:coral 5")
  local above={x=w.x+math.floor(s1.x+.5),y=0,z=w.z+math.floor(s1.z+.5)}
  C.registered_items["brickcraft:coral"].on_place(stack,dad,{type="node",under={x=above.x,y=-1,z=above.z},above=above})
  assert(C.get_node(above).name=="air","a brick placed from a kart")
  assert(dad:hud_get_flags().minimap,"the minimap on in a kart")
  log("GRID: 8 karts and 12 banana bunches; Dad got in (his bricks place nothing in a kart, his minimap is on)")

  K.set_laps(1); K.set_racers(6)
  assert(K.start(g),"start")
  local racers,looks=0,{}
  for _,k in ipairs(g.karts) do
    if k._bot then racers=racers+1; assert(not looks[k._bot.id] and k._bot.id~="dad","a CPU racer twice, or as Dad"); looks[k._bot.id]=true end
  end
  assert(racers==5,"5 CPU racers, got "..racers)
  wait(3,function() return C.get_node({x=w.x+K.LIGHTS[1].x,y=K.LIGHTS[1].y,z=w.z+K.LIGHTS[1].z}).name=="brickcraft:kart_light_red" end,function() return "no red light" end)
  assert(vector.distance(g.karts[2]._p,g.karts[2].object:get_pos())<.1,"held on the grid")
  wait(6,function() return g.phase=="race" end,function() return "no race" end)
  assert(C.get_node({x=w.x+K.LIGHTS[3].x,y=K.LIGHTS[3].y,z=w.z+K.LIGHTS[3].z}).name=="brickcraft:kart_light_green","green")
  log("START: 5 CPU racers in, three red lights, then green")

  -- Dad's kart drives: W down for two seconds.
  mine._input={up=true,steer=0}
  sleep(2)
  assert(mine._vl>8 and mine._prog>-10,"Dad's kart drove: "..mine._vl.." "..mine._prog)
  -- Steering with the keys keeps his view behind the kart; heading off the road at its
  -- edge, smart steering brings him back on.
  assert(math.abs(dad:get_look_horizontal()-mine._yaw)<.05 or math.abs(math.abs(dad:get_look_horizontal()-mine._yaw)-2*math.pi)<.05,"the view behind the kart")
  local edge=mine._i
  place(mine,w,edge,HALF-1.3,{up=true,steer=0,human=true})
  mine._yaw=mine._yaw-.45 -- heading off to the right
  mine._vl=9
  local off=false
  for _=1,15 do sleep(.1); if mine._road==false then off=true end end
  assert(not off and math.abs(mine._lat)<HALF,"smart steering kept him on: "..mine._lat)
  mine._input=nil; mine._autopilot=true
  log(("DRIVE: Dad's kart at %.1f cells/s after 2 s; his view stays behind it, smart steering kept him on the road"):format(mine._vl))
  -- Dad's AI builder keeps off the track: it watches from its seat in the middle.
  local builder=brickcraft.ai and brickcraft.ai.get and brickcraft.ai.get("dad")
  if builder then
    local seat={x=w.x-2,y=-.5,z=w.z-2}
    wait(12,function() local bp=builder.pos(); return bp and vector.distance(bp,seat)<1.6 end,
      function() local bp=builder.pos(); return "Dad's builder not in its seat: "..(bp and C.pos_to_string(vector.round(bp)) or "none") end)
    log("BUILDER: Dad's AI builder watches the race from its seat in the middle, off the track")
  end

  -- A banana in front of a CPU kart spins it out.
  local bot
  for _,k in ipairs(g.karts) do if k._bot then bot=k end end
  bot._bananas=1
  local j=quiet(g,w,bot,{40,120,200})
  local b=K.throw(bot,false)
  assert(b,"dropped")
  place(bot,w,j,0,{up=true,steer=0})
  b.object:set_pos({x=w.x+S[j+4].x,y=S[j+4].h-.5+.3,z=w.z+S[j+4].z})
  b._from=nil
  wait(4,function() return (bot._spin or 0)>t() end,function() return "no spin: "..bot._vl end)
  assert(not b.object:get_pos(),"the banana's gone")
  log("BANANA: a kart running over a banana spun out")
  -- A thrown one lands on the track ahead.
  quiet(g,w,bot,{100})
  place(bot,w,100,0)
  bot._bananas=1
  local thrown=K.throw(bot,true)
  wait(3,function() return thrown._lying end,function() return "still flying" end)
  local tp=thrown.object:get_pos()
  local gy=K.ground(tp.x-w.x,tp.z-w.z,tp.y,100)
  local d=vector.distance(tp,bot._p)
  assert(d>4 and math.abs(tp.y-.3-gy)<.05,"landed ahead on the track: "..d)
  thrown.object:remove(); K.bananas()[thrown]=nil
  log(("THROW: a banana thrown ahead landed %.1f cells on"):format(d))

  -- Spun out on the bridge's edge, a kart slides off, falls, and is put back.
  quiet(g,w,bot,{top})
  place(bot,w,top,HALF-.6)
  assert(K.spin(bot),"spun")
  bot._vt=6
  wait(3,function() return (bot._fell or 0)>0 end,function() return "didn't fall off: "..bot._p.y end)
  local fell=bot._p.y
  wait(3,function() return not bot._fell end,function() return "not put back" end)
  assert(fell<0 and bot._p.y>S[top].h-1 and math.abs(bot._vl)<.1,"back on the bridge: "..bot._p.y)
  log(("DERAIL: a spin on the bridge sent a kart off (down to %.1f); it's back on the bridge at %.1f"):format(fell,bot._p.y))

  -- A banana bunch gives bananas.
  local box=quiet(g,w,bot,K.BOX_AT) -- (where no other racer takes it first)
  for _,o in pairs(C.luaentities) do if o.name=="brickcraft:kart_bunch" then o._back=t() end end -- none just taken by a racer
  bot._bananas=0
  place(bot,w,box-6,-.8,{up=true,steer=0})
  bot._vl=6
  wait(3,function() return bot._bananas>0 end,function() return "no banana from the bunch" end)
  log("BUNCH: a banana bunch on the road gave "..bot._bananas.." banana(s)")
  -- A boost pad.
  local pads={}
  for j2=1,N do if S[j2].boost and not S[j2-1 < 1 and N or j2-1].boost then pads[#pads+1]=j2 end end
  boost=quiet(g,w,bot,pads)
  place(bot,w,boost-4,0,{up=true,steer=0})
  bot._vl=8
  wait(2,function() return (bot._boost or 0)>t() end,function() return "no boost" end)
  sleep(.6)
  assert(bot._vl>11.5,"boosting: "..bot._vl)
  log(("BOOST: a boost pad took a kart to %.1f cells/s"):format(bot._vl))
  -- The kicker throws a kart in the air.
  quiet(g,w,bot,{kick})
  place(bot,w,kick-14,0,{up=true,steer=0})
  bot._vl=11
  local flew=0
  wait(4,function() if bot._air then flew=flew+1 end; return bot._i>kick+12 and not bot._air end,function() return "never past the kicker" end)
  assert(flew>=2 and not bot._fell,"in the air over the kicker: "..flew)
  log("JUMP: the kicker threw a kart in the air and it landed on the road")
  -- A long-jump ramp after a boost pad: a long way through the air.
  local ramp=K.nearest(K.JUMPS[2][1],K.JUMPS[2][2])
  quiet(g,w,bot,{ramp})
  place(bot,w,ramp-24,0,{up=true,steer=0})
  bot._vl,bot._boost=16,t()+3
  local from,to
  wait(4,function()
    if bot._air and not from then from=vector.copy(bot._p) end
    if from and not bot._air then to=vector.copy(bot._p) end
    return to
  end,function() return "no long jump" end)
  local long=vector.distance({x=from.x,y=0,z=from.z},{x=to.x,y=0,z=to.z})
  assert(long>8 and not bot._fell,"a long jump: "..long)
  log(("LONG JUMP: off the big ramp at speed, a kart flew %.1f cells"):format(long))
  -- Space going straight jumps: over a banana lying on the road.
  local j3=quiet(g,w,bot,{60})
  bot._bananas=1
  local peel=K.throw(bot,false)
  peel.object:set_pos({x=w.x+S[j3+5].x,y=S[j3+5].h-.5+.3,z=w.z+S[j3+5].z})
  peel._from=nil
  place(bot,w,j3,0,{up=true,steer=0,drift=true})
  bot._vl=10
  wait(3,function() return bot._i>j3+14 and not bot._air end,function() return "didn't get past the banana" end)
  assert(not bot._spin and peel.object:get_pos(),"jumped over the banana")
  peel.object:remove(); K.bananas()[peel]=nil
  log("HOP: Space going straight jumped a kart over a banana")
  -- A crate stops a kart that runs into it, and one that jumps clears it.
  local cr=K.CRATE_AT[1]
  quiet(g,w,bot,{cr.j})
  local function at_crate(back,input,v)
    place(bot,w,cr.j-back,cr.lat,input)
    bot._yaw=math.atan2(-(w.x+cr.x-bot._p.x),w.z+cr.z-bot._p.z) -- straight at it
    bot._vl=v
  end
  at_crate(8,{up=true,steer=0},6)
  sleep(1.5)
  local short=vector.distance({x=bot._p.x,y=0,z=bot._p.z},{x=w.x+cr.x,y=0,z=w.z+cr.z})
  assert(short<1.6 and short>.4,"stopped by the crate: "..short)
  at_crate(8,{up=true,steer=0,drift=true},11)
  wait(3,function() return bot._i>cr.j+6 end,function() return "didn't clear the crate: "..(bot._i-cr.j) end)
  assert(not bot._fell,"cleared it on the road")
  log("CRATE: a crate on the road stopped a kart; jumping, a kart cleared it")
  -- Landed on a crate, a kart drives off it; one that ended up in it drives out.
  at_crate(0,{up=true,steer=0},4)
  bot._p={x=w.x+cr.x,y=.5,z=w.z+cr.z}; bot.object:set_pos(bot._p)
  bot._yaw=math.atan2(-S[cr.j].tx,S[cr.j].tz) -- down the road
  sleep(1.5)
  assert(vector.distance(bot._p,{x=w.x+cr.x,y=bot._p.y,z=w.z+cr.z})>1.5,"stuck on the crate")
  at_crate(0,{up=true,steer=0},4)
  bot._p={x=w.x+cr.x,y=-.5,z=w.z+cr.z}; bot.object:set_pos(bot._p)
  bot._yaw=math.atan2(-S[cr.j].tx,S[cr.j].tz)
  sleep(1.5)
  assert(vector.distance(bot._p,{x=w.x+cr.x,y=bot._p.y,z=w.z+cr.z})>1.5,"stuck in the crate")
  log("CRATE TOP: a kart on a crate drove off it, one in it drove out")
  -- E puts a kart back on the middle of the road; so does being stuck for 3 s.
  local mid=quiet(g,w,bot,{150})
  place(bot,w,mid,0,{})
  bot._p.x,bot._p.z=bot._p.x+HALF+2,bot._p.z+2; bot.object:set_pos(bot._p)
  bot._input={reset=true}
  sleep(.5)
  local back=vector.distance(bot._p,{x=w.x+S[bot._i].x,y=bot._p.y,z=w.z+S[bot._i].z})
  assert(back<.1,"reset: "..back)
  local house
  for _,pc in ipairs(K.PIECES) do if pc[1]=="house" then house=pc; break end end
  bot._input={up=true,steer=0}
  bot._p={x=w.x+house[2]-1,y=-.5,z=w.z+house[3]}
  bot._yaw=math.atan2(-1,0)
  bot._vl,bot._vt=0,0
  bot.object:set_pos(bot._p)
  wait(5,function() local s2=S[bot._i]; return vector.distance(bot._p,{x=w.x+s2.x,y=bot._p.y,z=w.z+s2.z})<.1 end,function() return "not put back when stuck" end)
  log("RESET: E put a kart back on the road, and so did 3 s stuck against a building")
  -- The side of the raised road stops a kart on the grass.
  local bank=first(function(s) return s.h>=2.5 and not s.open end)
  local bs=S[bank]
  local brx,brz=bs.tz,-bs.tx
  bot._input={up=true,steer=0}
  bot._p={x=w.x+bs.x+brx*(HALF+3),y=-.5,z=w.z+bs.z+brz*(HALF+3)}
  bot._yaw=math.atan2(brx,-brz) -- facing the road
  bot._vl,bot._vt,bot._air,bot._vy=5,0,false,0
  bot.object:set_pos(bot._p)
  sleep(1.5)
  assert(bot._p.y<0 and (bot._p.x-w.x-bs.x)^2+(bot._p.z-w.z-bs.z)^2>HALF^2,"stopped by the bank: "..bot._p.y)
  log("BANK: the side of the raised road stopped a kart on the grass")
  -- So does a building.
  local house
  for _,pc in ipairs(K.PIECES) do if pc[1]=="house" then house=pc; break end end
  bot._p={x=w.x+house[2]-3,y=-.5,z=w.z+house[3]}
  bot._yaw=math.atan2(-1,0) -- facing +x, at the wall
  bot._vl,bot._vt,bot._air,bot._vy=6,0,false,0
  bot.object:set_pos(bot._p)
  sleep(1.5)
  assert(bot._p.x<w.x+house[2]-.4,"stopped by the building: "..(bot._p.x-w.x-house[2]))
  log("WALL: a building stopped a kart")
  bot._input=nil
  place(bot,w,bot._i,0,nil)
  bot._input=nil

  -- Everyone finishes; the results; the grid again.
  wait(150,function() return g.phase=="done" end,function()
    local s={}
    for _,k in ipairs(g.karts) do if k._rider or k._bot then s[#s+1]=("%s %d/%d"):format(k._bot and k._bot.id or "dad",k._prog,N) end end
    return "race not over: "..table.concat(s,", ")
  end)
  assert(mine._place,"Dad finished")
  local placed=#g.places
  assert(placed>=4,"finishers: "..placed)
  log(("FINISH: Dad finished %d of %d (%.1f s); %d finished"):format(mine._place,6,mine._time,placed))
  g.next=t()
  wait(5,function() return K.game()~=g end,function() return "no new grid" end)
  g=K.game()
  assert(g.phase=="lobby" and #g.karts==8 and not dad:get_attach() and not K.riding(DAD),"the grid ready again")
  log("NEW RACE: the grid is ready again, Dad out of his kart")

  -- A scene: Dad racing again, seen from behind.
  g.karts[1].object:get_luaentity().on_rightclick(g.karts[1],dad)
  K.start(g)
  g.karts[1]._autopilot=true
  dad:set_camera({mode="third"})
  sleep(9)
  log("SCENE: Dad racing")
  sleep(8)
  log("PASS: the Kart Circuit races")
  C.request_shutdown("BrickCraft kart circuit checked",false,1)
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
