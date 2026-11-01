-- Train track and a cart that rides it.
-- Track pieces are nodes that know their two ends from their shape and turn; new track
-- joins the track next to it by itself (turning a loose neighbor to meet it). A cart is an
-- entity that follows those ends cell to cell, like advtrains rather than the engine's
-- physics: it keeps the cell it is in, the end it came in by and how far along it is, and
-- works out its spot on the straight or quarter-circle centerline every step.
-- Track is 1 cell (2 studs) wide; real track is 8 studs wide, see README.
local C=core
local TRACK,STRAIGHT,CURVE,CART="brickcraft:track","brickcraft:track_straight","brickcraft:track_curve","brickcraft:cart"
-- Cells per second, and cells per second each second.
local MAX_SPEED,ACCEL,BRAKE,FRICTION,PUSH=5,3,6,.6,3

local function D(r) return C.facedir_to_dir(r%4) end
local function same(a,b) return a.x==b.x and a.z==b.z end
local function neg(d) return {x=-d.x,y=0,z=-d.z} end
-- The two directions a track node opens toward, or nil for anything else.
-- A straight turned r runs r and r+2; a curve turned r joins r and r+1.
local function ends_of(node)
  local r=node.param2%4
  if node.name==STRAIGHT then return {D(r),D(r+2)} end
  if node.name==CURVE then return {D(r),D(r+1)} end
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
local function piece_for(dirs,look)
  local a,b=dirs[1],dirs[2]
  if not a then return {name=STRAIGHT,param2=C.dir_to_facedir(look)} end
  local ra=C.dir_to_facedir(a)
  if not b or same(b,neg(a)) then return {name=STRAIGHT,param2=ra} end
  local rb=C.dir_to_facedir(b)
  return {name=CURVE,param2=(ra+1)%4==rb and ra or rb}
end

-- Lays track at pos joined to up to two neighbors: ends already pointing here count most,
-- then loose pieces (at most one end joined) that can turn to meet it, then going straight.
local function lay(pos,look)
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
    if c.n then C.swap_node(c.n,piece_for({neg(c.d),joined(c.n)[1]})) end
  end
  local node=piece_for(dirs,look)
  C.set_node(pos,node)
  return node
end

local function place_track(stack,placer,pointed)
  if pointed.type~="node" or not placer or not placer:is_player() then return stack end
  local udef=C.registered_nodes[C.get_node(pointed.under).name]
  local pos=(udef and udef.buildable_to) and pointed.under or pointed.above
  local def=C.registered_nodes[C.get_node(pos).name]
  if not (def and def.buildable_to) or pos.y<0 then return stack end
  local node=lay(pos,placer:get_look_dir())
  stack:take_item(1)
  brickcraft.remember(placer,{kind="place",pos=vector.copy(pos),node=node,drop=TRACK})
  return stack
end

C.register_craftitem(TRACK,{
  description="Train Track\nRight click: lay track (it joins the track next to it)\n"..
    "Separator: left click collects, right click turns a piece",
  inventory_image="brickcraft_track_item.png",stack_max=999,range=7,
  on_place=place_track,
  on_drop=function(stack) return stack end, -- Q never throws track into the world
})
local track_box={type="fixed",fixed={-.5,-.5,-.5,.5,-.32,.5}}
for name,piece in pairs({[STRAIGHT]={"straight","53401"},[CURVE]={"curve","53400"}}) do
  C.register_node(name,{
    description="Train Track ("..piece[1]..")\nPart "..piece[2].." (1 cell here)",
    drawtype="mesh",mesh="brickcraft_track_"..piece[1]..".obj",
    -- Culling off: a flipped mesh (see generate_assets.py) can't lose its faces.
    tiles={{name="brickcraft_track_tie.png",backface_culling=false},{name="brickcraft_track_rail.png",backface_culling=false}},
    paramtype="light",paramtype2="facedir",sunlight_propagates=true,
    collision_box=track_box,selection_box=track_box,
    -- brick: the separator collects and turns it like any brick.
    groups={brick=1,track=1,not_in_creative_inventory=1},drop=TRACK,brickcraft_shape="track",
  })
end

-- Where a cart s cells into a piece is, entering by end a and leaving by end b, and which
-- way it moves. A curve's centerline is a quarter circle (radius 0.5) round the corner
-- between its ends.
local CURVE_LEN=math.pi/4
local function length(a,b) return same(a,neg(b)) and 1 or CURVE_LEN end
local function centerline(cell,a,b,s)
  if same(a,neg(b)) then
    return {x=cell.x+.5*(a.x*(1-s)+b.x*s),y=cell.y,z=cell.z+.5*(a.z*(1-s)+b.z*s)},{x=b.x,y=0,z=b.z}
  end
  local th=s/CURVE_LEN*math.pi/2
  local c,sn=math.cos(th),math.sin(th)
  local cx,cz=cell.x+.5*(a.x+b.x),cell.z+.5*(a.z+b.z)
  return {x=cx-.5*(b.x*c+a.x*sn),y=cell.y,z=cz-.5*(b.z*c+a.z*sn)},
    {x=b.x*sn-a.x*c,y=0,z=b.z*sn-a.z*c}
end
local function approach(v,target,step)
  if v<target then return math.min(v+step,target) end
  return math.max(v-step,target)
end

local function dismount(self,player)
  self._driver=nil
  player:set_detach()
  local p=self.object:get_pos()
  player:set_pos({x=p.x,y=p.y-.3,z=p.z})
end

C.register_entity(CART,{
  initial_properties={visual="mesh",mesh="brickcraft_cart.obj",
    textures={"brickcraft_cart_wheel.png","brickcraft_track_tie.png","brickcraft_coral.png"},
    visual_size={x=10,y=10},backface_culling=false,physical=false,pointable=true,static_save=true,
    collisionbox={-.42,-.35,-.42,.42,.1,.42},selectionbox={-.42,-.35,-.42,.42,.1,.42}},
  -- _cell: the track cell; _from: the end it came in by; _s: cells along the piece;
  -- _v: speed toward the other end; _cruise: a speed to keep without a driver (motors, tests).
  get_staticdata=function(self)
    return C.serialize({cell=self._cell,from=self._from,s=self._s,v=self._v,cruise=self._cruise})
  end,
  on_activate=function(self,staticdata)
    self.object:set_armor_groups({immortal=1})
    local d=C.deserialize(staticdata or "") or {}
    self._cell=d.cell or vector.round(self.object:get_pos())
    self._from,self._s,self._v,self._cruise=d.from,d.s,d.v or 0,d.cruise
  end,
  on_rightclick=function(self,clicker)
    if not clicker or not clicker:is_player() then return end
    local name=clicker:get_player_name()
    if self._driver==name then dismount(self,clicker); return end
    if self._driver then C.chat_send_player(name,"Someone is riding this cart."); return end
    if clicker:get_attach() then return end
    self._driver=name
    self._sneak=true -- a U still held from before must not get them straight off
    clicker:set_attach(self.object,"",{x=0,y=.3,z=0},{x=0,y=0,z=0})
    C.chat_send_player(name,"All aboard! W: go the way you look   S: brake   U or right click: get off")
  end,
  on_detach_child=function(self,child)
    if child:is_player() and child:get_player_name()==self._driver then self._driver=nil end
  end,
  on_punch=function(self,puncher)
    if not puncher or not puncher:is_player() or self._driver then return true end
    if puncher:get_wielded_item():get_name()=="brickcraft:separator" then
      local inv=puncher:get_inventory()
      if not inv:room_for_item("main",CART) then
        C.chat_send_player(puncher:get_player_name(),"Inventory full: no room for the cart.")
      else
        inv:add_item("main",CART); self.object:remove()
      end
      return true
    end
    -- Anything else gives it a push the way the player looks.
    local look,t=puncher:get_look_dir(),self._tan or {x=0,y=0,z=1}
    self._v=(look.x*t.x+look.z*t.z>=0 and 1 or -1)*PUSH
    return true
  end,
  on_step=function(self,dtime)
    local obj=self.object
    local e=track_ends(self._cell)
    if not e then -- its track was collected: it rests where it is
      if self._v~=0 then self._v=0; obj:set_velocity(vector.zero()) end
      return
    end
    if not (self._from and opens(e,self._from)) then self._from=e[1] end -- the piece was turned
    local b=exit_of(e,self._from)
    local len=length(self._from,b)
    self._s=math.min(self._s or len/2,len)
    local _,tan=centerline(self._cell,self._from,b,self._s)
    -- A rider's W or S wins; otherwise it keeps its cruise speed, or rolls to a stop.
    local v=self._v
    local driver=self._driver and C.get_player_by_name(self._driver)
    if driver and driver:get_attach()~=obj then driver,self._driver=nil,nil end
    local ctrl=driver and driver:get_player_control() or {}
    if driver then
      if ctrl.sneak and not self._sneak then dismount(self,driver); driver,ctrl=nil,{} end
      self._sneak=ctrl.sneak
    end
    if ctrl.up then
      local look=driver:get_look_dir()
      v=approach(v,(look.x*tan.x+look.z*tan.z>=0 and 1 or -1)*MAX_SPEED,ACCEL*dtime)
    elseif ctrl.down then v=approach(v,0,BRAKE*dtime)
    elseif self._cruise then v=approach(v,self._cruise,ACCEL*dtime)
    else v=approach(v,0,FRICTION*dtime) end
    if v<0 then -- going back the way it came
      self._from,b=b,self._from
      self._s,v=len-self._s,-v
    end
    -- Move along, piece to piece; it stops at the end of the line.
    local s=self._s+v*dtime
    for _=1,16 do
      if s<=len then break end
      local nxt=vector.add(self._cell,b)
      local ne=track_ends(nxt)
      if not opens(ne,neg(b)) then s,v=len,0; break end
      self._cell,self._from=nxt,neg(b)
      b=exit_of(ne,self._from)
      s=s-len; len=length(self._from,b)
    end
    s=math.min(s,len)
    self._s,self._v=s,v
    local p
    p,tan=centerline(self._cell,self._from,b,s)
    self._tan=tan
    local off=vector.subtract(p,obj:get_pos())
    if v==0 then
      if vector.length(off)>.01 then obj:set_pos(p) end
      obj:set_velocity(vector.zero())
      return
    end
    -- Velocity along the track keeps the motion smooth between server steps; the
    -- small pull toward the centerline takes up the difference on curves.
    if vector.length(off)>.6 then obj:set_pos(p); off=vector.zero() end
    obj:set_velocity(vector.add(vector.multiply(tan,v),vector.multiply(off,4)))
    obj:set_yaw(C.dir_to_yaw(tan))
  end,
})

C.register_craftitem(CART,{
  description="Train Cart\nRight click a track: put it on\nRight click the cart: ride (W go, S brake, U get off)\n"..
    "Punch: push   Separator: pick it up",
  inventory_image="brickcraft_cart_item.png",stack_max=99,range=7,
  on_place=function(stack,placer,pointed)
    if pointed.type~="node" then return stack end
    local pos=track_ends(pointed.under) and pointed.under or pointed.above
    local name=placer and placer:is_player() and placer:get_player_name() or ""
    if not track_ends(pos) then C.chat_send_player(name,"Put the cart on a track."); return stack end
    for _,o in ipairs(C.get_objects_inside_radius(pos,.6)) do
      local ent=o:get_luaentity()
      if ent and ent.name==CART then C.chat_send_player(name,"There's a cart here already."); return stack end
    end
    C.add_entity(pos,CART)
    stack:take_item(1)
    return stack
  end,
  on_drop=function(stack) return stack end,
})

-- Lays a rectangle of track with corners a and b (b larger in x and z), starting mid-side
-- so the last piece closes it. Returns the cells in laying order.
local function lay_loop(a,b)
  local cells={}
  local function add(x,z) cells[#cells+1]={x=x,y=a.y,z=z} end
  for x=a.x+1,b.x do add(x,a.z) end
  for z=a.z+1,b.z do add(b.x,z) end
  for x=b.x-1,a.x,-1 do add(x,b.z) end
  for z=b.z-1,a.z,-1 do add(a.x,z) end
  for _,pos in ipairs(cells) do lay(pos,{x=1,y=0,z=0}) end
  return cells
end

brickcraft.trains={lay=lay,lay_loop=lay_loop,ends=track_ends,joined=joined,exit_of=exit_of,centerline=centerline}
