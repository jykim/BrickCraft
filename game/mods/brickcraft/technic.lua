-- Technic machines: axles, gears and technic bricks with an axle through them, turned by a
-- Train Motor on the ground that a Battery Box next to it powers. They are pieces like any
-- other (the Technic row; the motor and battery box are in the Trains row): pick one, hold a
-- color and right click. An axle or gear points the way you look; the separator collects a
-- piece and its right click turns it (or steps a battery box's switch: forward, off, back).
--
-- Power: from each switched-on motor, turning goes along its output line (axles, gears and
-- technic bricks on the same axis) and from gear to gear. Gears have their real size (a
-- cell is 2 studs; pitch radius teeth/32 cells), and two gears in one plane mesh when their
-- centers are the two radii apart: an 8 next to a 24, a 24 two cells from a 40, two 24s or
-- an 8 and a 40 on a diagonal. The driven gear turns the other way, teeth_a/teeth_b as fast,
-- and so on down the train. Two motors turning one machine different ways jam it: nothing
-- in it turns. The machine is worked out again when a piece is placed, collected, turned or
-- switched, and every few seconds near players. A turning piece swaps to an invisible twin
-- and a "spinner" model turns in its place on the client (automatic_rotate about the
-- model's own y axis, which points along the piece). A machine's spinners start together,
-- each gear at the angle that puts its teeth between the teeth of the gear driving it.
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
local GEARS={gear8=8,gear24=24,gear40=40}
local function radius(teeth) return teeth/32 end
local MESH_SLACK=.1 -- how far off the exact spacing still meshes (two 24s on a diagonal)
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
  for id,teeth in pairs(GEARS) do
    local r=math.min(radius(teeth)+.05,.5)
    pair("_"..id,"gear",{drawtype="mesh",mesh="brickcraft_"..id..".obj",tiles={{name=tex,backface_culling=false}}},
      "brickcraft_"..id..".obj",{-r,-.1,-r,r,.1,r},
      {label="Gear, "..teeth.." teeth\nPart "..({gear8="3647",gear24="3648",gear40="3649"})[id],teeth=teeth})
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

-- A line's axis without its sign (+x, +y or +z), and two directions across it.
local function canon(a) return {x=math.abs(a.x),y=math.abs(a.y),z=math.abs(a.z)} end
local function across(u)
  if u.x>.5 then return {x=0,y=1,z=0},{x=0,y=0,z=1} end
  if u.y>.5 then return {x=0,y=0,z=1},{x=1,y=0,z=0} end
  return {x=0,y=1,z=0},{x=1,y=0,z=0}
end
-- Gears near a gear (or a gear about to go) at p with teeth n about axis a, in its plane:
-- calls fn(q, gear info, meshes?) for each, where meshes is whether the spacing is right.
local function gears_near(p,n,a,fn)
  local e1,e2=across(canon(a))
  for i=-3,3 do for j=-3,3 do
    if i~=0 or j~=0 then
      local q=vector.add(p,vector.add(vector.multiply(e1,i),vector.multiply(e2,j)))
      local gi=info(q)
      if gi and gi.kind=="gear" and parallel(gi.axis,a) then
        local gap=math.sqrt(i*i+j*j)-radius(n)-radius(gi.def.brickcraft_teeth)
        if gap<MESH_SLACK then fn(q,gi,math.abs(gap)<=MESH_SLACK) end
      end
    end
  end end
end
-- The angle of direction d about axis u (from the first across-direction).
local function angle(u,d) local e1=across(u); return math.atan2(dot(d,vector.cross(u,e1)),dot(d,e1)) end

-- Works out every machine driven by the given motors: turns per second for each turning
-- cell, about the piece's own axis. Returns {key={pos,w}} and the motors whose machine jammed.
local function solve(list)
  local spins,seen_motor,jams={}, {}, {}
  for _,m in ipairs(list) do
    if not seen_motor[key(m)] then
      local comp,queue,jam={}, {}, false
      -- w: turns per second about the piece's own axis; alpha: the angle (about the line's
      -- unsigned axis) where one of a gear's teeth starts.
      local function assign(p,w,alpha)
        local k=key(p)
        if comp[k] then
          if math.abs(comp[k].w-w)>1e-6 then jam=true end
          return
        end
        comp[k]={pos=p,w=w,i=info(p),alpha=alpha or 0}
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
          local na=i.def.brickcraft_teeth
          local u=canon(i.axis)
          gears_near(p,na,i.axis,function(q,gi,meshes)
            if not meshes then return end
            local nb=gi.def.brickcraft_teeth
            -- The driven gear turns the other way, na/nb as fast; its teeth start between
            -- the driver's where they touch (a tooth of the driver toward it, a gap back).
            local d=vector.direction(p,q)
            local back=vector.multiply(d,-1)
            local alpha=angle(u,back)+math.pi/nb-(na/nb)*(c.alpha-angle(u,d))
            assign(q,-w*na/nb*dot(i.axis,gi.axis),alpha)
          end)
        end
      end
      for k,c in pairs(comp) do spins[k]={pos=c.pos,w=jam and 0 or c.w,alpha=c.alpha,machine=key(m)} end
      if jam then jams[#jams+1]=m end
    end
  end
  return spins,jams
end

-- Turning pieces: their invisible twin, and a spinner model turning in their place. All
-- the spinners of a machine start together, so their teeth stay in step on every client.
local active={} -- key -> {pos,w,alpha,obj}
local machines={} -- machine (its first motor's key) -> {sig=..., keys={...}}
local function rotation_for(axis,alpha)
  local u=canon(axis)
  local e1=across(u)
  local forward=vector.add(vector.multiply(e1,math.cos(alpha)),vector.multiply(vector.cross(u,e1),math.sin(alpha)))
  return vector.dir_to_rotation(forward,u)
end
local function stop(k)
  local a=active[k]
  active[k]=nil
  if a.obj and a.obj:get_pos() then a.obj:remove() end
  local node=C.get_node(a.pos)
  local def=C.registered_nodes[node.name]
  if def and def.brickcraft_still_name then C.swap_node(a.pos,{name=def.brickcraft_still_name,param2=node.param2}) end
end
local function turn(k,pos,w,alpha)
  local i=info(pos)
  if not i then return end
  if i.def.brickcraft_spin_name then
    C.swap_node(pos,{name=i.def.brickcraft_spin_name,param2=i.node.param2})
  end
  local a=active[k] or {pos=pos}
  active[k]=a
  if a.obj and a.obj:get_pos() then a.obj:remove() end
  a.w,a.alpha=w,alpha
  a.obj=C.add_entity(pos,"brickcraft:spinner")
  if not a.obj then return end
  -- The spinner turns about the line's unsigned axis: a piece lying the other way round
  -- turns the other way about it.
  a.obj:set_properties({mesh=i.def.brickcraft_spin_mesh,textures={"brickcraft_"..i.def.brickcraft_color..".png"},
    automatic_rotate=w*dot(i.axis,canon(i.axis))*2*math.pi})
  a.obj:set_rotation(rotation_for(i.axis,alpha))
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
  -- Each machine that changed (or lost a spinner) starts all its spinners again together.
  local now_machines={}
  for k,sp in pairs(spins) do
    if sp.w~=0 then
      local m=now_machines[sp.machine] or {keys={},parts={}}
      now_machines[sp.machine]=m
      m.keys[#m.keys+1]=k
    end
  end
  for id,m in pairs(now_machines) do
    table.sort(m.keys)
    for _,k in ipairs(m.keys) do m.parts[#m.parts+1]=k..("=%.4f@%.4f"):format(spins[k].w,spins[k].alpha) end
    m.sig=table.concat(m.parts,";")
    local same=machines[id] and machines[id].sig==m.sig
    if same then
      for _,k in ipairs(m.keys) do
        local a=active[k]
        if not (a and a.obj and a.obj:get_pos()) then same=false; break end
      end
    end
    if not same then
      for _,k in ipairs(m.keys) do turn(k,spins[k].pos,spins[k].w,spins[k].alpha) end
    end
  end
  machines=now_machines
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
  if GEARS[kind] then
    -- A gear has to fit: it can't overlap another gear in its plane unless they mesh.
    local crowded
    gears_near(pos,GEARS[kind],AXES[math.floor(param2/4)],function(q,gi,meshes) if not meshes then crowded=gi end end)
    if crowded then
      C.chat_send_player(placer:get_player_name(),"That gear would bump the "..crowded.def.brickcraft_teeth..
        " there. Gears that fit together: 8 right next to 24, 24 two cells from 40, two 24s on a diagonal, 8 and 40 on a diagonal.")
      return stack
    end
  end
  C.set_node(pos,node)
  stack:take_item(s.cost)
  brickcraft.remember(placer,{kind="place",pos=vector.copy(pos),node=node,drop=item.." "..s.cost})
  return stack
end

-- How fast a cell turns now (0 if still), for tests and builders.
local function spin(pos) local a=active[key(pos)]; return a and a.w or 0 end
-- For tests: how far two turning gears' teeth are from interlocking where they touch
-- (0 when a tooth of one sits in a gap of the other, in tooth turns).
local function phase_off(pa,pb)
  local a,b=active[key(pa)],active[key(pb)]
  local ia,ib=info(pa),info(pb)
  local u=canon(ia.axis)
  local na,nb=ia.def.brickcraft_teeth,ib.def.brickcraft_teeth
  local d=vector.direction(pa,pb)
  local r=(na*(a.alpha-angle(u,d))+nb*(b.alpha-angle(u,vector.multiply(d,-1))-math.pi/nb))/(2*math.pi)
  return math.abs(r-math.floor(r+.5))
end

brickcraft.technic={place=place,solve=solve,run=run,spin=spin,phase_off=phase_off,active=active,motors=motors,axis_param=axis_param,
  jammed=function() return jammed end}

-- Technic Lab: a world made once for everyone, with machines running on the baseplate to
-- the right of the start spots: a gear train on a technic wall (8, 24, 40, 24 and 8 teeth,
-- each at the spacing that meshes), a windmill, a line of axles through technic bricks into
-- two 24s on a diagonal, and two motors jammed against each other (switch one the other way
-- to free it). On the left, a coaster: a motor turns an 8 that turns a 24 beside a chain
-- lift, which pulls three cars up six levels; from the top gravity does the rest: a drop,
-- a small hill and curves back round to the lift. init.lua makes the world; LAB_VERSION
-- rebuilds an older lab once (version 3's geared train and its loop go).
local LAB_VERSION=4
local COASTER_AREA={a={x=-23,z=-6},b={x=-7,z=8}}
-- The coaster's track, cell by cell in the direction the cars go, from the station.
local function coaster_path()
  local path={}
  local function add(x,y,z) path[#path+1]={x=x,y=y,z=z} end
  for x=-9,-21,-1 do add(x,0,-4) end                      -- station, then turn north
  for i=0,5 do add(-21,i,-3+i) end                        -- chain lift, six levels up
  add(-21,6,3); add(-21,6,4)                              -- over the top, turn east
  for i=0,5 do add(-20+i,5-i,4) end                       -- the drop
  add(-14,0,4); add(-13,0,4); add(-12,1,4); add(-11,2,4)  -- up the small hill
  add(-10,1,4); add(-9,0,4)                               -- and down
  for z=4,-4,-1 do add(-8,0,z) end                        -- back to the station
  return path
end
-- Each cell's piece, from its neighbors: a ramp where the next cell is a level up (rising
-- toward it) or the cell before is (rising toward that), else a straight or a curve.
local function coaster_pieces(path,color)
  local out={}
  local function flat(a) return {x=a.x,y=0,z=a.z} end
  for i,p in ipairs(path) do
    local prev,nxt=path[(i-2)%#path+1],path[i%#path+1]
    local a,b=flat(vector.subtract(prev,p)),flat(vector.subtract(nxt,p))
    local name,param2
    if nxt.y==p.y+1 then name,param2="_track_ramp",C.dir_to_facedir(b)
    elseif prev.y==p.y+1 then name,param2="_track_ramp",C.dir_to_facedir(a)
    elseif vector.equals(a,vector.multiply(b,-1)) then name,param2="_track",C.dir_to_facedir(b)
    else
      local ra,rb=C.dir_to_facedir(a),C.dir_to_facedir(b)
      name,param2="_track_curve",(ra+1)%4==rb and ra or rb
    end
    out[i]={pos=p,name="brickcraft:"..color..name,param2=param2}
  end
  return out
end
local function build_lab(w)
  local function at(x,y,z) return {x=w.x+x,y=y,z=w.z+z} end
  for x=8,23 do for y=0,7 do for z=-4,8 do C.set_node(at(x,y,z),{name="air"}) end end end
  local function put(x,y,z,name,param2) C.set_node(at(x,y,z),{name="brickcraft:"..name,param2=param2 or 0}) end
  local Z,X,MX=axis_param({x=0,y=0,z=1}),axis_param({x=1,y=0,z=0}),axis_param({x=-1,y=0,z=0})
  -- Gear train: gears at y 2 in front of a wall; technic bricks in the wall hold their axles.
  for x=9,17 do for y=0,1 do put(x,y,4,"cream") end end
  for x=9,17 do put(x,2,4,"cream") end
  local train={{10,"gold","gear8"},{11,"coral","gear24"},{13,"sky","gear40"},{15,"coral","gear24"},{16,"gold","gear8"}}
  for _,g in ipairs(train) do put(g[1],2,4,"mint_technic_brick",0); put(g[1],2,3,g[2].."_"..g[3],Z) end
  for y=0,1 do put(9,y,2,"cream"); put(10,y,2,"cream") end
  put(9,2,2,"navy_battery_node_fwd"); put(10,2,2,"navy_motor_node",0)
  -- Windmill: a tower with the motor on top turning a big wheel toward the start spots.
  for y=0,3 do put(19,y,6,"sky"); put(19,y,7,"sky") end
  put(19,4,7,"navy_battery_node_fwd"); put(19,4,6,"navy_motor_node",2)
  put(19,4,5,"cream_axle",Z); put(19,4,4,"rose_gear40",Z)
  -- Bearing line: motor facing +x, axles through technic bricks, then two 24s on a diagonal.
  for x=10,15 do for y=0,1 do put(x,y,-2,"cream") end end
  for y=0,1 do put(10,y,-3,"cream") end
  put(10,2,-3,"navy_battery_node_fwd"); put(10,2,-2,"navy_motor_node",1)
  put(11,2,-2,"gold_axle",X); put(12,2,-2,"mint_technic_brick",1); put(13,2,-2,"gold_axle",X)
  put(14,2,-2,"mint_technic_brick",1); put(15,2,-2,"coral_gear24",X)
  for y=0,2 do put(16,y,-1,"cream") end
  put(16,3,-1,"mint_technic_brick",1); put(15,3,-1,"sky_gear24",X)
  -- Jam: two motors on one axle, both forward, so they fight.
  for x=18,21 do put(x,0,-3,"cream") end
  put(18,0,-4,"cream"); put(21,0,-4,"cream")
  put(18,1,-4,"navy_battery_node_fwd"); put(18,1,-3,"navy_motor_node",1)
  put(19,1,-3,"violet_axle",X); put(20,1,-3,"violet_axle",MX)
  put(21,1,-4,"navy_battery_node_fwd"); put(21,1,-3,"navy_motor_node",3)
  -- The coaster (its cars go on when someone first comes by: tick below). Version 3's
  -- geared train and its loop were here: their carts go too, when their area wakes.
  local ca,cb=at(COASTER_AREA.a.x,0,COASTER_AREA.a.z),at(COASTER_AREA.b.x,9,COASTER_AREA.b.z)
  for x=ca.x,cb.x do for y=0,9 do for z=ca.z,cb.z do C.set_node({x=x,y=y,z=z},{name="air"}) end end end
  brickcraft.trains.clear_carts(vector.offset(ca,0,-1,0),cb)
  local pieces=coaster_pieces(coaster_path(),"coral")
  for _,pc in ipairs(pieces) do
    local pos=at(pc.pos.x,pc.pos.y,pc.pos.z)
    C.set_node(pos,{name=pc.name,param2=pc.param2})
    for y=0,pc.pos.y-1 do C.set_node(at(pc.pos.x,y,pc.pos.z),{name="brickcraft:tan"}) end -- supports
  end
  -- The lift is the six ramps after the station: chain lift pieces. Its drive: a motor
  -- facing +x turns an 8, which turns a 24 beside the lift's second piece.
  for _,pc in ipairs(pieces) do
    if pc.name:find("_track_ramp$") and pc.pos.x==-21 then
      C.set_node(at(pc.pos.x,pc.pos.y,pc.pos.z),{name="brickcraft:coral_track_lift",param2=pc.param2})
    end
  end
  put(-23,0,-1,"cream"); put(-23,0,0,"cream")
  put(-23,1,0,"navy_battery_node_fwd"); put(-23,1,-1,"navy_motor_node",1)
  put(-22,1,-1,"gold_gear8",X); put(-22,1,-2,"coral_gear24",X)
  storage:set_int("lab_coaster_"..w.id,0)
  C.log("action","BrickCraft Technic Lab machines built at "..w.x..","..w.z)
  changed()
  return LAB_VERSION
end
brickcraft.technic.lab_version=LAB_VERSION
-- The coaster's cars go on when a player is near (its area must be loaded).
local lab_timer=0
C.register_globalstep(function(dt)
  lab_timer=lab_timer+dt
  if lab_timer<2 then return end
  lab_timer=0
  for _,w in ipairs(brickcraft.worlds()) do
    if w.technic and (tonumber(w.machines) or 0)>=4 and storage:get_int("lab_coaster_"..w.id)==0 then
      for _,pl in ipairs(C.get_connected_players()) do
        local p=pl:get_pos()
        if math.abs(p.x-w.x)<40 and math.abs(p.z-w.z)<40 then
          local z=w.z-4
          local cars=brickcraft.trains.put_coaster({{x=w.x-18,y=0,z=z},{x=w.x-17,y=0,z=z},{x=w.x-16,y=0,z=z}},
            {"gold","mint","sky"},3)
          if #cars==3 then
            storage:set_int("lab_coaster_"..w.id,1)
            C.log("action","BrickCraft Technic Lab coaster cars put on the track")
          end
          break
        end
      end
    end
  end
end)
brickcraft.technic.coaster_path=coaster_path
brickcraft.technic.build_lab=build_lab

if C.settings:get_bool("brickcraft_technic_test",false) then
  dofile(C.get_modpath("brickcraft").."/technic_test.lua")
end
