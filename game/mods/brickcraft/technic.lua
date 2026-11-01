-- Technic machines: axles, gears and technic bricks with an axle through them, turned by a
-- Train Motor on the ground that a Battery Box next to it powers. They are pieces like any
-- other (the Technic row; the motor and battery box are in the Trains row): pick one, hold a
-- color and right click. An axle or gear points the way you look; the separator collects a
-- piece and its right click turns it (or steps a battery box's switch: forward, off, back).
--
-- Power: from each switched-on motor, turning goes along its output line (axles, gears and
-- technic bricks on the same axis) and from gear to gear across neighboring cells (parallel
-- axes): the next gear turns the other way, teeth_a/teeth_b as fast. Two motors turning one
-- machine different ways jam it: nothing in it turns. The machine is worked out again when
-- a piece is placed, collected, turned or switched, and every few seconds near players.
-- A turning piece swaps to an invisible twin and a "spinner" model turns in its place on
-- the client (automatic_rotate about the model's own y axis, which points along the piece).
local C=core
local MOTOR_RPS=1 -- turns per second at a motor's output
local AXES={[0]={x=0,y=1,z=0},{x=0,y=0,z=1},{x=0,y=0,z=-1},{x=1,y=0,z=0},{x=-1,y=0,z=0},{x=0,y=-1,z=0}}
local DIRS={{x=1,y=0,z=0},{x=-1,y=0,z=0},{x=0,y=1,z=0},{x=0,y=-1,z=0},{x=0,y=0,z=1},{x=0,y=0,z=-1}}
local LIGHT={[1]="brickcraft_mint.png",[0]="brickcraft_coral.png",[-1]="brickcraft_gold.png"}
local SWITCH_WORDS={[1]="forward",[0]="off",[-1]="back"}
local function key(p) return p.x..","..p.y..","..p.z end
local function dot(a,b) return a.x*b.x+a.y*b.y+a.z*b.z end
local function axis_param(d)
  for i=0,5 do if vector.equals(AXES[i],d) then return i*4 end end
  return 0
end
local dirty=true -- something changed: work the machines out again
local function changed() dirty=true end

-- The pieces, in every color. An axle or gear lies along its facedir axis (param2 / 4); a
-- technic brick, motor and battery box turn about y (param2 % 4: the hole, the motor's
-- output, the battery box's front).
local GEARS={gear8={8,.28},gear24={24,.45},gear40={40,.56}}
local brick_frame={{-.5,-.5,-.5,.5,-.18,.5},{-.5,.18,-.5,.5,.5,.5},{-.5,-.18,-.5,-.18,.18,.5},{.18,-.18,-.5,.5,.18,.5}}
for _,x in ipairs({-.25,.25}) do
  for _,z in ipairs({-.25,.25}) do brick_frame[#brick_frame+1]={x-.13,.5,z-.13,x+.13,.64,z+.13} end
end
local brick_axle={{-.05,-.13,-.5,.05,.13,.5},{-.13,-.05,-.5,.13,.05,.5}}
local function with(a,b) local t={} for _,v in ipairs(a) do t[#t+1]=v end for _,v in ipairs(b) do t[#t+1]=v end return t end
local separator -- the separator's right click on a piece (below)
local function register(name,def)
  def.paramtype="light"; def.paramtype2="facedir"; def.sunlight_propagates=true
  def.groups=def.groups or {brick=1,technic=1,not_in_creative_inventory=1}
  def.brickcraft_shape="technic"
  def.on_construct=changed; def.after_destruct=changed
  def.brickcraft_turn=function(...) return separator(...) end
  C.register_node(name,def)
end
for _,color in ipairs(brickcraft.colors) do
  local tex="brickcraft_"..color..".png"
  local drop="brickcraft:"..color
  local base="brickcraft:"..color
  -- A pair: the piece, and its invisible twin while it turns (the spinner draws it).
  local function pair(suffix,kind,shown,spin_mesh,box,extra)
    local still,spin=base..suffix,base..suffix.."_spin"
    local def={description=extra.label,drop=drop,collision_box={type="fixed",fixed=box},
      selection_box={type="fixed",fixed=box},brickcraft_power=kind,brickcraft_color=color,
      brickcraft_spin_name=spin,brickcraft_spin_mesh=spin_mesh,brickcraft_teeth=extra.teeth}
    for k,v in pairs(shown) do def[k]=v end
    register(still,def)
    local twin={description=extra.label,drop=drop,collision_box={type="fixed",fixed=box},
      selection_box={type="fixed",fixed=box},brickcraft_power=kind,brickcraft_color=color,
      brickcraft_still_name=still,brickcraft_spin_mesh=spin_mesh,brickcraft_teeth=extra.teeth,
      groups={brick=1,technic=1,technic_spin=1,not_in_creative_inventory=1},
      drawtype=extra.twin_drawtype or "airlike",node_box=extra.twin_box,tiles=extra.twin_box and {tex} or nil}
    register(spin,twin)
  end
  pair("_technic_brick","brick",{drawtype="nodebox",node_box={type="fixed",fixed=with(brick_frame,brick_axle)},tiles={tex}},
    "brickcraft_axle.obj",{-.5,-.5,-.5,.5,.5,.5},
    {label="Technic Brick with axle hole\nPart 32064",twin_drawtype="nodebox",twin_box={type="fixed",fixed=brick_frame}})
  pair("_axle","axle",{drawtype="mesh",mesh="brickcraft_axle.obj",tiles={{name=tex,backface_culling=false}}},
    "brickcraft_axle.obj",{-.15,-.5,-.15,.15,.5,.15},{label="Axle\nPart 3705"})
  for id,g in pairs(GEARS) do
    local r=math.min(g[2],.5)
    pair("_"..id,"gear",{drawtype="mesh",mesh="brickcraft_"..id..".obj",tiles={{name=tex,backface_culling=false}}},
      "brickcraft_"..id..".obj",{-r,-.1,-r,r,.1,r},
      {label="Gear, "..g[1].." teeth\nPart "..({gear8="3647",gear24="3648",gear40="3649"})[id],teeth=g[1]})
  end
  register(base.."_motor_node",{description="Train Motor\nPart 88002",drawtype="mesh",mesh="brickcraft_motor_node.obj",
    tiles={{name=tex,backface_culling=false},{name="brickcraft_track_rail.png",backface_culling=false}},
    collision_box={type="fixed",fixed={-.32,-.5,-.4,.32,.24,.5}},selection_box={type="fixed",fixed={-.32,-.5,-.4,.32,.24,.5}},
    drop=drop,brickcraft_power="motor",brickcraft_color=color,
    on_construct=nil})
  for state,suffix in pairs({[0]="",[1]="_fwd",[-1]="_back"}) do
    register(base.."_battery_node"..suffix,{description="Battery Box with switch\nPart 8881",drawtype="mesh",
      mesh="brickcraft_battery_node.obj",
      tiles={{name=tex,backface_culling=false},{name=LIGHT[state],backface_culling=false}},
      collision_box={type="fixed",fixed={-.3,-.5,-.34,.3,.18,.3}},selection_box={type="fixed",fixed={-.3,-.5,-.34,.3,.18,.3}},
      drop=drop,brickcraft_power="battery",brickcraft_color=color,brickcraft_state=state,
      brickcraft_battery=base.."_battery_node"})
  end
end

-- Motors are remembered by position, so the machines they drive can be worked out.
local storage=C.get_mod_storage()
local motors=C.deserialize(storage:get_string("technic_motors")) or {}
local function save_motors() storage:set_string("technic_motors",C.serialize(motors)) end
for _,color in ipairs(brickcraft.colors) do
  C.override_item("brickcraft:"..color.."_motor_node",{
    on_construct=function(pos) motors[key(pos)]=vector.copy(pos); save_motors(); changed() end,
    after_destruct=function(pos) motors[key(pos)]=nil; save_motors(); changed() end,
  })
end

-- What a cell holds, for the machine: its kind and the line it turns about.
local function info(pos)
  local node=C.get_node(pos)
  local def=C.registered_nodes[node.name]
  local kind=def and def.brickcraft_power
  if not kind then return end
  local axis=(kind=="axle" or kind=="gear") and AXES[math.floor(node.param2/4)%6] or C.facedir_to_dir(node.param2%4)
  return {kind=kind,axis=axis,node=node,def=def}
end
local function shaft(i) return i and (i.kind=="axle" or i.kind=="gear" or i.kind=="brick") end
local function parallel(a,b) return math.abs(dot(a,b))>.99 end
local function battery_next_to(pos)
  for _,d in ipairs(DIRS) do
    local i=info(vector.add(pos,d))
    if i and i.kind=="battery" then return i.def.brickcraft_state end
  end
  return 0
end

-- Works out every machine driven by the given motors: turns per second for each turning
-- cell, about the piece's own axis. Returns {key={pos,w}} and the motors whose machine jammed.
local function solve(list)
  local spins,seen_motor,jams={}, {}, {}
  for _,m in ipairs(list) do
    if not seen_motor[key(m)] then
      local comp,queue,jam={}, {}, false
      local function assign(p,w)
        local k=key(p)
        if comp[k] then
          if math.abs(comp[k].w-w)>1e-6 then jam=true end
          return
        end
        comp[k]={pos=p,w=w,i=info(p)}
        queue[#queue+1]=p
      end
      -- A switched-on motor turns the shaft in front of it (its output line).
      local function drive(mp)
        seen_motor[key(mp)]=true
        local mi=info(mp)
        if not mi or mi.kind~="motor" then return end
        local w=battery_next_to(mp)*MOTOR_RPS
        local out=vector.add(mp,mi.axis)
        local oi=info(out)
        if w~=0 and shaft(oi) and parallel(oi.axis,mi.axis) then assign(out,w*dot(mi.axis,oi.axis)) end
      end
      drive(m)
      local n=1
      while n<=#queue and n<4000 do
        local p=queue[n]; n=n+1
        local c=comp[key(p)]
        local i,w=c.i,c.w
        for _,sgn in ipairs({1,-1}) do
          local q=vector.add(p,vector.multiply(i.axis,sgn))
          local qi=info(q)
          if shaft(qi) and parallel(qi.axis,i.axis) then assign(q,w*dot(i.axis,qi.axis))
          elseif qi and qi.kind=="motor" and vector.equals(vector.add(q,qi.axis),p) and not seen_motor[key(q)] then
            drive(q) -- another motor on this line
          end
        end
        if i.kind=="gear" then
          for _,d in ipairs(DIRS) do
            if math.abs(dot(d,i.axis))<.01 then
              local q=vector.add(p,d)
              local gi=info(q)
              if gi and gi.kind=="gear" and parallel(gi.axis,i.axis) then
                assign(q,-w*i.def.brickcraft_teeth/gi.def.brickcraft_teeth*dot(i.axis,gi.axis))
              end
            end
          end
        end
      end
      for k,c in pairs(comp) do spins[k]={pos=c.pos,w=jam and 0 or c.w} end
      if jam then jams[#jams+1]=m end
    end
  end
  return spins,jams
end

-- Turning pieces: their invisible twin, and a spinner model turning in their place.
local active={} -- key -> {pos,w,obj}
local function rotation_for(axis)
  local forward=math.abs(axis.y)>.5 and {x=0,y=0,z=1} or {x=0,y=1,z=0}
  return vector.dir_to_rotation(forward,axis)
end
local function stop(k)
  local a=active[k]
  active[k]=nil
  if a.obj and a.obj:get_pos() then a.obj:remove() end
  local node=C.get_node(a.pos)
  local def=C.registered_nodes[node.name]
  if def and def.brickcraft_still_name then C.swap_node(a.pos,{name=def.brickcraft_still_name,param2=node.param2}) end
end
local function turn(k,pos,w)
  local i=info(pos)
  if not i then return end
  if i.def.brickcraft_spin_name then
    C.swap_node(pos,{name=i.def.brickcraft_spin_name,param2=i.node.param2})
  end
  local a=active[k] or {pos=pos}
  active[k]=a
  if not (a.obj and a.obj:get_pos()) then
    a.obj=C.add_entity(pos,"brickcraft:spinner")
    a.w=nil
    if not a.obj then return end
    a.obj:set_properties({mesh=i.def.brickcraft_spin_mesh,textures={"brickcraft_"..i.def.brickcraft_color..".png"}})
    a.obj:set_rotation(rotation_for(i.axis))
  end
  if a.w~=w then a.w=w; a.obj:set_properties({automatic_rotate=w*2*math.pi}) end
end
C.register_entity("brickcraft:spinner",{
  initial_properties={visual="mesh",mesh="brickcraft_axle.obj",textures={"brickcraft_cream.png"},
    visual_size={x=10,y=10},backface_culling=false,physical=false,pointable=false,static_save=false},
})

local jammed={} -- motor key -> true while its machine is jammed
local function run()
  dirty=false
  local players=C.get_connected_players()
  local list={}
  for _,m in pairs(motors) do
    for _,pl in ipairs(players) do
      local p=pl:get_pos()
      if math.abs(p.x-m.x)<80 and math.abs(p.z-m.z)<80 then list[#list+1]=m; break end
    end
  end
  local spins,jams=solve(list)
  for k in pairs(active) do if not (spins[k] and spins[k].w~=0) then stop(k) end end
  for k,s in pairs(spins) do if s.w~=0 then turn(k,s.pos,s.w) end end
  local now={}
  for _,m in ipairs(jams) do
    now[key(m)]=true
    if not jammed[key(m)] then
      for _,pl in ipairs(players) do
        if vector.distance(pl:get_pos(),m)<24 then
          C.chat_send_player(pl:get_player_name(),"A machine is jammed: two motors turn it different ways. Switch one the other way.")
        end
      end
    end
  end
  jammed=now
end
local timer=0
C.register_globalstep(function(dt)
  timer=timer+dt
  if dirty or timer>2 then timer=0; run() end
end)
-- A twin left turning when its area unloaded (or the server stopped) is put back still;
-- the next run turns it again if its motor is on.
C.register_lbm({name="brickcraft:technic_still",nodenames={"group:technic_spin"},run_at_every_load=true,
  action=function(pos,node)
    if active[key(pos)] then return end
    local def=C.registered_nodes[node.name]
    C.swap_node(pos,{name=def.brickcraft_still_name,param2=node.param2})
    dirty=true
  end})

-- The separator's right click: a battery box's switch steps forward, off, back, off; an
-- axle or gear turns to point another way (one of six); a technic brick or motor turns.
function separator(pos,node,player)
  local def=C.registered_nodes[node.name]
  local name=player and player:is_player() and player:get_player_name()
  local after
  if def.brickcraft_power=="battery" then
    local meta=C.get_meta(pos)
    local state
    if def.brickcraft_state~=0 then state=0
    else state=meta:get_int("last")==1 and -1 or 1; meta:set_int("last",state) end
    after={name=def.brickcraft_battery..({[1]="_fwd",[0]="",[-1]="_back"})[state],param2=node.param2}
    if name then C.chat_send_player(name,"Switch: "..SWITCH_WORDS[state]) end
  elseif def.brickcraft_power=="axle" or def.brickcraft_power=="gear" then
    after={name=def.brickcraft_still_name or node.name,param2=((math.floor(node.param2/4)+1)%6)*4}
  else
    after={name=node.name,param2=(node.param2+1)%4}
  end
  C.swap_node(pos,after)
  brickcraft.remember(player,{kind="turn",pos=vector.copy(pos),before={name=node.name,param2=node.param2},after=after})
  changed()
end

-- Right click with a color and a technic piece, or a Train Motor or Battery Box on the
-- ground (place_brick in init.lua and trains.lua send them here). Axles and gears point
-- the way you look (straight up or down when you look steeply); the rest turn like bricks.
local SUFFIX={brick="_technic_brick",axle="_axle",gear8="_gear8",gear24="_gear24",gear40="_gear40",
  motor="_motor_node",battery="_battery_node"}
local function place(s,stack,placer,pointed,item)
  local kind=s.technic or s.train
  local udef=C.registered_nodes[C.get_node(pointed.under).name]
  local pos=(udef and udef.buildable_to) and pointed.under or pointed.above
  local def=C.registered_nodes[C.get_node(pos).name]
  if not (def and def.buildable_to) or pos.y<0 then return stack end
  local look=placer:get_look_dir()
  local turn=placer:get_meta():get_int("brickcraft_turn")%4
  local flat=(C.dir_to_facedir(look)+turn)%4
  local param2=flat
  if kind=="axle" or kind:find("^gear") then
    param2=math.abs(look.y)>.7 and (look.y>0 and 0 or 20) or axis_param(C.facedir_to_dir(flat))
  end
  local node={name=item..SUFFIX[kind],param2=param2}
  C.set_node(pos,node)
  stack:take_item(s.cost)
  brickcraft.remember(placer,{kind="place",pos=vector.copy(pos),node=node,drop=item.." "..s.cost})
  return stack
end

-- How fast a cell turns now (0 if still), for tests and builders.
local function spin(pos) local a=active[key(pos)]; return a and a.w or 0 end

brickcraft.technic={place=place,solve=solve,run=run,spin=spin,active=active,motors=motors,axis_param=axis_param,
  jammed=function() return jammed end}

-- Technic Lab: a world made once for everyone, with machines running on the baseplate to
-- the right of the start spots: a gear train (8, 24, 40, 24 and 8 teeth), a windmill, a
-- line of axles through technic bricks into two meshing gears, and two motors jammed
-- against each other (switch one the other way to free it). init.lua makes the world.
local function build_lab(w)
  local function at(x,y,z) return {x=w.x+x,y=y,z=w.z+z} end
  for x=8,22 do for y=0,6 do for z=-4,8 do C.set_node(at(x,y,z),{name="air"}) end end end
  local function put(x,y,z,name,param2) C.set_node(at(x,y,z),{name="brickcraft:"..name,param2=param2 or 0}) end
  local Z,X,MX=axis_param({x=0,y=0,z=1}),axis_param({x=1,y=0,z=0}),axis_param({x=-1,y=0,z=0})
  -- Gear train: battery, motor facing +z, then gears side by side, each on a stand.
  for x=9,14 do put(x,0,2,"cream") end
  put(9,1,2,"navy_battery_node_fwd"); put(10,1,2,"navy_motor_node",0)
  for x=10,14 do put(x,0,3,"cream") end
  for i,g in ipairs({"gear8","gear24","gear40","gear24","gear8"}) do put(9+i,1,3,({"gold","coral","sky","coral","gold"})[i].."_"..g,Z) end
  -- Windmill: a tower with the motor on top turning a big wheel toward the start spots.
  for y=0,3 do put(18,y,6,"sky"); put(18,y,7,"sky") end
  put(18,4,7,"navy_battery_node_fwd"); put(18,4,6,"navy_motor_node",2)
  put(18,4,5,"cream_axle",Z); put(18,4,4,"rose_gear40",Z)
  -- Bearing line: motor facing +x, axles through technic bricks, two gears meshing upward.
  for x=10,15 do put(x,0,-2,"cream") end
  put(10,0,-3,"cream"); put(10,1,-3,"navy_battery_node_fwd"); put(10,1,-2,"navy_motor_node",1)
  put(11,1,-2,"gold_axle",X); put(12,1,-2,"mint_technic_brick",1); put(13,1,-2,"gold_axle",X)
  put(14,1,-2,"mint_technic_brick",1); put(15,1,-2,"coral_gear24",X); put(15,2,-2,"sky_gear24",X)
  -- Jam: two motors on one axle, both forward, so they fight.
  for x=17,20 do put(x,0,-2,"cream") end
  put(17,0,-3,"cream"); put(20,0,-3,"cream")
  put(17,1,-3,"navy_battery_node_fwd"); put(17,1,-2,"navy_motor_node",1)
  put(18,1,-2,"violet_axle",X); put(19,1,-2,"violet_axle",MX)
  put(20,1,-3,"navy_battery_node_fwd"); put(20,1,-2,"navy_motor_node",3)
  C.log("action","BrickCraft Technic Lab machines built at "..w.x..","..w.z)
  changed()
end
brickcraft.technic.build_lab=build_lab

if C.settings:get_bool("brickcraft_technic_test",false) then
  dofile(C.get_modpath("brickcraft").."/technic_test.lua")
end
