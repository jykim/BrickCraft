-- Tower Defense (experimental): a world made once, after the Siege Castle. The castle
-- stands in the middle with a gate in its south, east and west walls (a door in each for
-- players), and roads wind to the gates from red portals at the edge of a flat field: one
-- from the south, one from the west, one from the east, and one from the north that forks
-- into the west and east roads (a lever at the fork sends it one way or the other). The
-- Red Army walks the roads in ten waves; whoever gets to a gate costs the castle hearts,
-- and out of hearts it falls. Each player picks a side and can switch any time (/td):
-- Defenders share the gold that knocking out the Red Army brings and spend it on the
--   gold pads beside the roads (arrow, cannon, frost towers and barracks of footmen, each
--   upgraded twice), on the roads (barricades the Red Army has to break, spike traps, tar)
--   and on spells (arrow rain on a road, reinforcements, ice storm, mending the castle).
-- Attackers share a war chest that fills as time goes by and as the castle loses hearts,
--   and spend it on knights of five kinds sent down the road they choose, and on war
--   drums, catapult stones that put a tower out for a while, sappers that clear a road's
--   traps, and a banner that heals the army. The waves come whether anyone attacks or not.
-- The defenders win when the tenth wave is beaten; then, or when the castle falls, a new
-- game starts on a fresh field. Nothing of a game is saved: a restart starts a new one.
return function(api)
local C=core
local now,LOOKS,MOVES=api.now,api.LOOKS,api.MOVES

local R=40 -- the field: ±R round the center, flat (the hills stay beyond)
local CASTLE_HP,GOLD_START,CHEST_START,WAVES=20,120,60,10
local FIRST_BUILD,BUILD,AFTER=40,20,25 -- seconds before the first wave, between waves, after a game
-- Roads: waypoints (x, z from the center) from a portal to a gate.
local ROUTES={
  south={{30,-38},{30,-34},{-28,-34},{-28,-26},{24,-26},{24,-18},{0,-18},{0,-12}},
  west={{-36,36},{-16,36},{-16,28},{-34,28},{-34,20},{-16,20},{-16,12},{-34,12},{-34,0},{-12,0}},
  east={{36,36},{16,36},{16,28},{34,28},{34,20},{16,20},{16,12},{34,12},{34,0},{12,0}},
  north_west={{0,38},{0,16},{-16,16},{-16,12},{-34,12},{-34,0},{-12,0}},
  north_east={{0,38},{0,16},{16,16},{16,12},{34,12},{34,0},{12,0}},
}
local ROADS={"south","west","east","north"} -- what attackers pick from; north takes the lever's way
local ROAD_NAME={south="South",west="West",east="East",north="North"}
local LEVER={x=3,z=19} -- by the fork
local ROAD,PAD,CAMP,ROAD_OF={},{},{},{} -- by "x,z": road cells, pads, portals' red ground, which roads
local function key(x,z) return x..","..z end
for name,route in pairs(ROUTES) do
  local road=name:match("^north") and "north" or name
  local function mark(x,z)
    local k=key(x,z)
    ROAD[k]=true
    ROAD_OF[k]=ROAD_OF[k] or {}
    ROAD_OF[k][name]=true
  end
  -- 3 wide along each stretch, a 3 x 3 square at each waypoint.
  for i=1,#route do
    local a=route[i]
    for o=-1,1 do for o2=-1,1 do mark(a[1]+o,a[2]+o2) end end
    local b=route[i+1]
    if b then
      local dx,dz=b[1]-a[1],b[2]-a[2]
      local n=math.max(math.abs(dx),math.abs(dz))
      for s=0,n do for o=-1,1 do
        mark(a[1]+dx/n*s+(dz~=0 and o or 0),a[2]+dz/n*s+(dx~=0 and o or 0))
      end end
    end
  end
  for dx=-1,1 do for dz=-1,1 do CAMP[key(route[1][1]+dx,route[1][2]+dz)]=road end end
end
-- Gold pads 3 out from a road's middle, every 4 along it, where there's room.
local function room(x,z)
  if math.max(math.abs(x),math.abs(z))<=13 or math.max(math.abs(x),math.abs(z))>R-2 then return false end
  if ROAD[key(x,z)] or (x==LEVER.x and z==LEVER.z) then return false end
  for dx=-1,1 do for dz=-1,1 do
    if ROAD[key(x+dx,z+dz)] and (dx==0 or dz==0) then return false end
    if PAD[key(x+dx,z+dz)] or PAD[key(x+dx*2,z+dz*2)] then return false end
  end end
  return true
end
for _,name in ipairs({"south","west","east","north_west","north_east"}) do
  local route=ROUTES[name]
  for i=1,#route-1 do
    local a,b=route[i],route[i+1]
    local dx,dz=b[1]-a[1],b[2]-a[2]
    local n=math.max(math.abs(dx),math.abs(dz))
    for s=2,n-2,4 do
      for _,side in ipairs({-3,3}) do
        local x,z=a[1]+dx/n*s+(dz~=0 and side or 0),a[2]+dz/n*s+(dx~=0 and side or 0)
        if room(x,z) then PAD[key(x,z)]=true end
      end
    end
  end
end

-- Nodes: the field's own ground, roads and pads (none of it collected or dug), towers,
-- barricades, tar and the fork's lever.
local stone="brickcraft_baseplate.png^[colorize:#a9adb5:210"
local function node(name,desc,tiles,extra)
  local def={description=desc,tiles=tiles,groups={not_in_creative_inventory=1},diggable=false,is_ground_content=false}
  for k,v in pairs(extra or {}) do def[k]=v end
  C.register_node(":brickcraft:"..name,def)
end
node("td_grass","Field",{"brickcraft_grass.png","brickcraft_dirt.png","brickcraft_grass_side.png"})
node("td_road","Road",{"brickcraft_tan.png^[colorize:#7a6040:60"})
node("td_pad","Tower Pad (right click: build)",{"brickcraft_gold.png^[colorize:#fff2a0:40"})
node("td_tar","Tar Pit",{"brickcraft_navy.png^[colorize:#101010:200"})
node("td_tower","Tower",{stone})
node("td_barricade","Barricade",{"brickcraft_trunk.png"})
node("td_barricade_cracked","Splintered Barricade",{"brickcraft_trunk.png^[colorize:#24140a:140"})
local TOWER_TOP={arrow="brickcraft_mint.png",cannon="brickcraft_cannon_metal.png",frost="brickcraft_sky.png^[colorize:#ffffff:90",
  barracks="brickcraft_navy.png"}
for kind,tex in pairs(TOWER_TOP) do node("td_top_"..kind,kind:sub(1,1):upper()..kind:sub(2).." Tower",{tex,stone,tex}) end
for _,s in ipairs({"west","east"}) do
  node("td_lever_"..s,"Fork Lever (sends the north road "..s..")",{"brickcraft_gold.png"},{drawtype="nodebox",paramtype="light",
    sunlight_propagates=true,node_box={type="fixed",fixed={{-.3,-.5,-.3,.3,-.3,.3},s=="west" and {-.45,-.3,-.06,.05,.35,.06} or {-.05,-.3,-.06,.45,.35,.06}}}})
end
local OURS={}
for _,n in ipairs({"td_road","td_pad","td_tar","td_tower","td_barricade","td_barricade_cracked","td_lever_west","td_lever_east",
  "spike_trap","red_camp","castle_wall","castle_wall_cracked","castle_wall_broken","castle_gate","castle_gate_cracked","castle_gate_broken",
  "flag_pole","castle_flag","castle_flag_red"}) do OURS["brickcraft:"..n]=true end
for kind in pairs(TOWER_TOP) do OURS["brickcraft:td_top_"..kind]=true end

-- The castle: the Siege Castle's, with gates in the east and west walls too, and a door 1
-- wide and 2 high in the middle of each gate (the Red Army never gets that far).
local function castle_at(x,y,z)
  local ax,az=math.abs(x),math.abs(z)
  if y<=2 and ((ax==9 or ax==10) and az<=1 or (az==9 or az==10) and ax<=1 and z<0) then
    if (x==0 or z==0) and y<=1 then return nil end
    return "brickcraft:castle_gate"
  end
  return api.castle_cell(x,y,z)
end
-- Lays the field out: the first time everything in it (hills and trees go), after that
-- only its own nodes and air (bricks players put on it stay).
local function lay_out(w,first,fork)
  local vm=C.get_voxel_manip()
  local emin,emax=vm:read_from_map({x=w.x-R,y=-2,z=w.z-R},{x=w.x+R,y=26,z=w.z+R})
  local area=VoxelArea:new({MinEdge=emin,MaxEdge=emax})
  local data=vm:get_data()
  local id=C.get_content_id
  local air,grass,road,pad,camp,plate=id("air"),id("brickcraft:td_grass"),id("brickcraft:td_road"),id("brickcraft:td_pad"),
    id("brickcraft:red_camp"),id("brickcraft:baseplate")
  local ours={}
  for name in pairs(OURS) do ours[id(name)]=true end
  for z=-R,R do for x=-R,R do
    local k=key(x,z)
    local i=area:index(w.x+x,-1,w.z+z)
    if first or ours[data[i]] or data[i]==air then data[i]=CAMP[k] and camp or ROAD[k] and road or PAD[k] and pad or grass end
    if first then data[area:index(w.x+x,-2,w.z+z)]=plate end
    for y=0,26 do
      local j=area:index(w.x+x,y,w.z+z)
      local want=y<=9 and math.max(math.abs(x),math.abs(z))<=11 and castle_at(x,y,z)
      if x==LEVER.x and z==LEVER.z and y==0 then want="brickcraft:td_lever_"..(fork or "west") end
      if want then if first or data[j]==air or ours[data[j]] then data[j]=id(want) end
      elseif first or ours[data[j]] then data[j]=air end
    end
  end end
  vm:set_data(data); vm:write_to_map(false)
  C.fix_light({x=w.x-R,y=-2,z=w.z-R},{x=w.x+R,y=31,z=w.z+R})
end

-- Slowed (k under 1) or hurried (over 1) for secs; the slowest wins while it lasts.
local function chill(e,k,secs)
  local t=now()
  local was=(e._slow or 0)>t and e._slow_k or 1
  e._slow,e._slow_k=math.max(e._slow or 0,t+secs),k>1 and k or math.min(was,k)
end
-- Kinds of Red Army knight: castle hearts a leak costs, a barricade blow, the defenders'
-- gold for a knockout, the attackers' price to send one. Rams don't stop to fight.
local KINDS={
  red={leak=1,bash=1,gold=4,price=10,name="Knight"},
  scout={leak=1,bash=1,gold=3,price=8,name="Scout"},
  shield={leak=2,bash=2,gold=10,price=25,name="Shield Knight"},
  ram={leak=3,bash=6,gold=12,price=30,name="Ram"},
  warlord={leak=5,bash=4,gold=50,price=120,name="Warlord"},
}
LOOKS.ram={tex="brickcraft_person_redknight.png^[colorize:#6a3a18:150",name="Battering Ram",tag="#ff9a76",hp=20,speed=1.6,sight=1,size=1.2,armor=.5}
local KIND_ORDER={"red","scout","shield","ram","warlord"}
-- Towers: seconds between shots and range for levels 1-3; a level costs the tower's price
-- (level 3 one and a half times it); selling gives half of what was spent back.
local TOWERS={
  arrow={name="Arrow Tower",cost=40,about="quick arrows (Shield Knights and Rams take half)",every={1.2,.85,.55},range={10,12,14}},
  cannon={name="Cannon Tower",cost=80,about="cannonballs that burst on a crowd",every={3.2,2.5,1.8},range={12,14,16}},
  frost={name="Frost Tower",cost=60,about="slows everyone near it",every={1.2,1.2,1.2},range={6,7.5,9},slow={.55,.45,.35}},
  barracks={name="Barracks",cost=70,about="footmen who stop the Red Army on the road",every={12,10,8},range={6,6,6},men={2,3,4}},
}
local TOWER_ORDER={"arrow","cannon","frost","barracks"}
local function level_cost(kind,level) return math.floor(TOWERS[kind].cost*(level==3 and 1.5 or 1)) end
local ROADWORK={barricade={name="Barricade",cost=20,about="across the road; the Red Army has to break it",hp=12},
  spikes={name="Spike Trap",cost=25,about="2 hearts off whoever steps on it"},tar={name="Tar Pit",cost=15,about="sticky: slows whoever walks it"}}
-- Spells and attacks: cost, seconds before it can be used again.
local SPELLS={
  rain={name="Arrow Rain",cost=30,every=20,about="arrows on everyone on a road",road=true},
  help={name="Reinforcements",cost=40,every=30,about="3 footmen at a road's gate for 40 s",road=true},
  ice={name="Ice Storm",cost=45,every=30,about="the whole Red Army slowed for 5 s"},
  mend={name="Mend the Castle",cost=50,every=20,about="3 castle hearts back"},
}
local ATTACKS={
  drums={name="War Drums",cost=40,every=25,about="the army runs half as fast again for 10 s"},
  catapult={name="Catapult",cost=50,every=20,about="a stone that puts the biggest tower out for 12 s"},
  sappers={name="Sappers",cost=35,every=20,about="clear a road's spike traps and tar, crack its barricades",road=true},
  banner={name="Healing Banner",cost=30,every=25,about="the whole army back to full hearts"},
}
local SPELL_ORDER,ATTACK_ORDER={"rain","help","ice","mend"},{"drums","catapult","sappers","banner"}

local function td_world() for _,w in ipairs(brickcraft.worlds()) do if w.td then return w end end end
local games={} -- world id -> the game on now
local sides={} -- player name -> "attack" (the default is defending)
local function side(name) return sides[name] or "defend" end
local function here(w)
  local out={}
  for _,p in ipairs(C.get_connected_players()) do if brickcraft.world_at(p:get_pos())==w then out[#out+1]=p end end
  return out
end
local function tell(w,msg,color)
  for _,p in ipairs(here(w)) do C.chat_send_player(p:get_player_name(),C.colorize(color or "#ffd27a",msg)) end
end
local function abs(w,x,z,y) return {x=w.x+x,y=y or 0,z=w.z+z} end
local function rel(w,pos) return math.floor(pos.x-w.x+.5),math.floor(pos.z-w.z+.5) end
local function on_field(g,ent) return ent._td==g.w.id and ent.object:get_pos() end
local function enemies(g)
  local out={}
  for ent in pairs(api.things) do
    if on_field(g,ent) and ent._lane and not ent._down then out[#out+1]=ent end
  end
  return out
end
local function remove_all(w)
  for ent in pairs(api.things) do
    if (ent._td==w.id or ent._archer==w.id) and ent.object:get_pos() then api.things[ent]=nil; ent.object:remove() end
  end
end

-- Map blocks of the field stay active while a game is on, so the Red Army walks (and
-- isn't lost) on roads far from everyone.
local function forceload(g,on)
  local w=g.w
  for x=w.x-R,w.x+R+15,16 do for z=w.z-R,w.z+R+15,16 do for _,y in ipairs({-1,0}) do
    local p={x=math.min(x,w.x+R),y=y,z=math.min(z,w.z+R)}
    if on then C.forceload_block(p,true,-1) else C.forceload_free_block(p,true) end
  end end end
end

-- The castle's guard: 8 archers in the battlements by the gates and facing the fork's road,
-- and 8 cannons (anyone in war fires them; by themselves every 12 s).
local SIDES={south={n={x=0,z=-1},a={x=1,z=0}},east={n={x=1,z=0},a={x=0,z=1}},west={n={x=-1,z=0},a={x=0,z=1}},north={n={x=0,z=1},a={x=1,z=0}}}
local function garrison(w)
  for _,s in pairs(SIDES) do
    for _,t in ipairs({-3,3}) do
      local k=api.spawn_knight({x=w.x+s.n.x*10+s.a.x*t,y=5,z=w.z+s.n.z*10+s.a.z*t},"blue",{yaw=math.atan2(-s.n.x,s.n.z)})
      if k then k._archer=w.id; api.dress(k) end
    end
  end
end
local function cannons(w)
  for ent in pairs(api.things) do if ent._castle==w.id and ent.object:get_pos() then return end end
  for _,s in pairs(SIDES) do for _,t in ipairs({-5,5}) do
    local obj=C.add_entity({x=w.x+s.n.x*10+s.a.x*t,y=4.5,z=w.z+s.n.z*10+s.a.z*t},"brickcraft:cannon")
    if obj then obj:set_yaw(math.atan2(-s.n.x,s.n.z)); obj:get_luaentity()._castle=w.id end
  end end
end

local new_game
local function over(g,msg)
  g.phase,g.next="over",now()+AFTER
  for _,e in ipairs(enemies(g)) do api.poof(e.object:get_pos()); api.things[e]=nil; e.object:remove() end
  tell(g.w,msg.." A new game starts in "..AFTER.." seconds.","#ff9a76")
end

-- A knight of the Red Army on its road: it walks from waypoint to waypoint (its own small
-- offset from the middle), fights whoever stands in its way, breaks barricades ahead, and
-- at the last one (a gate) it's in: the castle loses hearts.
local function leak(g,self)
  local k=KINDS[self._kind]
  g.hp=math.max(0,g.hp-k.leak)
  g.chest=g.chest+5*k.leak
  api.poof(self.object:get_pos()); api.things[self]=nil; self.object:remove()
  tell(g.w,("A %s got in at the %s gate! Castle %d/%d hearts."):format(LOOKS[self._kind].name,ROAD_NAME[self._road] or "",g.hp,CASTLE_HP),"#ff7a6a")
  if g.hp<=0 and g.phase~="over" then over(g,"The castle has fallen: the attackers win!") end
end
local function batter(g,self,c,p)
  api.face(self.object,vector.subtract(c,p))
  self._still=true
  local t=now()
  if (self._swung or 0)+MOVES.knight.cool>t then return end
  self._swung=t
  local k=key(rel(g.w,c))
  local b=g.bars[k]
  if not b then b={hp=ROADWORK.barricade.hp}; g.bars[k]=b end
  b.hp=b.hp-KINDS[self._kind].bash
  if b.hp<=0 then
    g.bars[k]=nil
    for y=0,1 do C.remove_node({x=c.x,y=y,z=c.z}) end
    api.poof(c)
  elseif b.hp<=ROADWORK.barricade.hp/2 then
    for y=0,1 do C.swap_node({x=c.x,y=y,z=c.z},{name="brickcraft:td_barricade_cracked"}) end
  end
end
local function lane_step(self,p)
  local g=games[self._td]
  if not g or g.phase=="over" then return false end
  local route=self._lane
  local b=route[self._wp]
  local a=route[self._wp-1]
  -- Past this waypoint (along the stretch it's on): on to the next.
  local sx,sz=b.x-a.x,b.z-a.z
  local len=math.max(math.sqrt(sx*sx+sz*sz),.01)
  if ((p.x-b.x)*sx+(p.z-b.z)*sz)/len>-.35 then
    if self._wp==#route then leak(g,self); return true end
    self._wp=self._wp+1
    a,b=b,route[self._wp]
  end
  if self._kind~="ram" then
    local foe=api.find_foe(self,p,1.6)
    if foe then api.swing(self,foe,p); return true end
  end
  local d=vector.normalize({x=b.x-p.x,y=0,z=b.z-p.z})
  local c={x=math.floor(p.x+d.x*.9+.5),y=0,z=math.floor(p.z+d.z*.9+.5)}
  local name=C.get_node(c).name
  if name=="brickcraft:td_barricade" or name=="brickcraft:td_barricade_cracked" then batter(g,self,c,p); return true end
  api.walk(self,{x=b.x,y=p.y,z=b.z},false,true)
  return true
end

-- The north road goes the way the lever points.
local function fork_route(g) return "north_"..g.fork end
local function spawn_enemy(g,road,kind)
  local w=g.w
  local name=road=="north" and fork_route(g) or road
  local route=ROUTES[name]
  local o={x=(math.random()-.5)*1.4,z=(math.random()-.5)*1.4}
  local pts={}
  for i,q in ipairs(route) do pts[i]={x=w.x+q[1]+o.x,y=0,z=w.z+q[2]+o.z} end
  local d={x=route[2][1]-route[1][1],z=route[2][2]-route[1][2]}
  local ent=api.spawn_knight({x=pts[1].x,y=0,z=pts[1].z},"red",{yaw=math.atan2(-d.x,d.z)})
  if not ent then return end
  ent._kind,ent._hp=kind,nil
  api.dress(ent)
  -- A little tougher each wave.
  ent._max=math.floor(LOOKS[kind].hp*(1+.08*math.max(0,g.wave-1))+.5)
  ent._hp=ent._max
  api.knight_tag(ent)
  ent._td,ent._lane,ent._wp,ent._road=w.id,pts,2,road
  ent._on_down=function(self,attacker)
    local gg=games[w.id]
    if not gg then return end
    gg.gold=gg.gold+KINDS[kind].gold
    if kind=="warlord" then tell(w,"The Red Warlord is down! +"..KINDS[kind].gold.." gold.") end
  end
  return ent
end

-- Waves: the south road at first; the west joins from wave 3, the east from 5, the north
-- from 7. Scouts from wave 2, Shield Knights from 4, Rams from 6; a Warlord on wave 5
-- (south) and on wave 10 (south and north).
local function wave_plan(n)
  local roads={"south"}
  if n>=3 then roads[#roads+1]="west" end
  if n>=5 then roads[#roads+1]="east" end
  if n>=7 then roads[#roads+1]="north" end
  local q={}
  for r,road in ipairs(roads) do
    local at=now()+1+r*.5
    for i=1,2+n do
      local kind=(n>=6 and i%5==0) and "ram" or (n>=4 and i%4==0) and "shield" or (n>=2 and i%3==0) and "scout" or "red"
      q[#q+1]={at=at,road=road,kind=kind}
      at=at+(kind=="scout" and 1 or 1.8)
    end
    if (n==5 and road=="south") or (n==10 and (road=="south" or road=="north")) then q[#q+1]={at=at+2,road=road,kind="warlord"} end
  end
  table.sort(q,function(a,b) return a.at>b.at end) -- the next one last
  return q
end
local function start_wave(g)
  g.wave=g.wave+1
  for _,q in ipairs(wave_plan(g.wave)) do g.queue[#g.queue+1]=q end -- (after knights the attackers sent)
  table.sort(g.queue,function(a,b) return a.at>b.at end)
  g.phase="wave"
  tell(g.w,("Wave %d of %d is coming%s!"):format(g.wave,WAVES,g.wave==5 and ", with a Red Warlord" or g.wave==10 and ", the last, with two Warlords" or ""),"#ff9a76")
  for _,road in ipairs({"south","west","east","north"}) do
    local first=ROUTES[road=="north" and "north_west" or road][1]
    if g.wave>=({south=1,west=3,east=5,north=7})[road] then
      local c=abs(g.w,first[1],first[2])
      C.add_particlespawner({amount=50,time=1.5,minpos=vector.offset(c,-2,0,-2),maxpos=vector.offset(c,2,1,2),
        minvel={x=-.3,y=1,z=-.3},maxvel={x=.3,y=2.5,z=.3},minexptime=1,maxexptime=2,minsize=6,maxsize=12,
        texture="brickcraft_smoke.png^[colorize:#d03020:160"})
    end
  end
end

-- Towers on the pads. A tower is a column of stone as high as its level with its kind's
-- top on it.
local function tower_cells(w,t)
  local out={}
  for y=0,3 do out[#out+1]={pos=abs(w,t.x,t.z,y),name=y<t.level and "brickcraft:td_tower" or y==t.level and "brickcraft:td_top_"..t.kind or "air"} end
  return out
end
local function put_tower(w,t) for _,c in ipairs(tower_cells(w,t)) do C.set_node(c.pos,{name=c.name}) end end
local function nearest_road(x,z)
  local best,bd
  for dx=-4,4 do for dz=-4,4 do
    if ROAD[key(x+dx,z+dz)] and (not bd or dx*dx+dz*dz<bd) then best,bd={x=x+dx,z=z+dz},dx*dx+dz*dz end
  end end
  return best
end
local function spend(g,amount,name)
  if g.gold<amount then C.chat_send_player(name,("Not enough gold: that's %d, you have %d."):format(amount,g.gold)); return false end
  g.gold=g.gold-amount
  return true
end
local function build_tower(g,k,kind,name)
  local x,z=k:match("^(-?%d+),(-?%d+)$")
  x,z=tonumber(x),tonumber(z)
  if not PAD[k] or g.towers[k] or not TOWERS[kind] then return false end
  for _,o in ipairs(C.get_objects_inside_radius(abs(g.w,x,z,.5),1)) do
    if o:is_player() then C.chat_send_player(name,"Step off the pad first."); return false end
  end
  if not spend(g,TOWERS[kind].cost,name) then return false end
  local t={x=x,z=z,kind=kind,level=1,spent=TOWERS[kind].cost,t=0,men={},rally=kind=="barracks" and nearest_road(x,z) or nil}
  g.towers[k]=t
  put_tower(g.w,t)
  api.poof(abs(g.w,x,z,1))
  return true
end
local function upgrade(g,k,name)
  local t=g.towers[k]
  if not t or t.level>=3 then return false end
  local cost=level_cost(t.kind,t.level+1)
  if not spend(g,cost,name) then return false end
  t.level,t.spent=t.level+1,t.spent+cost
  put_tower(g.w,t)
  api.poof(abs(g.w,t.x,t.z,t.level))
  return true
end
local function sell(g,k)
  local t=g.towers[k]
  if not t then return false end
  g.gold=g.gold+math.floor(t.spent/2)
  for _,m in ipairs(t.men) do if m.object:get_pos() then api.things[m]=nil; m.object:remove() end end
  g.towers[k]=nil
  t.level=-1
  put_tower(g.w,t)
  return true
end
-- Road work: a barricade across the road where it's clicked (the road's whole width),
-- spike traps and tar in the road's floor.
local function across(x,z)
  local out={}
  local function road(a,b) return ROAD[key(a,b)] end
  -- The road runs the way it reaches 2 further on.
  local along_x=road(x-2,z) or road(x+2,z)
  local along_z=road(x,z-2) or road(x,z+2)
  local dx,dz=0,0
  if along_x and not along_z then dz=1 elseif along_z and not along_x then dx=1 else dx=1 end
  for s=-2,2 do if road(x+dx*s,z+dz*s) then out[#out+1]={x=x+dx*s,z=z+dz*s} end end
  return out
end
local function road_work(g,k,what,name)
  local w=g.w
  local x,z=k:match("^(-?%d+),(-?%d+)$")
  x,z=tonumber(x),tonumber(z)
  if not ROAD[k] or CAMP[k] or math.max(math.abs(x),math.abs(z))<=12 or not ROADWORK[what] then return false end
  if what=="barricade" then
    local cells={}
    for _,c in ipairs(across(x,z)) do
      if C.get_node(abs(w,c.x,c.z)).name=="air" then cells[#cells+1]=c end
    end
    if #cells==0 then return false end
    if not spend(g,ROADWORK.barricade.cost,name) then return false end
    for _,c in ipairs(cells) do
      for y=0,1 do C.set_node(abs(w,c.x,c.z,y),{name="brickcraft:td_barricade"}) end
      g.bars[key(c.x,c.z)]={hp=ROADWORK.barricade.hp}
    end
    return true
  end
  if C.get_node(abs(w,x,z,-1)).name~="brickcraft:td_road" then return false end
  if not spend(g,ROADWORK[what].cost,name) then return false end
  C.set_node(abs(w,x,z,-1),{name=what=="tar" and "brickcraft:td_tar" or "brickcraft:spike_trap"})
  return true
end
local function clear_work(g,k)
  local w=g.w
  local x,z=k:match("^(-?%d+),(-?%d+)$")
  x,z=tonumber(x),tonumber(z)
  if g.bars[k] then
    g.bars[k]=nil
    for y=0,1 do C.remove_node(abs(w,x,z,y)) end
    g.gold=g.gold+5
    return true
  end
  local floor=C.get_node(abs(w,x,z,-1)).name
  if floor=="brickcraft:spike_trap" or floor=="brickcraft:td_tar" then
    C.set_node(abs(w,x,z,-1),{name="brickcraft:td_road"}); g.gold=g.gold+5; return true
  end
  return false
end
local function repair(g,k,name)
  local b=g.bars[k]
  if not b or b.hp>=ROADWORK.barricade.hp or not spend(g,8,name) then return false end
  b.hp=ROADWORK.barricade.hp
  local x,z=k:match("^(-?%d+),(-?%d+)$")
  for y=0,1 do C.swap_node(abs(g.w,tonumber(x),tonumber(z),y),{name="brickcraft:td_barricade"}) end
  return true
end
local function flip_lever(g)
  g.fork=g.fork=="west" and "east" or "west"
  C.set_node(abs(g.w,LEVER.x,LEVER.z),{name="brickcraft:td_lever_"..g.fork})
  tell(g.w,"The fork's lever now sends the north road "..g.fork..".")
end

-- Spells (defenders') and attacks (attackers'), each with its own wait.
local function ready(g,id,every,name)
  local left=(g.cool[id] or 0)-now()
  if left>0 then C.chat_send_player(name,("Not ready yet: %d s."):format(math.ceil(left))); return false end
  g.cool[id]=now()+every
  return true
end
local function footmen(g,at,n,expire,tower)
  local out={}
  for i=1,n do
    local a=i*2*math.pi/n
    local ent=api.spawn_knight({x=at.x+math.cos(a)*.8,y=0,z=at.z+math.sin(a)*.8},"blue",{})
    if ent then
      ent._kind,ent._hp="footman",nil; api.dress(ent)
      ent._td,ent._expire,ent._tower=g.w.id,expire,tower
      out[#out+1]=ent
    end
  end
  return out
end
local function cast(g,id,name,road)
  local sp=SPELLS[id]
  local w=g.w
  if sp.road and not ROAD_NAME[road or ""] then return false end
  if g.gold<sp.cost then C.chat_send_player(name,("Not enough gold: that's %d, you have %d."):format(sp.cost,g.gold)); return false end
  if not ready(g,id,sp.every,name) then return false end
  g.gold=g.gold-sp.cost
  local who=api.label(C.get_player_by_name(name))
  if id=="rain" then
    local n=0
    for _,e in ipairs(enemies(g)) do
      if e._road==road and n<14 then
        n=n+1
        local p=e.object:get_pos()
        for j=0,1 do api.loose({x=p.x+(math.random()-.5)*.4,y=p.y+10+j*2,z=p.z+(math.random()-.5)*.4},{x=0,y=-1,z=0},nil,nil,"blue") end
      end
    end
    tell(w,who.." called an Arrow Rain on the "..ROAD_NAME[road].." road!")
  elseif id=="help" then
    local route=ROUTES[road=="north" and fork_route(g) or road]
    local q=route[#route-1]
    footmen(g,abs(w,q[1],q[2]),3,now()+40)
    tell(w,who.." sent 3 footmen to the "..ROAD_NAME[road].." road!")
  elseif id=="ice" then
    for _,e in ipairs(enemies(g)) do
      chill(e,.4,5)
      local p=e.object:get_pos()
      C.add_particlespawner({amount=6,time=.3,minpos=vector.offset(p,-.4,1,-.4),maxpos=vector.offset(p,.4,2,.4),
        minvel={x=0,y=-1,z=0},maxvel={x=0,y=-.5,z=0},minexptime=1,maxexptime=1.5,minsize=2,maxsize=3,texture="brickcraft_cream.png"})
    end
    tell(w,who.." called an Ice Storm: the Red Army is slowed!")
  elseif id=="mend" then
    g.hp=math.min(CASTLE_HP,g.hp+3)
    tell(w,who.." mended the castle: "..g.hp.."/"..CASTLE_HP.." hearts.")
  end
  return true
end
local function attack(g,id,name,road)
  local at=ATTACKS[id]
  local w=g.w
  if at.road and not ROAD_NAME[road or ""] then return false end
  if g.chest<at.cost then C.chat_send_player(name,("Not enough in the war chest: that's %d, it has %d."):format(at.cost,g.chest)); return false end
  if not ready(g,id,at.every,name) then return false end
  g.chest=g.chest-at.cost
  local who=api.label(C.get_player_by_name(name))
  if id=="drums" then
    for _,e in ipairs(enemies(g)) do e._slow,e._slow_k=now()+10,1.5 end -- (frost after it slows them again)
    tell(w,who.." beats the War Drums: the Red Army runs!","#ff7a6a")
  elseif id=="catapult" then
    local best
    for _,t in pairs(g.towers) do if not best or t.spent>best.spent then best=t end end
    if not best then g.chest=g.chest+at.cost; g.cool[id]=0; C.chat_send_player(name,"No tower to throw a stone at."); return false end
    best.stun=now()+12
    local top=abs(w,best.x,best.z,best.level)
    api.lob_at(abs(w,best.x>0 and R-2 or -R+2,best.z,3),top,nil,"red",22)
    C.add_particlespawner({amount=40,time=12,minpos=vector.offset(top,-.4,.4,-.4),maxpos=vector.offset(top,.4,.8,.4),
      minvel={x=-.2,y=.6,z=-.2},maxvel={x=.2,y=1.2,z=.2},minexptime=1,maxexptime=2,minsize=4,maxsize=7,texture="brickcraft_smoke.png"})
    tell(w,who.."'s catapult hit the "..TOWERS[best.kind].name.."! It's out for 12 s.","#ff7a6a")
  elseif id=="sappers" then
    for k,roads in pairs(ROAD_OF) do
      local mine=road=="north" and (roads.north_west or roads.north_east) or roads[road]
      if mine then
        local x,z=k:match("^(-?%d+),(-?%d+)$")
        local p=abs(w,tonumber(x),tonumber(z),-1)
        local floor=C.get_node(p).name
        if floor=="brickcraft:spike_trap" or floor=="brickcraft:td_tar" then C.set_node(p,{name="brickcraft:td_road"}) end
        local b=g.bars[k]
        if b then
          b.hp=math.min(b.hp,ROADWORK.barricade.hp/2)
          for y=0,1 do C.swap_node({x=p.x,y=y,z=p.z},{name="brickcraft:td_barricade_cracked"}) end
        end
      end
    end
    tell(w,who.."'s sappers cleared the "..ROAD_NAME[road].." road's traps!","#ff7a6a")
  elseif id=="banner" then
    for _,e in ipairs(enemies(g)) do e._hp=e._max; api.knight_tag(e) end
    tell(w,who.." raised the Healing Banner!","#ff7a6a")
  end
  return true
end
-- Attackers send knights down a road (a few apart), from the first wave until the last.
local function send(g,kind,road,name)
  if not KINDS[kind] or not ROAD_NAME[road or ""] then return false end
  if g.wave<1 or g.wave>=WAVES and #g.queue==0 then C.chat_send_player(name,"Knights can be sent once the first wave comes, until the last."); return false end
  local price=KINDS[kind].price
  if g.chest<price then C.chat_send_player(name,("Not enough in the war chest: that's %d, it has %d."):format(price,g.chest)); return false end
  g.chest=g.chest-price
  local at=math.max(now(),(g.sent[road] or 0)+.8)
  g.sent[road]=at
  table.insert(g.queue,{at=at,road=road,kind=kind,by=name})
  table.sort(g.queue,function(a,b) return a.at>b.at end)
  return true
end

-- Menus. Right click a pad, a tower or the road (defenders), or type /td (anyone: spells or
-- attacks, and switching sides).
local ctx={} -- player name -> {k=the cell, what}
local function header(g,name)
  local s=side(name)
  return ("formspec_version[6]size[10.5,%%s]bgcolor[#142936;true]label[.5,.55;%s]label[.5,1;Wave %d/%d   Castle %d/%d hearts   %s]"):format(
    s=="attack" and "ATTACKER (Red Army)" or "DEFENDER (castle)",g.wave,WAVES,g.hp,CASTLE_HP,
    s=="attack" and "War chest: "..g.chest or "Gold: "..g.gold)
end
local function road_list(road) return "dropdown[6.6,1.45;3.4,.7;road;South,West,East,North;"..(({south=1,west=2,east=3,north=4})[road or "south"]).."]" end
local function panel(g,name)
  local s=side(name)
  local rows={}
  local y=2.3
  if s=="attack" then
    rows[#rows+1]="label[.5,1.8;Send down the road:]"..road_list(ctx[name] and ctx[name].road)
    for i,kind in ipairs(KIND_ORDER) do
      rows[#rows+1]=("button[%.1f,%.1f;1.9,.8;send_%s;%s %d]"):format(.5+(i-1)*1.95,y,kind,KINDS[kind].name,KINDS[kind].price)
    end
    y=y+1.1
    for _,id in ipairs(ATTACK_ORDER) do
      local a=ATTACKS[id]
      rows[#rows+1]=("button[.5,%.1f;4.4,.8;atk_%s;%s  %d]label[5.1,%.1f;%s]"):format(y,id,a.name,a.cost,y+.4,C.formspec_escape(a.about))
      y=y+.95
    end
  else
    rows[#rows+1]="label[.5,1.8;Spells (some on a road):]"..road_list(ctx[name] and ctx[name].road)
    for _,id in ipairs(SPELL_ORDER) do
      local sp=SPELLS[id]
      rows[#rows+1]=("button[.5,%.1f;4.4,.8;spell_%s;%s  %d]label[5.1,%.1f;%s]"):format(y,id,sp.name,sp.cost,y+.4,C.formspec_escape(sp.about))
      y=y+.95
    end
    if g.phase=="build" then
      rows[#rows+1]=("button_exit[.5,%.1f;9.5,.8;next;Call the next wave now (+%d gold)]"):format(y,math.max(0,math.ceil(g.next-now())))
      y=y+.95
    end
    rows[#rows+1]=("label[.5,%.1f;%s]"):format(y+.3,C.formspec_escape("Right click a gold pad to build a tower, a tower to upgrade it, the road for barricades and traps,\nthe lever at the north fork to send the north road west or east."))
    y=y+1
  end
  rows[#rows+1]=("button_exit[.5,%.1f;4.6,.8;switch;Switch to %s]button_exit[5.4,%.1f;4.6,.8;close;Close]"):format(y+.3,s=="attack" and "defending" or "attacking",y+.3)
  return header(g,name):format(y+1.4)..table.concat(rows)
end
local function cell_menu(g,name,k)
  local rows={}
  local y=1.7
  local t=g.towers[k]
  local title
  if t then
    local spec=TOWERS[t.kind]
    title=("%s, level %d%s"):format(spec.name,t.level,t.stun and t.stun>now() and " (out: catapult)" or "")
    rows[#rows+1]=("label[.5,%.1f;%s. Range %d, every %.1f s%s]"):format(y,C.formspec_escape(spec.about),spec.range[t.level],spec.every[t.level],
      spec.men and ", "..spec.men[t.level].." footmen" or "")
    y=y+.6
    if t.level<3 then rows[#rows+1]=("button_exit[.5,%.1f;9.5,.8;upgrade;Upgrade to level %d  (%d gold)]"):format(y,t.level+1,level_cost(t.kind,t.level+1)); y=y+.95 end
    rows[#rows+1]=("button_exit[.5,%.1f;9.5,.8;sell;Sell  (+%d gold)]"):format(y,math.floor(t.spent/2)); y=y+.95
  elseif PAD[k] then
    title="Build a tower here"
    for _,kind in ipairs(TOWER_ORDER) do
      local spec=TOWERS[kind]
      rows[#rows+1]=("button_exit[.5,%.1f;4.4,.8;tower_%s;%s  %d]label[5.1,%.1f;%s]"):format(y,kind,spec.name,spec.cost,y+.4,C.formspec_escape(spec.about))
      y=y+.95
    end
  elseif g.bars[k] then
    local b=g.bars[k]
    title=("Barricade %d/%d"):format(b.hp,ROADWORK.barricade.hp)
    if b.hp<ROADWORK.barricade.hp then rows[#rows+1]=("button_exit[.5,%.1f;9.5,.8;repair;Repair  (8 gold)]"):format(y); y=y+.95 end
    rows[#rows+1]=("button_exit[.5,%.1f;9.5,.8;clear;Take it away  (+5 gold)]"):format(y); y=y+.95
  else
    local x,z=k:match("^(-?%d+),(-?%d+)$")
    local floor=C.get_node(abs(g.w,tonumber(x),tonumber(z),-1)).name
    if floor~="brickcraft:td_road" then
      title=floor=="brickcraft:td_tar" and "Tar Pit" or "Spike Trap"
      rows[#rows+1]=("button_exit[.5,%.1f;9.5,.8;clear;Take it away  (+5 gold)]"):format(y); y=y+.95
    else
      title="The road"
      for _,what in ipairs({"barricade","spikes","tar"}) do
        local r=ROADWORK[what]
        rows[#rows+1]=("button_exit[.5,%.1f;4.4,.8;work_%s;%s  %d]label[5.1,%.1f;%s]"):format(y,what,r.name,r.cost,y+.4,C.formspec_escape(r.about))
        y=y+.95
      end
    end
  end
  rows[#rows+1]=("button_exit[.5,%.1f;4.6,.8;panel;Spells, switch side]button_exit[5.4,%.1f;4.6,.8;close;Close]"):format(y+.2,y+.2)
  return header(g,name):format(y+1.3)..("label[.5,1.4;%s]"):format(C.formspec_escape(title))..table.concat(rows)
end
local function show(name,form) C.show_formspec(name,"brickcraft:td",form) end
local function open_panel(name)
  local w=td_world()
  local g=w and games[w.id]
  if not g then return false end
  ctx[name]={what="panel",road=ctx[name] and ctx[name].road}
  show(name,panel(g,name))
  return true
end
-- A right click on the field: true when it opened a menu (or flipped the lever).
local function menu(player,pos)
  local w=td_world()
  if not w or brickcraft.world_at(pos)~=w then return false end
  local g=games[w.id]
  local name=player:get_player_name()
  local n=C.get_node(pos).name
  if not g or not OURS[n] or n:find("^brickcraft:castle") or n:find("flag") then return false end
  if side(name)=="attack" then return open_panel(name) end
  if n:find("^brickcraft:td_lever") then flip_lever(g); return true end
  local x,z=rel(w,pos)
  local k=key(x,z)
  if not PAD[k] and not ROAD[k] then return false end
  if ROAD[k] and CAMP[k] then return false end
  ctx[name]={what="cell",k=k,road=ctx[name] and ctx[name].road}
  show(name,cell_menu(g,name,k))
  return true
end
C.register_on_player_receive_fields(function(player,formname,fields)
  if formname~="brickcraft:td" then return end
  local name=player:get_player_name()
  local w=td_world()
  local g=w and games[w.id]
  local c=ctx[name]
  if not g or not c then return true end
  if not brickcraft.permissions.check(player,{x=w.x,y=0,z=w.z}) then return true end
  local road=fields.road and fields.road:lower()
  if ROAD_NAME[road or ""] then c.road=road end
  road=c.road or "south"
  if fields.switch then
    sides[name]=side(name)=="attack" and "defend" or "attack"
    tell(w,api.label(player).." is "..(sides[name]=="attack" and "attacking with the Red Army" or "defending the castle").." now.",
      sides[name]=="attack" and "#ff7a6a" or "#8fd0ff")
    return true
  end
  if fields.panel then return open_panel(name) end
  if fields.next and g.phase=="build" then
    g.gold=g.gold+math.max(0,math.ceil(g.next-now())); g.next=now()
    return true
  end
  local again=false
  for f in pairs(fields) do
    local kind=f:match("^tower_(%a+)$")
    if kind then build_tower(g,c.k,kind,name) end
    local what=f:match("^work_(%a+)$")
    if what then road_work(g,c.k,what,name) end
    if f=="upgrade" then upgrade(g,c.k,name) end
    if f=="sell" then sell(g,c.k) end
    if f=="clear" then clear_work(g,c.k) end
    if f=="repair" then repair(g,c.k,name) end
    local sp=f:match("^spell_(%a+)$")
    if sp and SPELLS[sp] and side(name)=="defend" then cast(g,sp,name,road); again=true end
    local at=f:match("^atk_(%a+)$")
    if at and ATTACKS[at] and side(name)=="attack" then attack(g,at,name,road); again=true end
    local sk=f:match("^send_(%a+)$")
    if sk and side(name)=="attack" then send(g,sk,road,name); again=true end
  end
  if again and not fields.quit then show(name,panel(g,name)) end
  return true
end)
-- Every right click on the field reaches the menu, whatever is in hand (bricks and war
-- tools place or fire through on_place, which never asks the node).
local function on_field_click(pos,_,clicker) if clicker and clicker:is_player() then menu(clicker,pos) end end
for n in pairs(OURS) do
  if n:find("^brickcraft:td_") then C.override_item(n,{on_rightclick=on_field_click}) end
end
C.register_on_mods_loaded(function()
  for iname,def in pairs(C.registered_items) do
    local place=def.on_place
    if iname~="" and place then
      C.override_item(iname,{on_place=function(stack,placer,pt)
        if pt and pt.type=="node" and placer and placer:is_player() and menu(placer,pt.under) then return stack end
        return place(stack,placer,pt)
      end})
    end
  end
end)

-- Each player's line at the top of the screen while they're here.
local huds={} -- player name -> hud id
local function hud_text(g,name)
  local s=side(name)
  local enemy=#enemies(g)
  local when=g.phase=="build" and ("Wave %d in %d s"):format(g.wave+1,math.max(0,math.ceil(g.next-now())))
    or g.phase=="over" and ("New game in %d s"):format(math.max(0,math.ceil(g.next-now())))
    or ("%d of the Red Army on the roads"):format(enemy+#g.queue)
  return ("%s   Wave %d/%d   Castle %d/%d hearts   %s   %s   /td: %s"):format(
    s=="attack" and "ATTACKING" or "DEFENDING",g.wave,WAVES,g.hp,CASTLE_HP,
    s=="attack" and "War chest "..g.chest or "Gold "..g.gold,when,
    s=="attack" and "send knights, attacks, switch side" or "spells, switch side (right click pads and roads to build)")
end
local function hud(player,g)
  local name=player:get_player_name()
  if not g then
    if huds[name] then player:hud_remove(huds[name]); huds[name]=nil end
    return
  end
  local text=hud_text(g,name)
  local color=side(name)=="attack" and 0xff7a6a or 0xffd27a
  if huds[name] then player:hud_change(huds[name],"text",text); player:hud_change(huds[name],"number",color); return end
  huds[name]=player:hud_add({type="text",position={x=.5,y=0},offset={x=0,y=28},text=text,number=color,alignment={x=0,y=0},scale={x=100,y=20}})
end
C.register_on_leaveplayer(function(player) huds[player:get_player_name()]=nil end)

new_game=function(w)
  local old=games[w.id]
  if old then forceload(old,false) end
  remove_all(w)
  lay_out(w,false,"west")
  local g={w=w,wave=0,hp=CASTLE_HP,gold=GOLD_START,chest=CHEST_START,phase="build",next=now()+FIRST_BUILD,queue={},
    towers={},bars={},cool={},sent={},fork="west",income=now()}
  games[w.id]=g
  forceload(g,true)
  garrison(w)
  tell(w,("Tower Defense: a new game! The first wave comes in %d s. Defenders: right click the gold pads to build towers. "..
    "Anyone: /td to switch to attacking (or back)."):format(FIRST_BUILD))
  return g
end
local function end_game(w)
  local g=games[w.id]
  if not g then return end
  forceload(g,false)
  remove_all(w)
  games[w.id]=nil
end

-- The game's turn, 4 times a second: towers fire, waves come, footmen are called up.
local function towers_turn(g,foes)
  local w=g.w
  local t0=now()
  for k,t in pairs(g.towers) do
    local spec=TOWERS[t.kind]
    local L=t.level
    if (t.stun or 0)<t0 and t.t+spec.every[L]<=t0 then
      local base=abs(w,t.x,t.z)
      local top=abs(w,t.x,t.z,L+.9)
      if t.kind=="barracks" then
        t.t=t0
        for i=#t.men,1,-1 do if not t.men[i].object:get_pos() then table.remove(t.men,i) end end
        if #t.men<spec.men[L] and t.rally then
          for _,m in ipairs(footmen(g,abs(w,t.rally.x,t.rally.z),1,nil,k)) do t.men[#t.men+1]=m end
        end
      elseif t.kind=="frost" then
        local any=false
        for _,e in ipairs(foes) do
          if vector.distance(base,e.object:get_pos())<=spec.range[L] then
            any=true
            chill(e,spec.slow[L],2)
          end
        end
        if any then
          t.t=t0
          C.add_particlespawner({amount=30,time=.8,minpos=vector.offset(base,-spec.range[L],.2,-spec.range[L]),
            maxpos=vector.offset(base,spec.range[L],1.5,spec.range[L]),minvel={x=-.2,y=-.4,z=-.2},maxvel={x=.2,y=.1,z=.2},
            minexptime=.6,maxexptime=1.2,minsize=1.5,maxsize=3,texture="brickcraft_cream.png"})
        end
      else
        -- The one furthest along its road within range.
        local best,bp
        for _,e in ipairs(foes) do
          local p=e.object:get_pos()
          if vector.distance(base,p)<=spec.range[L] then
            local wp=e._lane[e._wp]
            local progress=e._wp*1000-vector.distance(p,wp)
            if not bp or progress>bp then best,bp=e,progress end
          end
        end
        if best then
          t.t=t0
          local p=best.object:get_pos()
          local v=best.object:get_velocity()
          if t.kind=="arrow" then
            local q=vector.offset(p,0,.9,0)
            local fly=vector.distance(top,q)/api.arrow_speed
            q=vector.add(q,{x=v.x*fly,y=0,z=v.z*fly})
            local dir=vector.normalize(vector.subtract(vector.offset(q,0,api.arrow_gravity*fly*fly/2,0),top))
            api.loose(vector.add(top,vector.multiply(dir,.6)),dir,nil,nil,"blue")
          else
            local fly=vector.distance(top,p)/15*1.2
            api.lob_at(top,{x=p.x+v.x*fly,y=p.y+.4,z=p.z+v.z*fly},nil,"blue",15)
          end
        end
      end
    end
  end
end
local timer,welcomed=0,{}
C.register_globalstep(function(dt)
  timer=timer+dt
  if timer<.25 then return end
  local step=timer
  timer=0
  local w=td_world()
  if not w or not w.td_built then return end
  local g=games[w.id]
  local people=here(w)
  for _,p in ipairs(C.get_connected_players()) do
    local name=p:get_player_name()
    local in_w=brickcraft.world_at(p:get_pos())==w
    -- In war, an attacker fights on the Red Army's side here.
    local s=api.war[name]
    if s then
      local want=in_w and side(name)=="attack" and "red" or (s.team=="red" and "blue")
      if want and s.team~=want then api.set_team(name,want) end
    end
    if not in_w then hud(p,nil); welcomed[name]=nil end
  end
  if #people==0 then
    if g then g.alone=(g.alone or 0)+step; if g.alone>30 then end_game(w) end end
    return
  end
  if not g then g=new_game(w) end
  g.alone=0
  cannons(w)
  for _,p in ipairs(people) do
    local name=p:get_player_name()
    if not welcomed[name] then
      welcomed[name]=true
      C.chat_send_player(name,C.colorize("#ffd27a",w.name..": the Red Army comes along the roads in "..WAVES.." waves; keep it out of the castle's gates! "..
        "You're "..(side(name)=="attack" and "attacking" or "defending")..": /td switches. Defenders right click the gold pads beside the roads "..
        "for towers, the road for barricades and traps, the lever at the north fork to turn the north road. Attackers send knights and attacks from /td."))
    end
    hud(p,g)
  end
  local t=now()
  if g.phase=="over" then
    if t>=g.next then new_game(w) end
    return
  end
  -- The war chest fills: faster while a wave is on.
  if t-g.income>=5 then g.income=t; g.chest=g.chest+(g.phase=="wave" and 6 or 3) end
  if g.phase=="build" and t>=g.next then start_wave(g) end
  while g.queue[#g.queue] and g.queue[#g.queue].at<=t do
    local q=table.remove(g.queue)
    spawn_enemy(g,q.road,q.kind)
  end
  local foes=enemies(g)
  -- Tar slows whoever is on it; footmen called up for a while go.
  for _,e in ipairs(foes) do
    local p=e.object:get_pos()
    if C.get_node(vector.round({x=p.x,y=p.y-.3,z=p.z})).name=="brickcraft:td_tar" then chill(e,.4,1) end
  end
  for ent in pairs(api.things) do
    if ent._td==w.id and ent._expire and ent._expire<t and ent.object:get_pos() then api.poof(ent.object:get_pos()); api.things[ent]=nil; ent.object:remove() end
  end
  towers_turn(g,foes)
  if g.phase=="wave" and #g.queue==0 and #foes==0 then
    local alive=false
    for ent in pairs(api.things) do if on_field(g,ent) and ent._lane then alive=true end end
    if not alive then
      if g.wave>=WAVES then over(g,"All "..WAVES.." waves beaten: the defenders win!"); return end
      local bonus=15+5*g.wave
      g.gold=g.gold+bonus
      g.phase,g.next="build",t+BUILD
      tell(w,("Wave %d beaten! +%d gold. The next comes in %d s (/td: call it early for more gold)."):format(g.wave,bonus,BUILD))
    end
  end
end)

C.register_chatcommand("td",{params="[attack|defend|next|reset]",
  description="Tower Defense: the side menu (spells, or sending knights), switch side, call the next wave, or start over",
  func=function(name,param)
    local p=C.get_player_by_name(name)
    local w=td_world()
    if not p or not w or brickcraft.world_at(p:get_pos())~=w then return false,"Go to the Tower Defense world first (Which world?)." end
    local g=games[w.id] or new_game(w)
    param=param:lower():match("%a*")
    if param=="attack" or param=="defend" then
      sides[name]=param~="defend" and "attack" or nil
      tell(w,api.label(p).." is "..(param=="attack" and "attacking with the Red Army" or "defending the castle").." now.")
      return true
    end
    if param=="next" then
      if g.phase~="build" then return false,"A wave is on already." end
      g.gold=g.gold+math.max(0,math.ceil(g.next-now())); g.next=now()
      return true,"Here it comes!"
    end
    if param=="reset" then new_game(w); return true end
    open_panel(name)
    return true
  end})

C.after(0,function()
  if brickcraft.testing and not C.settings:get_bool("brickcraft_td_test",false) then return end
  local w=td_world()
  if w then
    if w.built and not w.td_built then
      C.emerge_area({x=w.x-R,y=-2,z=w.z-R},{x=w.x+R,y=31,z=w.z+R},function(_,_,r) if r==0 then lay_out(w,true); w.td_built=true; brickcraft.save_worlds() end end)
    end
    return
  end
  w=brickcraft.make_world("Tower Defense (experimental)","BrickCraft",function(w) lay_out(w,true); w.td_built=true; brickcraft.save_worlds() end)
  C.log("action","BrickCraft Tower Defense "..(w and "being made at "..w.x..","..w.z or "has no room"))
  if w then w.td=true; brickcraft.save_worlds() end
end)

return {lane_step=lane_step,games=games,sides=sides,world=td_world,new_game=new_game,build_tower=build_tower,upgrade=upgrade,
  sell=sell,road_work=road_work,flip_lever=flip_lever,cast=cast,attack=attack,send=send,spawn_enemy=spawn_enemy,
  start_wave=start_wave,menu=menu,enemies=enemies,ROUTES=ROUTES,ROAD=ROAD,PAD=PAD,LEVER=LEVER,KINDS=KINDS,TOWERS=TOWERS,
  castle_hp=CASTLE_HP,waves=WAVES,key=key}
end
