-- Train pieces: track, cart, train motor and battery box. They are pieces like any other
-- (the Trains row, Tab or I): hold a color and right click to place one, the separator
-- collects it and right clicks to turn it (or to switch a battery box).
-- Track pieces are nodes that know their two ends from their shape and turn; new track
-- joins the track next to it by itself (turning a loose neighbor to meet it). A cart is an
-- entity that follows those ends cell to cell, like advtrains rather than the engine's
-- physics: it keeps the cell it is in, the end it came in by and how far along it is, and
-- works out its spot on the straight or quarter-circle centerline every step.
-- Track is 1 cell (2 studs) wide; real track is 8 studs wide, see README.
local C=core
local CART,PART="brickcraft:cart","brickcraft:cart_part"
local colors={}
for _,color in ipairs(brickcraft.colors) do colors[color]=true end
-- Cells per second, and cells per second each second.
local MAX_SPEED,ACCEL,FRICTION,MOTOR_SPEED=5,3,.6,3
-- On ramps gravity pulls a car along the track (cells per second each second, times the
-- slope), up to FAST. A chain lift pulls cars up at LIFT_PER_TURN cells per second for each
-- turn per second of the fastest gear or axle touching its run of lift pieces.
local GRAVITY,FAST,LIFT_PER_TURN=6,12,6
-- A booster (Mesecons powered track) pushes a car its way up to BOOST; unpowered it brakes.
local BOOST,BOOST_ACCEL,BRAKE=4,4,8
-- A locomotive's gearbox: the motor's gear drives the gear on the drive wheels' axle, so
-- the wheels turn motor_teeth/wheel_teeth as fast as the motor. The motor turns
-- MOTOR_RPS times a second and a drive wheel is WHEEL_R cells in radius, so 24 to 24 runs
-- at MOTOR_SPEED, 8 to 24 at a third of it and 24 to 8 at three times (up to GEARED_MAX).
-- The gears are drawn at GEAR_SCALE of their real size on the locomotive's left side.
local WHEEL_R,GEAR_SCALE,GEARED_MAX=.2,.3,7
local MOTOR_RPS=MOTOR_SPEED/(2*math.pi*WHEEL_R)
local AXLE={x=-.5,y=-.12,z=-.15} -- the wheel gear's center, in the cart's frame (front +z)

local function D(r) return C.facedir_to_dir(r%4) end
local function same(a,b) return a.x==b.x and a.z==b.z end
local function neg(d) return {x=-d.x,y=0,z=-d.z} end
local function track_name(color,kind) return "brickcraft:"..color..(kind=="curve" and "_track_curve" or "_track") end
-- The two directions a track node opens toward, or nil for anything else.
-- A straight turned r runs r and r+2; a curve turned r joins r and r+1.
local function ends_of(node)
  local def=C.registered_nodes[node.name]
  local kind=def and def.brickcraft_track
  local r=node.param2%4
  if kind=="straight" then return {D(r),D(r+2)} end
  if kind=="curve" then return {D(r),D(r+1)} end
end
local function track_ends(pos) return ends_of(C.get_node(pos)) end
local function opens(e,d) return e~=nil and (same(e[1],d) or same(e[2],d)) end
local function exit_of(e,a) return same(e[1],a) and e[2] or e[1] end
-- Ends of the track at pos that meet another piece's end.
local function joined(pos)
  local out={}
  for _,d in ipairs(track_ends(pos) or {}) do
    if opens(track_ends(vector.add(pos,d)),neg(d)) then out[#out+1]=d end
  end
  return out
end
-- The piece opening toward up to two directions; a lone piece runs the way you look.
local function piece_for(color,dirs,look)
  local a,b=dirs[1],dirs[2]
  if not a then return {name=track_name(color),param2=C.dir_to_facedir(look)} end
  local ra=C.dir_to_facedir(a)
  if not b or same(b,neg(a)) then return {name=track_name(color),param2=ra} end
  local rb=C.dir_to_facedir(b)
  return {name=track_name(color,"curve"),param2=(ra+1)%4==rb and ra or rb}
end

-- Lays track of a color at pos joined to up to two neighbors: ends already pointing here
-- count most, then loose pieces (at most one end joined) that can turn to meet it, then
-- going straight. Neighbors turn to match and keep their own color.
local function lay(pos,look,color)
  local cands={}
  for r=0,3 do
    local d=D(r)
    local n=vector.add(pos,d)
    local e=track_ends(n)
    if opens(e,neg(d)) then cands[#cands+1]={d=d,ready=true}
    elseif e and #joined(n)<=1 then cands[#cands+1]={d=d,n=n} end
  end
  local best,score={},0
  for i=1,#cands do
    for j=i,#cands do
      local a,b=cands[i],j>i and cands[j] or nil
      local s=(a.ready and 4 or 1)+(b and (b.ready and 4 or 1)+(same(a.d,neg(b.d)) and 1 or 0) or 0)
      if s>score then best,score={a,b},s end
    end
  end
  local dirs={}
  for _,c in ipairs(best) do
    dirs[#dirs+1]=c.d
    if c.n then
      local ncolor=C.registered_nodes[C.get_node(c.n).name].brickcraft_color
      C.swap_node(c.n,piece_for(ncolor,{neg(c.d),joined(c.n)[1]}))
    end
  end
  local node=piece_for(color,dirs,look)
  C.set_node(pos,node)
  return node
end

-- Track nodes in every color: ties in the brick's color under light rails.
local track_box={type="fixed",fixed={-.5,-.5,-.5,.5,-.32,.5}}
for color in pairs(colors) do
  for _,kind in ipairs({"straight","curve"}) do
    C.register_node(":"..track_name(color,kind),{
      description="Train Track ("..kind..")\nPart "..(kind=="curve" and "53400" or "53401").." (1 cell here)",
      drawtype="mesh",mesh="brickcraft_track_"..kind..".obj",
      -- Culling off: a flipped mesh (see generate_assets.py) can't lose its faces.
      tiles={{name="brickcraft_"..color..".png",backface_culling=false},{name="brickcraft_track_rail.png",backface_culling=false}},
      paramtype="light",paramtype2="facedir",sunlight_propagates=true,
      collision_box=track_box,selection_box=track_box,
      -- brick: the separator collects it (one brick back) and turns it like any brick.
      groups={brick=1,track=1,not_in_creative_inventory=1},drop="brickcraft:"..color,
      brickcraft_shape="track",brickcraft_track=kind,brickcraft_color=color,
    })
  end
end
-- Ramps rise one level over one cell toward their turn (+z unturned); a chain lift is a
-- ramp with a chain between the rails that a turning gear or axle beside it drives.
local ramp_box={type="fixed",fixed={{-.5,-.5,-.5,.5,-.18,0},{-.5,-.5,0,.5,.32,.5}}}
for color in pairs(colors) do
  for _,kind in ipairs({"ramp","lift"}) do
    C.register_node(":brickcraft:"..color.."_track_"..kind,{
      description=kind=="lift" and "Chain Lift (track ramp)" or "Track Ramp",
      drawtype="mesh",mesh="brickcraft_track_"..kind..".obj",
      tiles={{name="brickcraft_"..color..".png",backface_culling=false},{name="brickcraft_track_rail.png",backface_culling=false},
        {name="brickcraft_cart_wheel.png",backface_culling=false}},
      paramtype="light",paramtype2="facedir",sunlight_propagates=true,
      collision_box=ramp_box,selection_box=ramp_box,
      groups={brick=1,track=1,not_in_creative_inventory=1},drop="brickcraft:"..color,
      brickcraft_shape="track",brickcraft_track="ramp",brickcraft_lift=kind=="lift" or nil,brickcraft_color=color,
    })
  end
end
-- Boosters: straight track that a Mesecons signal powers (lit rails). Powered, it pushes a
-- car the way it is turned (its first end); unpowered, it brakes the car to a stop and
-- holds it. A coaster's station uses them to wait for a ride and release the train.
for color in pairs(colors) do
  for _,on in ipairs({false,true}) do
    local name="brickcraft:"..color.."_track_booster"..(on and "_on" or "")
    local def={
      description="Booster Track (Mesecons powered)",
      drawtype="mesh",mesh="brickcraft_track_straight.obj",
      tiles={{name="brickcraft_"..color..".png",backface_culling=false},
        {name="brickcraft_track_rail.png^[colorize:"..(on and "#ffd34d:170" or "#d8402c:150"),backface_culling=false}},
      paramtype="light",paramtype2="facedir",sunlight_propagates=true,
      collision_box=track_box,selection_box=track_box,
      groups={brick=1,track=1,not_in_creative_inventory=1},drop="brickcraft:"..color,
      brickcraft_shape="track",brickcraft_track="straight",brickcraft_color=color,
      brickcraft_booster=on and "on" or "off",
    }
    if C.global_exists("mesecon") then
      local function set(to) return function(pos,node)
        C.swap_node(pos,{name="brickcraft:"..color.."_track_booster"..to,param2=node.param2})
      end end
      def.mesecons={effector={action_on=set("_on"),action_off=set("")}}
    end
    C.register_node(":"..name,def)
  end
end
-- Track and carts from before trains were pieces: old track is navy now, and the old train
-- items in inventories become bricks.
C.register_alias("brickcraft:track_straight","brickcraft:navy_track")
C.register_alias("brickcraft:track_curve","brickcraft:navy_track_curve")
C.register_alias("brickcraft:track","brickcraft:navy")
C.register_alias("brickcraft:cart","brickcraft:coral")
C.register_alias("brickcraft:train_motor","brickcraft:navy")
C.register_alias("brickcraft:battery_box","brickcraft:navy")

-- Where carts run. Each end of a piece is a direction d out of its cell and the height h
-- of the joint there (0 at the cell's level; 1 at a ramp's top end, a level up). Pieces
-- join where their joints meet: a ramp's top joins the piece a level up, and a piece
-- leads down onto a ramp whose top meets it.
local function path_ends(pos)
  local node=C.get_node(pos)
  local def=C.registered_nodes[node.name]
  local kind=def and def.brickcraft_track
  local r=node.param2%4
  if kind=="straight" then return {{d=D(r),h=0},{d=D(r+2),h=0}} end
  if kind=="curve" then return {{d=D(r),h=0},{d=D(r+1),h=0}} end
  if kind=="ramp" then return {{d=D(r+2),h=0},{d=D(r),h=1}} end
end
local function same_end(a,b) return same(a.d,b.d) and a.h==b.h end
local function has_end(e,a) return e~=nil and a~=nil and a.d~=nil and (same_end(e[1],a) or same_end(e[2],a)) end
local function other_end(e,a) return same_end(e[1],a) and e[2] or e[1] end
local function joint(pos,e) return {x=pos.x+.5*e.d.x,y=pos.y+e.h,z=pos.z+.5*e.d.z} end
-- The piece past end e of the piece at pos, and its end there; nil at the end of the line.
local function across(pos,e)
  local j=joint(pos,e)
  for _,dy in ipairs({0,-1,1}) do
    local q={x=pos.x+e.d.x,y=pos.y+dy,z=pos.z+e.d.z}
    for _,f in ipairs(path_ends(q) or {}) do
      if vector.equals(joint(q,f),j) then return q,f end
    end
  end
end
-- Where a cart s cells into a piece is, entering by end a and leaving by end b, and which
-- way it moves. A curve's centerline is a quarter circle (radius 0.5) round the corner
-- between its ends; a ramp's runs straight from joint to joint.
local CURVE_LEN=math.pi/4
local function length(a,b)
  if a.h~=b.h then return math.sqrt(2) end
  return same(a.d,neg(b.d)) and 1 or CURVE_LEN
end
local function centerline(cell,a,b,s)
  if a.h~=b.h then
    local ja,jb=joint(cell,a),joint(cell,b)
    local dv=vector.subtract(jb,ja)
    return vector.add(ja,vector.multiply(dv,s/math.sqrt(2))),vector.normalize(dv)
  end
  local ad,bd=a.d,b.d
  if same(ad,neg(bd)) then
    return {x=cell.x+.5*(ad.x*(1-s)+bd.x*s),y=cell.y,z=cell.z+.5*(ad.z*(1-s)+bd.z*s)},{x=bd.x,y=0,z=bd.z}
  end
  local th=s/CURVE_LEN*math.pi/2
  local c,sn=math.cos(th),math.sin(th)
  local cx,cz=cell.x+.5*(ad.x+bd.x),cell.z+.5*(ad.z+bd.z)
  return {x=cx-.5*(bd.x*c+ad.x*sn),y=cell.y,z=cz-.5*(bd.z*c+ad.z*sn)},
    {x=bd.x*sn-ad.x*c,y=0,z=bd.z*sn-ad.z*c}
end
-- A cart saved before ramps kept the end it came in by as a bare direction.
local function as_end(a) if a and not a.d then return {d=a,h=0} end return a end
-- How fast the chain lift under a cell pulls (nil if it isn't a lift or nothing turns it):
-- the fastest gear or axle touching any piece of its run of lift pieces.
local function lift_speed(cell)
  local def=C.registered_nodes[C.get_node(cell).name]
  if not (def and def.brickcraft_lift) or not brickcraft.technic then return end
  local best,seen,todo=0,{},{vector.copy(cell)}
  while #todo>0 do
    local p=table.remove(todo)
    local k=p.x..","..p.y..","..p.z
    if not seen[k] then
      seen[k]=true
      for _,d in ipairs({{x=1,y=0,z=0},{x=-1,y=0,z=0},{x=0,y=1,z=0},{x=0,y=-1,z=0},{x=0,y=0,z=1},{x=0,y=0,z=-1}}) do
        best=math.max(best,math.abs(brickcraft.technic.spin(vector.add(p,d))))
      end
      for _,e in ipairs(path_ends(p) or {}) do
        local q=across(p,e)
        local qd=q and C.registered_nodes[C.get_node(q).name]
        if qd and qd.brickcraft_lift then todo[#todo+1]=q end
      end
    end
  end
  return best>0 and best*LIFT_PER_TURN or nil
end
local function approach(v,target,step)
  if v<target then return math.min(v+step,target) end
  return math.max(v-step,target)
end

-- Carts loaded now, by id, so coupled cars can find the car they follow.
local carts={}
-- Areas whose older carts are taken away when they wake ({a,b,t}), kept in mod storage.
local storage=brickcraft.storage
local clearings=C.deserialize(storage:get_string("cart_clearings")) or {}
local function clear_carts(a,b)
  local t=os.time()
  clearings[#clearings+1]={a=vector.copy(a),b=vector.copy(b),t=t}
  storage:set_string("cart_clearings",C.serialize(clearings))
  for _,o in ipairs(C.get_objects_in_area(a,b)) do
    local ent=o:get_luaentity()
    if ent and ent.name==CART and (ent._born or 0)<t then o:remove() end
  end
end
local GAP=1 -- coupled cars run this far apart, center to center
-- How far b is from a along the track, ahead of a's way of travel (behind: negative),
-- or nil when it isn't within `far` cells either way.
local function gap(a,b,far)
  local function walk(cell,from,s)
    local e=path_ends(cell)
    local to=other_end(e,from)
    local len,acc=length(from,to),-s
    for _=1,far+2 do
      if vector.equals(cell,b._cell) then
        local d=acc+((b._from and b._from.d and same_end(b._from,from)) and (b._s or len/2) or len-(b._s or len/2))
        if d>=0 then return d<=far and d or nil end
      end
      acc=acc+len
      if acc>far then return end
      local nxt,nf=across(cell,to)
      if not nxt then return end
      cell,from=nxt,nf
      to=other_end(path_ends(cell),from); len=length(from,to)
    end
  end
  local e=path_ends(a._cell)
  if not (has_end(e,a._from) and b._cell) then return end
  local s=a._s or .5
  local d=walk(a._cell,a._from,s)
  if d then return d end
  local to=other_end(e,a._from)
  d=walk(a._cell,to,length(a._from,to)-s)
  return d and -d
end
-- Whether a follows b, directly or down the line of cars.
local function follows(a,b)
  for _=1,32 do
    if not (a and a._leader) then return false end
    if a._leader==b._id then return true end
    local o=carts[a._leader]
    a=o and o:get_luaentity()
  end
end
-- Couples two cars that meet: b hooks on behind a if it can, else a behind b. A car
-- with a motor never follows, and a car already following stays with its own.
local function hook(a,b)
  local function can(x,y) return not x._leader and not x._motor and not follows(y,x) end
  if can(b,a) then b._leader=a._id; return true end
  if can(a,b) then a._leader=b._id; return true end
end
-- Other carts within reach of this one's spot.
local function near(self,r)
  local out={}
  for _,o in ipairs(C.get_objects_inside_radius(self.object:get_pos(),r)) do
    local ent=o:get_luaentity()
    if ent and ent.name==CART and ent~=self then out[#out+1]=ent end
  end
  return out
end

-- A motor and a battery box fit onto a cart in a brick color and show as their own models
-- riding on it. The battery box's switch steps one notch each time the separator right
-- clicks the locomotive: forward, off, back, off.
local LIGHT={[1]="brickcraft_mint.png",[0]="brickcraft_coral.png",[-1]="brickcraft_gold.png"}
local SWITCH_WORDS={[1]="forward",[0]="off",[-1]="back"}
-- Carts and parts from before trains were pieces had no color.
local function color_of(v,default) return type(v)=="string" and v or default end
local function geared(self) return self._gear_m and self._gear_w end
local function gear_r(teeth) return teeth/32*GEAR_SCALE end
local function show_parts(self)
  self._parts=self._parts or {}
  local box=geared(self)
  for kind,on in pairs({motor=self._motor,battery=self._battery,coach=self._coach,
      gear_m=box,gear_w=box,wheel_l=box,wheel_r=box}) do
    local part=self._parts[kind]
    if on and not (part and part:get_pos()) then
      part=C.add_entity(self.object:get_pos(),PART)
      if part then
        -- Gears and drive wheels lie across the cart (their y axis along its x).
        local at,rot={x=0,y=0,z=0},{x=0,y=0,z=0}
        if kind=="gear_w" then at,rot=AXLE,{x=0,y=0,z=90}
        elseif kind=="gear_m" then
          at,rot={x=AXLE.x,y=AXLE.y,z=AXLE.z+gear_r(self._gear_m.teeth)+gear_r(self._gear_w.teeth)},{x=0,y=0,z=90}
        elseif kind=="wheel_l" or kind=="wheel_r" then
          at,rot={x=kind=="wheel_l" and -.42 or .42,y=AXLE.y,z=AXLE.z},{x=0,y=0,z=90}
        end
        part:set_attach(self.object,"",vector.multiply(at,10),rot)
        self._parts[kind]=part
        self._spun=nil
      end
    end
    if part and part:get_pos() then
      if not on then part:remove()
      elseif kind=="motor" then
        part:set_properties({mesh="brickcraft_train_motor.obj",textures={"brickcraft_"..color_of(on,"navy")..".png"},pointable=false})
      elseif kind=="battery" then
        part:set_properties({mesh="brickcraft_battery_box.obj",
          textures={"brickcraft_"..color_of(on,"navy")..".png",LIGHT[self._power or 0]},pointable=true,
          selectionbox={-.28,-.02,-.44,.28,.31,-.12,rotate=true}})
      elseif kind=="coach" then
        part:set_properties({mesh="brickcraft_coach.obj",textures={"brickcraft_"..color_of(on,"sky")..".png","brickcraft_cream.png"},pointable=false})
      elseif kind=="gear_m" or kind=="gear_w" then
        local teeth=kind=="gear_m" and self._gear_m.teeth or self._gear_w.teeth
        part:set_properties({mesh="brickcraft_gear"..teeth..".obj",textures={"brickcraft_"..(kind=="gear_m" and self._gear_m or self._gear_w).color..".png"},
          visual_size={x=10*GEAR_SCALE,y=10*GEAR_SCALE,z=10*GEAR_SCALE},pointable=false})
      else
        part:set_properties({mesh="brickcraft_wheel.obj",textures={"brickcraft_cart_wheel.png"},
          visual_size={x=20*WHEEL_R,y=20*WHEEL_R,z=20*WHEEL_R},pointable=false})
      end
    end
  end
end
-- The gearbox turns with the wheels: the drive wheels and their gear at the wheels' speed,
-- the motor's gear the other way, wheel_teeth/motor_teeth as fast. Sent only on a change.
local function spin_gearbox(self,front)
  if not geared(self) then return end
  local wheel=front/(2*math.pi*WHEEL_R)*2*math.pi -- radians per second
  if self._spun and math.abs(self._spun-wheel)<.02 then return end
  self._spun=wheel
  local p=self._parts
  for _,k in ipairs({"wheel_l","wheel_r","gear_w"}) do
    if p[k] and p[k]:get_pos() then p[k]:set_properties({automatic_rotate=wheel}) end
  end
  if p.gear_m and p.gear_m:get_pos() then
    p.gear_m:set_properties({automatic_rotate=-wheel*self._gear_w.teeth/self._gear_m.teeth})
  end
end
-- How fast a switched-on locomotive goes: straight from the motor, or through its gears.
local function motor_speed(self)
  if not geared(self) then return MOTOR_SPEED end
  return math.min(GEARED_MAX,MOTOR_RPS*self._gear_m.teeth/self._gear_w.teeth*2*math.pi*WHEEL_R)
end
-- A Gear piece on a locomotive: the first goes on the motor, the second on the wheels.
local function fit_gear(self,player,s,color)
  local name=player:get_player_name()
  if not self._motor then C.chat_send_player(name,"Put a Train Motor on first: the gears go between the motor and the wheels."); return end
  if geared(self) then C.chat_send_player(name,"This locomotive has both its gears. Collect it to change them."); return end
  local stack=player:get_wielded_item()
  if stack:get_count()<s.cost then return end
  stack:take_item(s.cost); player:set_wielded_item(stack)
  local gear={teeth=tonumber(s.technic:match("%d+")),color=color}
  if not self._gear_m then
    self._gear_m=gear
    C.chat_send_player(name,"A "..gear.teeth.." on the motor. Now a gear for the wheels (right click again with a Gear).")
    return
  end
  self._gear_w=gear
  show_parts(self)
  local a,b=self._gear_m.teeth,self._gear_w.teeth
  C.chat_send_player(name,("Gearbox: %d on the motor drives %d on the wheels, so the wheels turn %s as fast: %.1f cells a second."):format(
    a,b,a==b and "just" or (a<b and ("1/"..math.floor(b/a+.5)) or tostring(math.floor(a/b+.5)).." times"),motor_speed(self)))
end
-- Puts a motor or battery box piece (shape s) in a color on the cart, from the held stack.
local function fit(self,player,s,color)
  local name=player:get_player_name()
  local field=s.train=="motor" and "_motor" or "_battery"
  if self[field] then C.chat_send_player(name,"This cart has a "..s.label.." already."); return end
  local stack=player:get_wielded_item()
  if stack:get_count()<s.cost then C.chat_send_player(name,"A "..s.label.." needs "..s.cost.." bricks of this color."); return end
  stack:take_item(s.cost); player:set_wielded_item(stack)
  if field=="_motor" then self._leader=nil end -- a locomotive leads
  self[field]=color
  show_parts(self)
  C.chat_send_player(name,field=="_motor" and
    (self._battery and "Motor on: it's a locomotive! Right click it with the separator to switch it on."
      or "Motor on: it's a locomotive! Put a Battery Box on it to power the motor.")
    or "Battery box on. Right click it with the separator to switch: forward, off, back."..
      (self._motor and "" or " It needs a Train Motor to go."))
end
local function switch(self,player)
  if (self._power or 0)~=0 then self._power=0
  else self._power=self._last==1 and -1 or 1; self._last=self._power end
  show_parts(self)
  if player and player:is_player() then
    C.chat_send_player(player:get_player_name(),"Switch: "..SWITCH_WORDS[self._power]..
      ((self._power~=0 and not self._motor) and " (no motor: put a Train Motor on the cart)" or ""))
  end
end

-- The separator collects a cart: its bricks back, and the motor's and battery box's.
local function collect(self,player)
  local inv=player:get_inventory()
  local function give(color,n)
    local left=inv:add_item("main","brickcraft:"..color.." "..n)
    if not left:is_empty() then C.add_item(self.object:get_pos(),left) end
  end
  give(color_of(self._color,"coral"),self._coach and brickcraft.shapes.coach.cost or brickcraft.shapes.cart.cost)
  for _,g in ipairs({self._gear_m,self._gear_w}) do give(g.color,1) end
  if self._motor then give(color_of(self._motor,"navy"),brickcraft.shapes.motor.cost) end
  if self._battery then give(color_of(self._battery,"navy"),brickcraft.shapes.battery.cost) end
  self.object:remove()
end

-- Riding: a player who jumps onto the deck rides along; Space hops off to the side.
local hopped={} -- name -> time they hopped off, so they don't land straight back on
local function hop_off(self,player)
  self._driver=nil
  player:set_detach()
  hopped[player:get_player_name()]=C.get_us_time()
  local p,t=self.object:get_pos(),self._tan or {x=0,y=0,z=1}
  for _,side in ipairs({{x=-t.z,z=t.x},{x=t.z,z=-t.x}}) do
    local to={x=p.x+side.x,y=p.y,z=p.z+side.z}
    local def=C.registered_nodes[C.get_node(vector.round(to)).name]
    if def and not def.walkable then player:set_pos({x=to.x,y=p.y-.3,z=to.z}); return end
  end
  player:set_pos({x=p.x,y=p.y+1.2,z=p.z})
end
local function board(self,player)
  self._driver=player:get_player_name()
  self._jump=true -- the jump that got them on isn't the one that gets them off
  player:set_attach(self.object,"",{x=0,y=.3,z=0},{x=0,y=0,z=0})
end
-- Players who land on its deck board; players walking into it push it along.
local function people(self,tan)
  local p=self.object:get_pos()
  for _,pl in ipairs(C.get_connected_players()) do
    local q=pl:get_pos()
    local dx,dz=q.x-p.x,q.z-p.z
    local flat=math.sqrt(dx*dx+dz*dz)
    if flat<.9 and not pl:get_attach() then
      local name=pl:get_player_name()
      local vel=pl:get_velocity()
      if flat<.45 and q.y>p.y-.1 and q.y<p.y+.6 and vel.y<=.1 and not self._driver and
         C.get_us_time()-(hopped[name] or 0)>1e6 then
        board(self,pl)
      elseif q.y<p.y and q.y>p.y-.7 and dx*vel.x+dz*vel.z<0 then
        -- Walking into it: the cart takes their speed along the track.
        local along=vel.x*tan.x+vel.z*tan.z
        if math.abs(along)>.5 then return along end
      end
    end
  end
end

C.register_entity(":"..PART,{
  initial_properties={visual="mesh",mesh="brickcraft_train_motor.obj",textures={"brickcraft_navy.png"},
    visual_size={x=10,y=10},backface_culling=false,physical=false,pointable=false,static_save=false},
  -- Clicks on a part are clicks on its cart.
  on_rightclick=function(self,clicker)
    local cart=self.object:get_attach()
    local ent=cart and cart:get_luaentity()
    if ent then ent:on_rightclick(clicker) end
  end,
  on_punch=function(self,puncher)
    local cart=self.object:get_attach()
    local ent=cart and cart:get_luaentity()
    if ent then ent:on_punch(puncher) end
    return true
  end,
  on_step=function(self) if not self.object:get_attach() then self.object:remove() end end,
})

C.register_entity(":"..CART,{
  initial_properties={visual="mesh",mesh="brickcraft_cart.obj",
    textures={"brickcraft_cart_wheel.png","brickcraft_track_tie.png","brickcraft_coral.png"},
    visual_size={x=10,y=10},backface_culling=false,physical=false,pointable=true,static_save=true,
    collisionbox={-.42,-.35,-.42,.42,.1,.42},selectionbox={-.42,-.35,-.42,.42,.1,.42,rotate=true}},
  -- _cell: the track cell; _from: the end it came in by; _s: cells along the piece;
  -- _v: speed toward the other end. _flip: its front faces back the way it travels (the
  -- motor's forward is its front). _cruise: a front-ward speed to keep (tests). _color;
  -- _motor, _battery: their colors; _power: the switch (1/0/-1, _last on); _leader: the
  -- car it follows; _driver: who rides it.
  get_staticdata=function(self)
    return C.serialize({id=self._id,cell=self._cell,from=self._from,s=self._s,v=self._v,flip=self._flip,
      cruise=self._cruise,color=self._color,motor=self._motor,battery=self._battery,power=self._power,
      last=self._last,leader=self._leader,coach=self._coach,gear_m=self._gear_m,gear_w=self._gear_w,born=self._born})
  end,
  on_activate=function(self,staticdata)
    self.object:set_armor_groups({immortal=1})
    local d=C.deserialize(staticdata or "") or {}
    self._id=d.id or (tostring(C.get_us_time())..math.random(1000,9999))
    self._cell=d.cell or vector.round(self.object:get_pos())
    local e=path_ends(self._cell)
    self._from=as_end(d.from) or (e and e[1])
    self._born=d.born or 0 -- unknown: made before carts kept their age
    -- Carts in an area cleared after they were made (a world rebuilt) go when they wake.
    for _,z in ipairs(clearings) do
      local p=self.object:get_pos()
      if self._born<z.t and p.x>=z.a.x and p.x<=z.b.x and p.y>=z.a.y and p.y<=z.b.y and p.z>=z.a.z and p.z<=z.b.z then
        self._gone=true
      end
    end
    self._s,self._v,self._flip,self._cruise,self._color=d.s,d.v or 0,d.flip,d.cruise,d.color
    self._motor,self._battery,self._power,self._last,self._leader=d.motor,d.battery,d.power or 0,d.last,d.leader
    self._coach,self._gear_m,self._gear_w=d.coach,d.gear_m,d.gear_w
    carts[self._id]=self.object
  end,
  on_deactivate=function(self)
    carts[self._id]=nil
    for _,part in pairs(self._parts or {}) do if part:get_pos() then part:remove() end end
  end,
  -- Right click like on any piece: a Train Motor or Battery Box piece goes on it, and the
  -- separator switches a locomotive (or turns a plain cart around).
  on_rightclick=function(self,clicker)
    if not clicker or not clicker:is_player() then return end
    local name=clicker:get_player_name()
    local item=clicker:get_wielded_item():get_name()
    if item=="brickcraft:separator" then
      if self._battery then switch(self,clicker)
      elseif self._v==0 then self._flip=not self._flip; C.chat_send_player(name,"Turned the cart around.") end
      return
    end
    local color=item:match("^brickcraft:(%a+)$")
    local s=brickcraft.get_shape(clicker)
    if color and colors[color] then
      if s.train=="motor" or s.train=="battery" then fit(self,clicker,s,color)
      elseif s.technic and s.technic:find("^gear") then fit_gear(self,clicker,s,color)
      elseif s.train=="cart" then C.chat_send_player(name,"Put the new cart on the track next to this one: it hooks on.")
      else C.chat_send_player(name,"Pick the Train Motor or Battery Box piece (Tab) to put it on this cart.") end
    end
  end,
  on_detach_child=function(self,child)
    if child:is_player() and child:get_player_name()==self._driver then self._driver=nil end
  end,
  on_punch=function(self,puncher)
    if puncher and puncher:is_player() and not self._driver and
       puncher:get_wielded_item():get_name()=="brickcraft:separator" then
      collect(self,puncher)
    end
    return true
  end,
  on_step=function(self,dtime)
    local obj=self.object
    if self._gone then obj:remove(); return end
    if not self._parts then
      show_parts(self)
      obj:set_properties({textures={"brickcraft_cart_wheel.png","brickcraft_track_tie.png",
        "brickcraft_"..color_of(self._color,"coral")..".png"}})
    end
    local e=path_ends(self._cell)
    if not e then -- its track was collected: it rests where it is
      if self._v~=0 then self._v=0; obj:set_velocity(vector.zero()) end
      return
    end
    self._from=as_end(self._from)
    if not has_end(e,self._from) then self._from=e[1] end -- the piece was turned
    local b=other_end(e,self._from)
    local len=length(self._from,b)
    self._s=math.min(self._s or len/2,len)
    local _,tan=centerline(self._cell,self._from,b,self._s)
    local v=self._v
    local rider=self._driver and C.get_player_by_name(self._driver)
    if rider and rider:get_attach()~=obj then rider,self._driver=nil,nil end
    if rider then
      local jump=rider:get_player_control().jump
      if jump and not self._jump then hop_off(self,rider) end
      self._jump=jump
    end
    local pushed=people(self,tan)
    local leader=self._leader and carts[self._leader]
    local lent=leader and leader:get_luaentity()
    local d=lent and gap(self,lent,3)
    if lent and not d then self._leader,lent=nil,nil end -- pulled apart: unhooked
    if lent then
      -- A coupled car keeps GAP from the car it follows, at that car's speed along the
      -- track: toward this car's front when the two are on the same side of each other's way.
      local dl=gap(lent,self,3)
      local lv=dl and (d*dl<0 and lent._v or -lent._v) or 0
      v=lv+3*(d-(d>=0 and GAP or -GAP))
      if math.abs(v)<.05 then v=0 end -- settled: it stops with the car it follows
      v=math.max(-FAST-1,math.min(FAST+1,v))
    else
      -- The motor drives it; otherwise someone pushing it, or it rolls to a stop.
      local front=(self._motor and self._battery and (self._power or 0)~=0) and self._power*motor_speed(self) or self._cruise
      if front then v=approach(v,front*(self._flip and -1 or 1),ACCEL*dtime)
      elseif pushed then v=math.max(-MAX_SPEED,math.min(MAX_SPEED,pushed))
      else v=approach(v,0,FRICTION*dtime) end
      -- A booster under it pushes it the booster's way, or brakes it.
      local bnode=C.get_node(self._cell)
      local boost=(C.registered_nodes[bnode.name] or {}).brickcraft_booster
      if boost=="on" then v=approach(v,same(b.d,D(bnode.param2)) and BOOST or -BOOST,BOOST_ACCEL*dtime)
      elseif boost=="off" then v=approach(v,0,BRAKE*dtime) end
      -- Gravity along a ramp (uphill slows it, downhill speeds it up), and a running chain
      -- lift that catches it on the way up.
      v=v-GRAVITY*tan.y*dtime
      local lift=tan.y~=0 and lift_speed(self._cell)
      if lift and tan.y>0 and v<lift then v=lift end
      if lift and tan.y<0 and v>-lift then v=-lift end
      v=math.max(-FAST,math.min(FAST,v))
    end
    if v<0 then -- going back the way it came
      self._from,b=b,self._from
      self._s,v=len-self._s,-v
      self._flip=not self._flip
    end
    -- Running into another car couples them; if they can't couple, it stops short.
    if v>0 then
      for _,other in ipairs(near(self,GAP+.8)) do
        local og=other._id~=self._leader and gap(self,other,GAP+.3)
        if og and og>0 and og<GAP+.05 and not (follows(other,self) or follows(self,other)) then
          if not hook(self,other) and og<GAP then v=0 end
        end
      end
    end
    -- Move along, piece to piece; it stops at the end of the line.
    local s=self._s+v*dtime
    for _=1,16 do
      if s<=len then break end
      local nxt,nf=across(self._cell,b)
      if not nxt then s,v=len,0; break end
      self._cell,self._from=nxt,nf
      b=other_end(path_ends(nxt),nf)
      s=s-len; len=length(self._from,b)
    end
    s=math.min(s,len)
    self._s,self._v=s,v
    local p
    p,tan=centerline(self._cell,self._from,b,s)
    self._tan=tan
    -- It faces its front, tipped up or down on a ramp.
    local rot=vector.dir_to_rotation(self._flip and vector.multiply(tan,-1) or tan)
    spin_gearbox(self,self._flip and -v or v)
    local off=vector.subtract(p,obj:get_pos())
    if v==0 then
      if vector.length(off)>.01 then obj:set_pos(p) end
      obj:set_velocity(vector.zero())
      if vector.distance(obj:get_rotation(),rot)>.01 then obj:set_rotation(rot) end
      return
    end
    -- Velocity along the track keeps the motion smooth between server steps; the
    -- small pull toward the centerline takes up the difference on curves.
    if vector.length(off)>.6 then obj:set_pos(p); off=vector.zero() end
    obj:set_velocity(vector.add(vector.multiply(tan,v),vector.multiply(off,4)))
    obj:set_rotation(rot)
  end,
})

-- Puts a cart of a color on the track at pos; it hooks on behind a car next to it.
local function put_cart(pos,color,coach)
  local obj=C.add_entity(pos,CART,C.serialize({color=color,coach=coach and color or nil,born=os.time()}))
  local ent=obj and obj:get_luaentity()
  if not ent then return end
  for _,other in ipairs(near(ent,GAP+.6)) do
    if gap(ent,other,GAP+.3) and hook(other,ent) then break end
  end
  return ent
end

-- Right click with a color and a train piece (place_brick in init.lua sends them here):
-- track is laid, a cart goes on the track. Motors and battery boxes go on a cart by a right
-- click on the cart itself; on the ground they become machine blocks (brickcraft_technic).
local function place(s,stack,placer,pointed,item)
  local name=placer:get_player_name()
  local color=item:match("^brickcraft:(.+)$")
  if s.train=="track" then
    local udef=C.registered_nodes[C.get_node(pointed.under).name]
    local pos=(udef and udef.buildable_to) and pointed.under or pointed.above
    local def=C.registered_nodes[C.get_node(pos).name]
    if not (def and def.buildable_to) or pos.y<0 then return stack end
    local node=lay(pos,placer:get_look_dir(),color)
    stack:take_item(s.cost)
    brickcraft.remember(placer,{kind="place",pos=vector.copy(pos),node=node,drop=item.." "..s.cost})
    return stack
  end
  if s.train=="cart" or s.train=="coach" then
    local pos=path_ends(pointed.under) and pointed.under or pointed.above
    if not path_ends(pos) then C.chat_send_player(name,"Put the cart on a track."); return stack end
    for _,o in ipairs(C.get_objects_inside_radius(pos,.6)) do
      local ent=o:get_luaentity()
      if ent and ent.name==CART then C.chat_send_player(name,"There's a cart here already."); return stack end
    end
    local ent=put_cart(pos,color,s.train=="coach")
    if not ent then return stack end
    if ent._leader then C.chat_send_player(name,"Hooked on!") end
    stack:take_item(s.cost)
    return stack
  end
  -- A motor or battery box put on the ground drives machines (brickcraft_technic).
  return brickcraft.technic.place(s,stack,placer,pointed,item)
end

-- A locomotive (motor and battery box, switched off) in a color with cars hooked on
-- behind it, along cells (the first is the locomotive's). Returns their entities.
local function put_train(cells,color,opts)
  opts=opts or {}
  local out={}
  for i,pos in ipairs(cells) do
    local car=i>1 and opts.coach or nil
    local obj=C.add_entity(pos,CART,C.serialize({color=car or color,coach=car,born=os.time()}))
    local ent=obj and obj:get_luaentity()
    if not ent then return out end
    if i==1 then
      ent._motor,ent._battery="navy","navy"
      if opts.gears then ent._gear_m,ent._gear_w={teeth=opts.gears[1],color="gold"},{teeth=opts.gears[2],color="gold"} end
      if opts.on then ent._power,ent._last=1,1 end
    else ent._leader=out[i-1]._id end
    out[i]=ent
  end
  return out
end

-- A coaster train: plain cars in turn of colors along cells, each hooked on behind the one
-- before; the first heads away from the second at speed.
local function put_coaster(cells,colors_list,speed)
  local out={}
  for i,pos in ipairs(cells) do
    local obj=C.add_entity(pos,CART,C.serialize({color=colors_list[(i-1)%#colors_list+1],born=os.time()}))
    local ent=obj and obj:get_luaentity()
    if not ent then return out end
    if i>1 then ent._leader=out[i-1]._id end
    out[i]=ent
  end
  local lead,second=out[1],out[2]
  if lead and second then
    for _,en in ipairs(path_ends(lead._cell) or {}) do
      local q=across(lead._cell,en)
      if q and vector.equals(q,second._cell) then lead._from=en end
    end
    lead._v=speed or 0
  end
  return out
end

-- Lays a rectangle of track with corners a and b (b larger in x and z), starting mid-side
-- so the last piece closes it. Returns the cells in laying order.
local function lay_loop(a,b,color)
  local cells={}
  local function add(x,z) cells[#cells+1]={x=x,y=a.y,z=z} end
  for x=a.x+1,b.x do add(x,a.z) end
  for z=a.z+1,b.z do add(b.x,z) end
  for x=b.x-1,a.x,-1 do add(x,b.z) end
  for z=b.z-1,a.z,-1 do add(a.x,z) end
  for _,pos in ipairs(cells) do lay(pos,{x=1,y=0,z=0},color or "navy") end
  return cells
end

brickcraft.trains={lay=lay,lay_loop=lay_loop,ends=track_ends,joined=joined,exit_of=exit_of,centerline=centerline,
  path_ends=path_ends,other_end=other_end,across=across,lift_speed=lift_speed,put_coaster=put_coaster,clear_carts=clear_carts,
  gap=gap,place=place,put_cart=put_cart,put_train=put_train,switch=switch,hop_off=hop_off,carts=carts,
  motor_speed=motor_speed}
brickcraft.placers.train=place

-- The worlds (brickcraft core) this mod adds to.
local worlds,save_worlds,make_world=brickcraft.worlds(),brickcraft.save_worlds,brickcraft.make_world
local testing=brickcraft.testing

-- Train Yard: a world made once for everyone, with a 12 x 12 loop of navy track on the baseplate
-- to the right of the start spots and a train on it: a locomotive, switched off, and two
-- cars. The train goes on when someone first comes by (its area has to be loaded).
-- Test worlds skip it (but the train check).
local YARD_A,YARD_B={x=9,z=-4},{x=20,z=7}
-- The Train Yard line: a level causeway of navy track from the Workshop's west side to
-- Train Yard's east side, its long middle stretch in the empty strip between worlds
-- (x -65, outside every world's square, so worlds made later never grow hills over it).
-- It cuts through the hills (scenery only: builds are left alone), and over the gap has a
-- protected deck, railings and piers. A shuttle train waits at the Workshop end.
local function line_path(yard)
  local path={}
  for x=-25,-65,-1 do path[#path+1]={x=x,y=0,z=0} end
  for z=-1,yard.z,-1 do path[#path+1]={x=-65,y=0,z=z} end
  for x=-66,yard.x+25,-1 do path[#path+1]={x=x,y=0,z=yard.z} end
  return path
end
local building_line=false
local function build_line(yard)
  if building_line or yard.line or not yard.track then return end
  if yard.x~=-128 or yard.z~=-128 then return end -- the route assumes the first square out
  building_line=true
  local path=line_path(yard)
  C.emerge_area({x=yard.x+20,y=-8,z=yard.z-4},{x=-20,y=30,z=4},function(_,_,remaining)
    if remaining>0 then return end
    -- Every cell within 2 of the track, with how far it is from it.
    local band={}
    for _,p in ipairs(path) do
      for dz=-2,2 do for dx=-2,2 do
        local k=(p.x+dx)..","..(p.z+dz)
        local d=math.max(math.abs(dx),math.abs(dz))
        if not band[k] or d<band[k].d then band[k]={x=p.x+dx,z=p.z+dz,d=d} end
      end end
    end
    for _,c in pairs(band) do
      for y=0,26 do
        local pos={x=c.x,y=y,z=c.z}
        if C.get_item_group(C.get_node(pos).name,"scenery")>0 then C.remove_node(pos) end
      end
      local floor={x=c.x,y=-1,z=c.z}
      if C.get_node(floor).name=="air" then
        C.set_node(floor,{name="brickcraft:baseplate"})
        if c.d==2 then C.set_node({x=c.x,y=0,z=c.z},{name="brickcraft:bridge_rail"}) end
      end
    end
    for i,p in ipairs(path) do
      if i%12==0 and C.get_node({x=p.x,y=-2,z=p.z}).name=="air" then
        for y=-6,-2 do C.set_node({x=p.x,y=y,z=p.z},{name="brickcraft:baseplate"}) end
      end
    end
    local laid=0
    for i,p in ipairs(path) do
      local nxt=path[i+1] or path[i-1]
      local look=vector.subtract(nxt,p)
      if C.get_node(p).name=="air" then brickcraft.trains.lay(p,look,"navy"); laid=laid+1 end
    end
    yard.line=true; save_worlds(); building_line=false
    C.log("action","BrickCraft Train Yard line built: "..laid.." of "..#path.." pieces")
  end)
end
local function lay_train_yard(w)
  brickcraft.trains.lay_loop({x=w.x+YARD_A.x,y=0,z=w.z+YARD_A.z},{x=w.x+YARD_B.x,y=0,z=w.z+YARD_B.z})
  w.track=true; save_worlds()
  C.log("action","BrickCraft Train Yard track laid at "..w.x..","..w.z)
  build_line(w)
end
C.after(0,function()
  if testing and not C.settings:get_bool("brickcraft_train_test",false) then return end
  for _,w in ipairs(worlds) do
    if w.yard then
      if w.built and not w.track then lay_train_yard(w) else build_line(w) end
      return
    end
  end
  local w=make_world("Train Yard","BrickCraft",lay_train_yard)
  C.log("action","BrickCraft Train Yard "..(w and "being made at "..w.x..","..w.z or "has no room"))
  if w then w.yard=true; save_worlds() end
end)

local yard_timer=0
C.register_globalstep(function(dt)
  yard_timer=yard_timer+dt
  if yard_timer<2 then return end
  yard_timer=0
  for _,w in ipairs(worlds) do
    if w.yard and w.track and not w.train then
      for _,p in ipairs(C.get_connected_players()) do
        local pos=p:get_pos()
        if math.abs(pos.x-w.x)<32 and math.abs(pos.z-w.z)<32 then
          local z=w.z+YARD_B.z
          local train=brickcraft.trains.put_train({{x=w.x+17,y=0,z=z},{x=w.x+16,y=0,z=z},{x=w.x+15,y=0,z=z}},"coral")
          if #train==3 then
            w.train=true; save_worlds()
            C.log("action","BrickCraft Train Yard train put on the track")
          end
          break
        end
      end
    end
    -- The shuttle on the line: a locomotive and a car at the Workshop end.
    if w.yard and w.line and not w.shuttle then
      for _,p in ipairs(C.get_connected_players()) do
        local pos=p:get_pos()
        if math.abs(pos.x+27)<32 and math.abs(pos.z)<32 then
          local train=brickcraft.trains.put_train({{x=-28,y=0,z=0},{x=-27,y=0,z=0}},"sky")
          if #train==2 then
            w.shuttle=true; save_worlds()
            C.log("action","BrickCraft Train Yard shuttle put on the line")
          end
          break
        end
      end
    end
  end
end)
brickcraft.trains.line_path=line_path
brickcraft.trains.yard,brickcraft.trains.yard_far=YARD_A,YARD_B
