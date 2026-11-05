-- Disasters any habitat can have, started with /disaster or the habitat panel.
-- None of them breaks a brick: walls, roofs and raised floors players build are what
-- keeps creatures (and their food) safe.
return function(H)
local C=core
local EDGE=H.EDGE
local function rnd(a,b) return a+math.random()*(b-a) end

------------------------------------------------------------------------------------------
-- Flood: water rises two cells over low ground, then drains. It pours in through any
-- opening, so a sealed bunker stays dry; food left on the ground is spoiled.
------------------------------------------------------------------------------------------
local FLOOD="brickcraft_habitat:flood"
C.register_node(FLOOD,{description="Flood water",drawtype="glasslike",tiles={"brickcraft_habitat_flood.png"},
  use_texture_alpha="blend",paramtype="light",sunlight_propagates=true,walkable=false,pointable=false,
  diggable=false,buildable_to=true,liquid_move_physics=true,move_resistance=2,
  post_effect_color={a=100,r=40,g=100,b=170},groups={not_in_creative_inventory=1},drop=""})
local function region(w,y0,y1) return {x=w.x-EDGE,y=y0,z=w.z-EDGE},{x=w.x+EDGE,y=y1,z=w.z+EDGE} end
-- Fills layer y: from every open-sky air cell (and every air cell over water below) the
-- water spreads sideways through air.
local function fill(w,y)
  local minp,maxp=region(w,y-1,y+20)
  local vm=C.get_voxel_manip()
  local emin,emax=vm:read_from_map(minp,maxp)
  local area=VoxelArea:new({MinEdge=emin,MaxEdge=emax})
  local data=vm:get_data()
  local air,flood=C.get_content_id("air"),C.get_content_id(FLOOD)
  local open={} -- content id -> lets light/sky through (not walkable)
  local function clear(id)
    if open[id]==nil then
      local d=C.registered_nodes[C.get_name_from_content_id(id)]
      open[id]=not (d and d.walkable)
    end
    return open[id]
  end
  local queue,head={},1
  for z=minp.z,maxp.z do for x=minp.x,maxp.x do
    local i=area:index(x,y,z)
    if data[i]==air then
      local seed=data[area:index(x,y-1,z)]==flood
      if not seed then
        seed=true
        for yy=y+1,maxp.y do if not clear(data[area:index(x,yy,z)]) then seed=false; break end end
      end
      if seed then data[i]=flood; queue[#queue+1]=i end
    end
  end end
  local ys=area.ystride
  while head<=#queue do
    local i=queue[head]; head=head+1
    for _,o in ipairs({1,-1,area.zstride,-area.zstride}) do
      local j=i+o
      if data[j]==air then
        local q=area:position(j)
        if math.abs(q.x-w.x)<=EDGE and math.abs(q.z-w.z)<=EDGE then data[j]=flood; queue[#queue+1]=j end
      end
    end
  end
  vm:set_data(data); vm:write_to_map(true)
  -- Food with water over it or beside it is spoiled.
  local lo,hi=region(w,y-1,y)
  for _,q in ipairs(C.find_nodes_in_area(lo,hi,{"group:habitat_food"})) do
    for _,o in ipairs({{0,1,0},{1,0,0},{-1,0,0},{0,0,1},{0,0,-1}}) do
      if C.get_node(vector.offset(q,o[1],o[2],o[3])).name==FLOOD then H.spoil(q); break end
    end
  end
end
local function drain(w,y0,y1)
  local minp,maxp=region(w,y0,y1)
  local vm=C.get_voxel_manip()
  local emin,emax=vm:read_from_map(minp,maxp)
  local area=VoxelArea:new({MinEdge=emin,MaxEdge=emax})
  local data=vm:get_data()
  local air,flood=C.get_content_id("air"),C.get_content_id(FLOOD)
  for i in area:iterp(minp,maxp) do if data[i]==flood then data[i]=air end end
  vm:set_data(data); vm:write_to_map(true)
end
-- Shallow (one cell) most of the time, deep (two) for peak seconds in the middle.
H.register_disaster("flood",{label="Flood",delay=10,duration=44,peak=12,creatures_seek="high",safe_y=2,
  warning="Get the bunnies to high ground or into a sealed bunker, and raise the food up!",
  start=function(ctx) ctx.data.level=0 end,
  step=function(ctx)
    local d=ctx.def.duration
    local mid=d/2
    local half=(ctx.def.peak or 12)/2
    local want=(ctx.t>=mid-half and ctx.t<mid+half) and 2 or ctx.t<d-4 and 1 or 0
    local lv=ctx.data.level
    if want>lv then for y=lv,want-1 do fill(ctx.world,y) end
    elseif want<lv then drain(ctx.world,want,lv) end
    ctx.data.level=want
  end,
  stop=function(ctx) drain(ctx.world,-1,4) end})

------------------------------------------------------------------------------------------
-- Earthquake: the ground shakes and boulders tumble down the hills. Walls stop them.
------------------------------------------------------------------------------------------
local BOULDER="brickcraft_habitat:boulder"
local function hurt_near(p,r,n,how,done)
  for ent in pairs(H.live) do
    local q=ent.object:get_pos()
    if q and not done[ent] and vector.distance(p,vector.offset(q,0,.3,0))<r then done[ent]=true; H.hurt(ent,n,how) end
  end
end
C.register_entity(BOULDER,{
  initial_properties={visual="cube",textures={"brickcraft_habitat_boulder.png","brickcraft_habitat_boulder.png",
    "brickcraft_habitat_boulder.png","brickcraft_habitat_boulder.png","brickcraft_habitat_boulder.png","brickcraft_habitat_boulder.png"},
    visual_size={x=.9,y=.9},physical=true,collide_with_objects=false,pointable=false,static_save=false,
    collisionbox={-.45,-.45,-.45,.45,.45,.45}},
  on_activate=function(self)
    self._t,self._hit,self._still=0,{},0
    self.object:set_acceleration({x=0,y=-2*9.81,z=0})
  end,
  on_step=function(self,dtime)
    self._t=self._t+dtime
    local p=self.object:get_pos()
    local v=self.object:get_velocity()
    if self._dir then self.object:set_velocity({x=self._dir.x,y=v.y,z=self._dir.z}) end
    self.object:set_rotation({x=self._t*4,y=0,z=0})
    hurt_near(p,1,6,"was hit by a tumbling boulder",self._hit)
    self._still=math.abs(v.x)+math.abs(v.z)<.5 and self._still+dtime or 0
    if self._t>10 or self._still>.6 then H.poof(p,"brickcraft_habitat_boulder.png"); self.object:remove() end
  end,
})
H.register_disaster("earthquake",{label="Earthquake",delay=8,duration=16,panic=true,
  warning="Boulders will roll down the hills: walls stop them.",
  start=function(ctx) ctx.data.rock,ctx.data.jolt=0,0 end,
  step=function(ctx,dtime)
    local w=ctx.world
    ctx.data.jolt=ctx.data.jolt-dtime
    if ctx.data.jolt<=0 then
      ctx.data.jolt=.15
      for _,p in ipairs(H.players_in(w)) do p:add_velocity({x=rnd(-1.6,1.6),y=rnd(0,.8),z=rnd(-1.6,1.6)}) end
      for ent in pairs(H.live) do
        if ent.object:get_pos() and math.random()<.2 then ent.object:add_velocity({x=rnd(-1,1),y=0,z=rnd(-1,1)}) end
      end
    end
    ctx.data.rock=ctx.data.rock-dtime
    if ctx.data.rock<=0 then
      ctx.data.rock=rnd(.6,1.2)
      local a=rnd(0,2*math.pi)
      local x,z=math.floor(w.x+math.cos(a)*31+.5),math.floor(w.z+math.sin(a)*31+.5)
      local g=H.ground(x,z,30)
      if g then
        local obj=C.add_entity({x=x,y=g+.6,z=z},BOULDER)
        local ent=obj and obj:get_luaentity()
        if ent then
          -- Toward the middle, give or take, at a run.
          local to={x=w.x+rnd(-14,14)-x,y=0,z=w.z+rnd(-14,14)-z}
          ent._dir=vector.multiply(vector.normalize(to),rnd(4,6))
        end
      end
    end
  end})

------------------------------------------------------------------------------------------
-- Asteroids: burning rocks fall from the sky, mostly near creatures. A roof (or any
-- brick) stops them; the landscape gets craters; food sources they hit are gone.
------------------------------------------------------------------------------------------
local METEOR="brickcraft_habitat:meteor"
local function impact(pos,under)
  C.add_particlespawner({amount=30,time=.2,minpos=vector.offset(pos,-.4,0,-.4),maxpos=vector.offset(pos,.4,.5,.4),
    minvel={x=-4,y=2,z=-4},maxvel={x=4,y=7,z=4},minacc={x=0,y=-15,z=0},maxacc={x=0,y=-15,z=0},
    minexptime=.4,maxexptime=1,minsize=1,maxsize=3,texture="brickcraft_habitat_spark.png",glow=14})
  if under then
    for x=-1,1 do for y=-1,1 do for z=-1,1 do
      local q=vector.offset(under,x,y,z)
      if x*x+y*y+z*z<=2 and q.y>=-1 then
        local name=C.get_node(q).name
        if C.get_item_group(name,"habitat_source")>0 then
          C.remove_node(q)
          local hw=brickcraft.world_at(q)
          H.tell(hw,"An asteroid smashed a "..(C.registered_nodes[name].description:match("^[^\n(]+") or "food source"):gsub("%s+$",""):lower().."!","#ff9a8a")
        elseif name~="air" and H.LANDSCAPE[name] then C.remove_node(q) end
      end
    end end end
  end
  local done={}
  for ent in pairs(H.live) do
    local q=ent.object:get_pos()
    if q and not done[ent] then
      local d=vector.distance(pos,q)
      if d<2.8 and C.line_of_sight(vector.offset(pos,0,.6,0),vector.offset(q,0,.35,0)) then
        done[ent]=true; H.hurt(ent,d<1.3 and 10 or 5,"was hit by an asteroid")
      end
    end
  end
end
C.register_entity(METEOR,{
  initial_properties={visual="cube",textures={"brickcraft_habitat_meteor.png","brickcraft_habitat_meteor.png",
    "brickcraft_habitat_meteor.png","brickcraft_habitat_meteor.png","brickcraft_habitat_meteor.png","brickcraft_habitat_meteor.png"},
    visual_size={x=.7,y=.7},physical=false,pointable=false,static_save=false,glow=14},
  on_activate=function(self) self._last=self.object:get_pos(); self._t=0 end,
  on_step=function(self,dtime)
    local p=self.object:get_pos()
    self._t=self._t+dtime
    self.object:set_rotation({x=self._t*6,y=self._t*4,z=0})
    C.add_particle({pos=p,velocity={x=0,y=1,z=0},expirationtime=.5,size=4,texture="brickcraft_habitat_spark.png",glow=14})
    for hit in C.raycast(self._last,p,false,false) do
      if hit.type=="node" then
        local n=C.get_node(hit.under).name
        local d=C.registered_nodes[n]
        if d and (d.walkable or C.get_item_group(n,"habitat_source")>0) then
          impact(hit.intersection_point or p,hit.under); self.object:remove(); return
        end
      end
    end
    self._last=p
    if p.y<-4 or self._t>8 then self.object:remove() end
  end,
})
H.register_disaster("asteroids",{label="Asteroids",delay=10,duration=24,creatures_seek="shelter",
  warning="Get the bunnies under a roof, and roof over the food!",
  start=function(ctx) ctx.data.next=0 end,
  step=function(ctx,dtime)
    ctx.data.next=ctx.data.next-dtime
    if ctx.data.next>0 then return end
    ctx.data.next=rnd(.35,.7)
    local w=ctx.world
    local target
    -- Most fall near a creature; the rest anywhere.
    if math.random()<.6 then
      local list={}
      for ent in pairs(H.live) do
        local q=ent.object:get_pos()
        if q and brickcraft.world_at(q)==w then list[#list+1]=q end
      end
      if #list>0 then local q=list[math.random(#list)]; target={x=q.x+rnd(-3,3),y=q.y,z=q.z+rnd(-3,3)} end
    end
    target=target or {x=w.x+rnd(-34,34),y=0,z=w.z+rnd(-34,34)}
    local a=rnd(0,2*math.pi)
    local from={x=target.x+math.cos(a)*16,y=target.y+40,z=target.z+math.sin(a)*16}
    local obj=C.add_entity(from,METEOR)
    if obj then obj:set_velocity(vector.multiply(vector.normalize(vector.subtract(target,from)),24)) end
  end})
end
