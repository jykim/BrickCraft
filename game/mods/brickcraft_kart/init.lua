-- Kart Circuit (experimental): a world made once, after Tower Defense, with a race track on a
-- flat field. The track is one closed loop of waypoints (a Catmull-Rom curve through them,
-- cut into samples every half cell): a long start straight under a gantry with start lights,
-- a sweeping bend, a climb onto a bridge that crosses the lower road (a figure eight), a
-- descent, a hairpin, a dip under the bridge, S bends with a kicker jump and a last hairpin.
-- Boost pads speed you up; rows of banana bunches on the road give bananas to throw, and
-- buildings and trees between the roads keep any racer from seeing the whole track.
-- Everyone in the world races together: right click a kart on the grid (or /kart), and the
-- race starts JOIN seconds later with CPU racers (the family's other block people, jms and
-- the knights) filling the grid up to RACERS. Three red lights, then green: LAPS laps.
-- A banana thrown ahead or dropped behind spins out whoever runs into it, and a spin sends a
-- kart sliding sideways, off the bridge if it's there: it falls off the track ("derails")
-- and is put back on it a second later, stopped.
-- Karts drive like the cars of APercy's Automobiles Pack (MIT): speed along the kart and
-- sideways are kept apart, the sideways part dies off with the tyres' grip (less grip while
-- drifting), and the steering turns it by (1 - 1/(speed + 1)), so a kart barely turns
-- standing still. Laps count like PanqKart's checkpoints: progress along the track only grows
-- going the right way, so a lap can't be skipped or driven backwards. Holding Space in a turn
-- drifts (a little hop first); let go after a second for a mini-turbo, after two for a
-- longer one.
-- The karts are entities that move themselves (no engine physics, like the train carts):
-- their height comes from the track's own curve where they are on it, and the flat field
-- (y -0.5) where they aren't. Nothing of a race is saved: a restart starts at the grid.
local C=core
local now=function() return C.get_us_time()/1e6 end

local LAYOUT_VERSION=3 -- v2: buildings and trees; v3: long-jump ramps and crates
local R=44 -- the field: ±R round the center, flat (the hills stay beyond)
local HALF=3.5 -- half the road's width
local SAMPLE=.5 -- cells between samples along the track
local LAPS,RACERS,JOIN=3,6,15 -- laps, karts on the grid with CPU racers, seconds to jump in
local VMAX,VMAX_GRASS,BOOST_V=11,5,16 -- top speeds (cells/s): road, grass, boosting
local ACCEL,BRAKE,REVERSE,ROLL=9,18,4,4
local GRIP,DRIFT_GRIP,TURN=12,3,2.3 -- sideways speed lost per second; turning (rad/s)
local G,SLOPE_G=20,8 -- falling; slowing uphill (and speeding downhill) per unit of slope
local SPIN,RESCUE=1.3,1 -- seconds spun out by a banana; seconds before a fallen kart is back

-- The track: waypoints x, z (from the center) and the road's height there.
local POINTS={{-26,-34,0},{-6,-34,0},{16,-34,0},{30,-30,0},{36,-18,0},{34,-4,1},{26,8,3},{14,14,4.5},{0,15,5},
  {-14,14,4.5},{-26,18,3},{-34,28,1},{-28,37,0},{-14,37,0},{-6,30,0},{-2,22,0},{10,8,0},{14,-2,0},{6,-12,0},
  {-8,-8,0},{-20,-14,0},{-32,-22,0}}
local START={-14,-34} -- the start line; the grid is behind it
-- Jumps: where each ramp drops straight back down, its length (samples) and height. The
-- kicker in the S bends, and two long ramps on the straights (a boost pad before the first)
-- that throw a fast kart ten cells and more.
local JUMPS={{-15,-11,12,1.5},{14,-34,16,2},{-16,37,16,2}}
local BOOSTS={{4,-34},{35,-12},{-4,26},{-27,-17}}
local BOXES={{-6,-34},{-28,35},{12,2}} -- rows of banana bunches
local CRATES={{28,-34,-1.6},{36,-21,1.6},{-23,-16,2}} -- x, z, cells right of the middle

-- Samples: x, z, h (height of the road over the field), tx, tz (unit tangent), slope (dh/ds),
-- open (a bridge: nothing under it), boost.
local S={}
do
  local fine,n={},#POINTS
  local function cr(a,b,c,d,t,k)
    return .5*(2*b[k]+(-a[k]+c[k])*t+(2*a[k]-5*b[k]+4*c[k]-d[k])*t*t+(-a[k]+3*b[k]-3*c[k]+d[k])*t*t*t)
  end
  for i=1,n do
    local a,b,c,d=POINTS[(i-2)%n+1],POINTS[i],POINTS[i%n+1],POINTS[(i+1)%n+1]
    for k=0,199 do local t=k/200; fine[#fine+1]={cr(a,b,c,d,t,1),cr(a,b,c,d,t,2),cr(a,b,c,d,t,3)} end
  end
  local raw,acc={{x=fine[1][1],z=fine[1][2],h=fine[1][3]}},0
  for i=2,#fine do
    local p,q=fine[i-1],fine[i]
    acc=acc+math.sqrt((q[1]-p[1])^2+(q[2]-p[2])^2)
    if acc>=SAMPLE then raw[#raw+1]={x=q[1],z=q[2],h=q[3]}; acc=0 end
  end
  -- Sample 1 is the start line.
  local first,bd=1
  for i,s in ipairs(raw) do
    local d=(s.x-START[1])^2+(s.z-START[2])^2
    if not bd or d<bd then first,bd=i,d end
  end
  for i=1,#raw do S[i]=raw[(first+i-2)%#raw+1] end
end
local N=#S
local function wrap(i) return (i-1)%N+1 end
local function nearest_to(x,z)
  local best,bd
  for i,s in ipairs(S) do
    local d=(s.x-x)^2+(s.z-z)^2
    if not bd or d<bd then best,bd=i,d end
  end
  return best
end
for _,jp in ipairs(JUMPS) do
  local j,n,h=nearest_to(jp[1],jp[2]),jp[3],jp[4]
  for k=0,n-1 do local s=S[wrap(j-n+k)]; s.h=s.h+h*(k+1)/n end
end
for i,s in ipairs(S) do
  local a,b=S[wrap(i-1)],S[wrap(i+1)]
  local dx,dz=b.x-a.x,b.z-a.z
  local l=math.sqrt(dx*dx+dz*dz)
  s.tx,s.tz=dx/l,dz/l
  -- Across the kicker's drop, the slope of the side that isn't the drop.
  local fwd,back=(b.h-s.h)/SAMPLE,(s.h-a.h)/SAMPLE
  s.slope=math.abs(b.h-s.h)>.5 and back or math.abs(s.h-a.h)>.5 and fwd or (fwd+back)/2
end
-- A bridge: high road within reach of road well below it (that road runs under it).
for i,s in ipairs(S) do
  if s.h>=3 then
    for _,o in ipairs(S) do
      if s.h-o.h>=3 and (s.x-o.x)^2+(s.z-o.z)^2<(2*HALF+1.5)^2 then s.open=true; break end
    end
  end
end
for _,b in ipairs(BOOSTS) do
  local j=nearest_to(b[1],b[2])
  for k=0,3 do S[wrap(j+k)].boost=true end
end
local BOX_AT={}
for _,b in ipairs(BOXES) do BOX_AT[#BOX_AT+1]=nearest_to(b[1],b[2]) end
-- Crates on the road, a cell high: steer round them or jump them.
local CRATE_AT={} -- {j, lat, x, z (its cell)}
for _,c in ipairs(CRATES) do
  local j=nearest_to(c[1],c[2])
  local s=S[j]
  CRATE_AT[#CRATE_AT+1]={j=j,lat=c[3],x=math.floor(s.x+s.tz*c[3]+.5),z=math.floor(s.z-s.tx*c[3]+.5)}
end

local function right_of(s) return s.tz,-s.tx end -- the road's right, seen driving along it
local function yaw_of(dx,dz) return math.atan2(-dx,dz) end
local function wrap_angle(a) return (a+math.pi)%(2*math.pi)-math.pi end
local function clamp(v,a,b) return math.max(a,math.min(b,v)) end

-- The sample nearest x, z: within span of hint if there is one, else anywhere (leaving out
-- bridges well over y, which don't hold it up).
local function nearest(x,z,y,hint,span)
  local best,bd
  local function try(j)
    local s=S[j]
    if not hint and s.open and s.h-.5>y+1.5 then return end
    local d=(s.x-x)^2+(s.z-z)^2
    if not bd or d<bd then best,bd=j,d end
  end
  if hint then for d=-span,span do try(wrap(hint+d)) end
  else for j=1,N do try(j) end end
  return best,math.sqrt(bd or 1e9)
end
-- Under x, z for something at height y: the top it stands on (relative to the world's
-- center height), whether that's the road, the sample, and how far right of the middle.
local function ground(x,z,y,hint)
  local j,dist=nearest(x,z,y,hint,hint and 24)
  if not j or dist>HALF+4 then j,dist=nearest(x,z,y) end
  local s=S[j]
  local dx,dz=x-s.x,z-s.z
  local rx,rz=right_of(s)
  local lat=dx*rx+dz*rz
  if math.abs(lat)<=HALF and dist<=HALF+.5 then
    local top=-.5+s.h+(dx*s.tx+dz*s.tz)*s.slope
    if not (s.open and top>y+1.5) then return top,j,lat,true end
  end
  return -.5,j,lat,false
end

-- Nodes: the field's own ground and the road (none of it collected or dug). The road's top
-- follows the curve in quarter cells: a full node and a slab 1–3 quarters high on it.
local function node(name,desc,tiles,extra)
  local def={description=desc,tiles=tiles,groups={not_in_creative_inventory=1},diggable=false,is_ground_content=false}
  for k,v in pairs(extra or {}) do def[k]=v end
  C.register_node(":brickcraft:"..name,def)
end
local OURS={}
local function slabs(name,desc,tiles)
  node(name,desc,tiles); OURS["brickcraft:"..name]=true
  for q=1,3 do
    node(name.."_"..q,desc,tiles,{drawtype="nodebox",paramtype="light",node_box={type="fixed",fixed={-.5,-.5,-.5,.5,-.5+q/4,.5}}})
    OURS["brickcraft:"..name.."_"..q]=true
  end
end
local ROAD_TEX="brickcraft_kart_road.png"
node("kart_grass","Field",{"brickcraft_grass.png","brickcraft_dirt.png","brickcraft_grass_side.png"})
slabs("kart_road","Race Track",{ROAD_TEX})
slabs("kart_curb_red","Curb",{"brickcraft_coral.png",ROAD_TEX})
slabs("kart_curb_white","Curb",{"brickcraft_cream.png",ROAD_TEX})
slabs("kart_fill","Track Bank",{ROAD_TEX,ROAD_TEX,"brickcraft_tan.png"})
for _,n in ipairs({
  {"kart_start","Start Line",{"brickcraft_kart_check.png",ROAD_TEX}},
  {"kart_boost","Boost Pad",{"brickcraft_kart_boost.png",ROAD_TEX},{paramtype2="facedir",light_source=4}},
  {"kart_pillar","Bridge Pillar",{"brickcraft_navy.png"}},
  {"kart_gantry","Start Gantry",{"brickcraft_kart_check.png","brickcraft_kart_check.png","brickcraft_cream.png"}},
  {"kart_light_off","Start Light",{"brickcraft_navy.png^[colorize:#101010:180"}},
  {"kart_light_red","Start Light",{"brickcraft_coral.png^[colorize:#ff2010:140"},{light_source=10}},
  {"kart_light_green","Start Light",{"brickcraft_mint.png^[colorize:#30ff60:120"},{light_source=10}},
  {"kart_window","Window",{"brickcraft_sky.png^[colorize:#dff4ff:110"},{light_source=3}},
  {"kart_roof","Roof",{"brickcraft_navy.png"}},
  {"kart_crate","Crate (jump it: Space)",{"brickcraft_trunk.png^[colorize:#c08a4a:110"}},
  {"kart_trunk","Tree Trunk",{"brickcraft_trunk_top.png","brickcraft_trunk_top.png","brickcraft_trunk.png"}},
  {"kart_leaves","Leaves",{"brickcraft_leaves.png"}},
}) do node(n[1],n[2],n[3],n[4]); OURS["brickcraft:"..n[1]]=true end
for _,c in ipairs({"coral","gold","mint","sky","violet","rose","cream"}) do
  node("kart_wall_"..c,"Building",{"brickcraft_"..c..".png"}); OURS["brickcraft:kart_wall_"..c]=true
end

-- Where each kind of node goes, by cell: one or two layers of road (two where the bridge
-- crosses the lower road), each the sample nearest the cell in it.
local CELLS={} -- "x,z" -> {layer,...}; layer = {j, lat, top}
local function key(x,z) return x..","..z end
do
  local near={}
  for j,s in ipairs(S) do
    local rx,rz=right_of(s)
    for x=math.floor(s.x-HALF-1),math.ceil(s.x+HALF+1) do for z=math.floor(s.z-HALF-1),math.ceil(s.z+HALF+1) do
      local dx,dz=x-s.x,z-s.z
      local d=math.sqrt(dx*dx+dz*dz)
      if d<=HALF+.3 then
        local k=key(x,z)
        near[k]=near[k] or {}
        local l=near[k]
        l[#l+1]={j=j,d=d,lat=dx*rx+dz*rz,top=-.5+s.h+(dx*s.tx+dz*s.tz)*s.slope}
      end
    end end
  end
  for k,l in pairs(near) do
    table.sort(l,function(a,b) return a.d<b.d end)
    local layers={l[1]}
    for _,c in ipairs(l) do
      if math.abs(S[c.j].h-S[l[1].j].h)>=3 then layers[2]=c; break end
    end
    if math.abs(layers[1].lat)<=HALF then CELLS[k]=layers end
  end
end
local function boost_dir(s)
  if math.abs(s.tx)>math.abs(s.tz) then return s.tx>0 and 1 or 3 end
  return s.tz>0 and 0 or 2
end
-- The gantry over the start line: posts either side, a checkered beam at y 5 and the three
-- start lights hanging under it.
local GANTRY,LIGHTS={},{}
do
  local s=S[1]
  local rx,rz=right_of(s)
  for lat=-HALF-1,HALF+1,.5 do
    local x,z=math.floor(s.x+rx*lat+.5),math.floor(s.z+rz*lat+.5)
    GANTRY[key(x,z)]={beam=true,post=math.abs(lat)>=HALF+1}
  end
  for _,lat in ipairs({-1,0,1}) do
    LIGHTS[#LIGHTS+1]={x=math.floor(s.x+rx*lat+.5),y=4,z=math.floor(s.z+rz*lat+.5)}
  end
end
-- Buildings and trees between the roads, so no racer sees the whole track at once: on a
-- loose grid, wherever one fits two cells clear of the road and the gantry, and not in the
-- middle (where players arrive). Karts run into them like into the side of a raised road.
local PIECES,BLOCKED={},{} -- {kind, x0, z0, x1, z1, h, color}; "x,z" -> the top a kart can't get under
for _,c in ipairs(CRATE_AT) do BLOCKED[c.x..","..c.z]=.5 end
do
  local function rnd(a,b) return (math.sin(a*12.9898+b*78.233)*43758.5453)%1 end
  local function clear(x0,z0,x1,z1)
    if math.max(math.abs(x0),math.abs(x1),math.abs(z0),math.abs(z1))>R-3 then return false end
    if x1>=-9 and x0<=9 and z1>=-7 and z0<=7 then return false end
    for x=x0-2,x1+2 do for z=z0-2,z1+2 do
      if CELLS[key(x,z)] or GANTRY[key(x,z)] or BLOCKED[key(x,z)] then return false end
    end end
    return true
  end
  local WALLS={"coral","gold","mint","sky","violet","rose","cream"}
  for gz=-40,40,6 do for gx=-40,40,6 do
    local r=rnd(gx,gz)
    local x,z=gx+math.floor(rnd(gz,gx)*3)-1,gz+math.floor(r*3)-1
    if r<.6 then
      local wd,dp=3+math.floor(rnd(x,z+1)*3),3+math.floor(rnd(x+1,z)*3)
      local x0,z0=x-math.floor(wd/2),z-math.floor(dp/2)
      local x1,z1=x0+wd-1,z0+dp-1
      if clear(x0,z0,x1,z1) then
        local h=4+math.floor(rnd(x+2,z)*6)
        PIECES[#PIECES+1]={"house",x0,z0,x1,z1,h,WALLS[math.floor(rnd(z,x+3)*#WALLS)+1]}
        for bx=x0,x1 do for bz=z0,z1 do BLOCKED[key(bx,bz)]=h+.5 end end
      end
    elseif clear(x-1,z-1,x+1,z+1) then
      PIECES[#PIECES+1]={"tree",x,z,x,z,3+math.floor(rnd(x,z+5)*2)}
      BLOCKED[key(x,z)]=3
    end
  end end
end

-- Lays the field out: the first time everything in it (hills and trees go), after that only
-- its own nodes and air (bricks players put on it stay).
local function lay_out(w,first)
  local vm=C.get_voxel_manip()
  local emin,emax=vm:read_from_map({x=w.x-R,y=-2,z=w.z-R},{x=w.x+R,y=26,z=w.z+R})
  local area=VoxelArea:new({MinEdge=emin,MaxEdge=emax})
  local data,p2=vm:get_data(),vm:get_param2_data()
  local id=C.get_content_id
  local air,grass,plate=id("air"),id("brickcraft:kart_grass"),id("brickcraft:baseplate")
  local ours={}
  for name in pairs(OURS) do ours[id(name)]=true end
  local built={} -- "x,z" -> {y -> name}, the buildings and trees
  local function put(x,z,y,name) local k=key(x,z); built[k]=built[k] or {}; built[k][y]=built[k][y] or name end
  for _,pc in ipairs(PIECES) do
    local kind,x0,z0,x1,z1,h,color=unpack(pc)
    if kind=="house" then
      for x=x0,x1 do for z=z0,z1 do
        local edge=x==x0 or x==x1 or z==z0 or z==z1
        local corner=(x==x0 or x==x1) and (z==z0 or z==z1)
        for y=0,h-1 do
          put(x,z,y,edge and not corner and y%3==1 and (x+z)%2==0 and "brickcraft:kart_window" or "brickcraft:kart_wall_"..color)
        end
        put(x,z,h,"brickcraft:kart_roof")
      end end
    else
      for y=0,h-1 do put(x0,z0,y,"brickcraft:kart_trunk") end
      for dy=-1,1 do
        local rad=dy==1 and 1 or 2
        for dx=-rad,rad do for dz=-rad,rad do
          if dx~=0 or dz~=0 or dy>=0 then
            if math.abs(dx)+math.abs(dz)<=rad+1 then put(x0+dx,z0+dz,h+dy,"brickcraft:kart_leaves") end
          end
        end end
      end
    end
  end
  for _,c in ipairs(CRATE_AT) do put(c.x,c.z,math.floor(S[c.j].h+.5),"brickcraft:kart_crate") end
  for z=-R,R do for x=-R,R do
    local want={} -- y -> {name, param2}
    for y,name in pairs(built[key(x,z)] or {}) do want[y]={name} end
    want[-1]={"brickcraft:kart_grass"}
    local layers=CELLS[key(x,z)]
    for _,c in ipairs(layers or {}) do
      local s=S[c.j]
      local top=math.floor(c.top*4+.5)/4
      local yf=math.floor(top-.5+1e-6) -- the highest full node
      local q=math.floor((top-(yf+.5))*4+.5)
      if q>=4 then yf,q=yf+1,0 end
      local kind="kart_road"
      if math.abs(c.lat)>HALF-1 then kind=math.floor(c.j/4)%2==0 and "kart_curb_red" or "kart_curb_white" end
      local flat,param=nil,0
      if c.j==1 or c.j==2 or c.j==N then flat="kart_start"
      elseif s.boost and math.abs(c.lat)<HALF-1.2 then flat,param="kart_boost",boost_dir(s) end
      local from=s.open and yf or -1
      for y=from,yf do want[y]={"brickcraft:kart_fill"} end
      if q>0 then want[yf+1]={"brickcraft:"..kind.."_"..q}
      else want[yf]={"brickcraft:"..(flat or kind),param} end
      -- Pillars along the bridge's edges, where nothing runs under it.
      if s.open and #layers==1 and math.abs(c.lat)>=HALF-1.5 and (x+z)%3==0 then
        for y=0,yf-1 do want[y]={"brickcraft:kart_pillar"} end
      end
    end
    local g=GANTRY[key(x,z)]
    if g then
      want[5]={"brickcraft:kart_gantry"}
      if g.post then for y=0,4 do want[y]={"brickcraft:kart_gantry"} end end
    end
    if first then data[area:index(w.x+x,-2,w.z+z)]=plate end
    for y=-1,26 do
      local i=area:index(w.x+x,y,w.z+z)
      local n=want[y]
      if n then
        if first or data[i]==air or ours[data[i]] or data[i]==grass then data[i]=id(n[1]); p2[i]=n[2] or 0 end
      elseif first or ours[data[i]] then data[i]=air end
    end
  end end
  for _,l in ipairs(LIGHTS) do data[area:index(w.x+l.x,l.y,w.z+l.z)]=id("brickcraft:kart_light_off") end
  vm:set_data(data); vm:set_param2_data(p2); vm:write_to_map(false)
  C.fix_light({x=w.x-R,y=-2,z=w.z-R},{x=w.x+R,y=31,z=w.z+R})
end
local function lights(w,n,green)
  for i,l in ipairs(LIGHTS) do
    C.swap_node({x=w.x+l.x,y=l.y,z=w.z+l.z},{name="brickcraft:kart_light_"..(green and "green" or i<=n and "red" or "off")})
  end
end

-- Who drives: players race as who they play; CPU racers are the rest of the family, jms and
-- the knights. Each has a kart color.
local KART_COLOR={builder="sky",dad="navy",daughter="rose",explorer="mint",jms="gold",knight="cream",blueknight="violet",redknight="coral"}
local CPU={
  {id="daughter"},{id="dad"},{id="explorer"},{id="builder"},
  {id="jms",label="jms",mesh="brickcraft_person.obj",tex="brickcraft_person_jms.png",tag="#ffb36b"},
  {id="knight",label="Brick Knight",mesh="brickcraft_person.obj",tex="brickcraft_person_knight.png",tag="#d8dde6"},
  {id="blueknight",label="Blue Knight",mesh="brickcraft_person.obj",tex="brickcraft_person_blueknight.png",tag="#8fc8ff"},
  {id="redknight",label="Red Knight",mesh="brickcraft_person.obj",tex="brickcraft_person_redknight.png",tag="#ff9a76"},
}
local function look_of(c)
  local st=brickcraft.styles[c.id]
  if st then return {id=c.id,label=st.label,mesh=st.mesh,tex=st.tex,tag=st.tag} end
  return c
end

local function kart_world() for _,w in ipairs(brickcraft.worlds()) do if w.kart then return w end end end
local game -- the race on now (one Kart Circuit): {w, phase, karts={}, next, t0, places={}}
local riding={} -- player name -> the kart they're in
local map_was={} -- player name -> whether their minimap was allowed before
local q_until={} -- player name -> until when Q steers their kart left
local MAP_MODES={{type="off"},{type="surface",size=256},{type="surface",size=128},{type="surface",size=64},
  {type="radar",size=512},{type="radar",size=256},{type="radar",size=128}} -- the engine's own
local bananas,boxes={},{} -- entity -> true
local function here(w)
  local out={}
  for _,p in ipairs(C.get_connected_players()) do if brickcraft.world_at(p:get_pos())==w then out[#out+1]=p end end
  return out
end
local function tell(w,msg,color)
  for _,p in ipairs(here(w)) do C.chat_send_player(p:get_player_name(),C.colorize(color or "#ffd27a",msg)) end
end
local function label_of(kart)
  if kart._bot then return kart._bot.label end
  local p=kart._rider and C.get_player_by_name(kart._rider)
  local st=p and brickcraft.playing_as(p) and brickcraft.styles[brickcraft.playing_as(p)]
  return st and st.label or kart._name or kart._rider or "?"
end
local function ordinal(n) return n..((n%100>=11 and n%100<=13) and "th" or ({"st","nd","rd"})[n%10] or "th") end

-- Map blocks of the field stay active while a race is on, so karts far from everyone keep
-- driving (and aren't lost: karts aren't saved).
local function forceload(w,on)
  for x=w.x-R,w.x+R+15,16 do for z=w.z-R,w.z+R+15,16 do for _,y in ipairs({-1,8}) do
    local p={x=math.min(x,w.x+R),y=y,z=math.min(z,w.z+R)}
    if on then C.forceload_block(p,true,-1) else C.forceload_free_block(p,true) end
  end end end
end

-- Karts. State: _p (where it is, the object follows), _yaw (its heading), _vl, _vt (speed
-- along it and sideways), _vy, _air, _steer (-1 right .. 1 left), _i (its track sample),
-- _prog (samples driven since the start line, the right way), _bananas, _rider (a player's
-- name) or _bot (a look), and timers (_spin, _boost, _fell).
local KART="brickcraft:kart"
local function rider_of(kart)
  local p=kart._rider and C.get_player_by_name(kart._rider)
  if p and p:get_attach()==kart.object then return p end
end
local function drop_rider(kart,move)
  local name=kart._rider
  if not name then return end
  kart._rider=nil
  riding[name]=nil
  C.log("action","BrickCraft kart: "..name.." got out")
  local p=C.get_player_by_name(name)
  if p and p:get_attach()==kart.object then
    p:set_detach()
    p:set_eye_offset({x=0,y=0,z=0},{x=0,y=0,z=0})
    p:set_minimap_modes(MAP_MODES,0)
    p:hud_set_flags({minimap=map_was[name]~=false})
    map_was[name]=nil
    if move~=false then
      local s=S[kart._i]
      local rx,rz=right_of(s)
      local side=kart._lat and kart._lat>0 and -1 or 1
      local w=game.w
      C.after(0,function()
        if p:get_pos() then p:set_pos({x=w.x+s.x+rx*(HALF+1.5)*side,y=math.max(kart._p.y,0)+.6,z=w.z+s.z+rz*(HALF+1.5)*side}) end
      end)
    end
  end
end
local function board(kart,player)
  local name=player:get_player_name()
  if riding[name] or kart._rider or kart._bot then return false end
  kart._rider=name
  riding[name]=kart
  C.log("action","BrickCraft kart: "..name.." got in")
  local st=brickcraft.playing_as(player) and brickcraft.styles[brickcraft.playing_as(player)]
  kart._name=st and st.label or name
  player:set_attach(kart.object,"",{x=0,y=-3,z=-1.5},{x=0,y=0,z=0})
  player:set_look_horizontal(kart._yaw)
  player:set_look_vertical(.18)
  player:set_eye_offset({x=0,y=0,z=0},{x=0,y=4,z=-6})
  -- The minimap shows the whole track from above, every kart a dot on it.
  map_was[name]=player:hud_get_flags().minimap
  player:hud_set_flags({minimap=true})
  player:set_minimap_modes({{type="surface",label="Kart Circuit",size=176},{type="off",label="Map off"}},0)
  local id=brickcraft.playing_as(player)
  kart._color=KART_COLOR[id or ""] or "sky"
  kart.object:set_properties({textures={"brickcraft_cart_wheel.png","brickcraft_"..kart._color..".png","brickcraft_navy.png"}})
  return true
end
local function seat_bot(kart,look)
  kart._bot=look
  kart._skill=.88+math.random()*.08
  kart._lane=(math.random()-.5)*2.4
  kart._color=KART_COLOR[look.id] or "cream"
  kart.object:set_properties({textures={"brickcraft_cart_wheel.png","brickcraft_"..kart._color..".png","brickcraft_navy.png"}})
  local d=C.add_entity(kart.object:get_pos(),"brickcraft:kart_driver")
  if d then
    d:set_properties({mesh=look.mesh,textures={look.tex},nametag=look.label,nametag_color=look.tag})
    d:set_attach(kart.object,"",{x=0,y=-3,z=-1.5},{x=0,y=0,z=0})
    kart._driver=d
  end
end

local function spin(kart,by)
  local t=now()
  if (kart._spin or 0)>t or (kart._fell or 0)>0 then return false end
  kart._spin=t+SPIN
  kart._vl=kart._vl*.4
  kart._vt=(math.random()<.5 and -1 or 1)*4.5 -- it slides off sideways: off the bridge, if it's there
  kart._drift,kart._boost=nil,nil
  local p=rider_of(kart)
  if p then C.chat_send_player(p:get_player_name(),C.colorize("#ffe14a","Banana!"..(by and " ("..by..")" or ""))) end
  C.add_particlespawner({amount=12,time=.2,minpos=vector.subtract(kart._p,.3),maxpos=vector.add(kart._p,.3),
    minvel={x=-2,y=1,z=-2},maxvel={x=2,y=3,z=2},minexptime=.4,maxexptime=.8,minsize=2,maxsize=4,texture="brickcraft_smoke.png"})
  return true
end
local function throw(kart,ahead)
  if (kart._bananas or 0)<=0 then return end
  kart._bananas=kart._bananas-1
  local f={x=-math.sin(kart._yaw),z=math.cos(kart._yaw)}
  local p=kart._p
  local at=ahead and {x=p.x+f.x*1.2,y=p.y+.6,z=p.z+f.z*1.2} or {x=p.x-f.x*1.4,y=p.y+.3,z=p.z-f.z*1.4}
  local obj=C.add_entity(at,"brickcraft:kart_banana")
  local b=obj and obj:get_luaentity()
  if not b then return end
  b._g,b._by,b._from,b._i=game,label_of(kart),kart,kart._i
  b._at=now()
  if ahead then b._v={x=f.x*(math.max(kart._vl,0)+9),y=4,z=f.z*(math.max(kart._vl,0)+9)} else b._v={x=0,y=0,z=0} end
  bananas[b]=true
  return b
end

-- The CPU racers drive at a point on the road ahead (further at speed) in their own lane,
-- moving over for bananas lying there; they ease off in tight turns, and try to keep
-- within reach of the players (a little faster well behind them, slower well ahead). They
-- drop bananas on racers right behind and throw them at racers just ahead.
local function bot_controls(kart,karts)
  local w=game.w
  local p=kart._p
  local i=kart._i
  local lane=kart._lane or 0
  local ahead=wrap(i+math.floor(8+math.abs(kart._vl)*.9))
  local s=S[ahead]
  local rx,rz=right_of(s)
  for b in pairs(bananas) do
    if b._g==game and b._lying and b.object:get_pos() then
      local bp=b.object:get_pos()
      local dx,dz=bp.x-p.x,bp.z-p.z
      local fwd=dx*-math.sin(kart._yaw)+dz*math.cos(kart._yaw)
      if fwd>0 and fwd<10 and dx*dx+dz*dz<100 then
        local bs=S[b._i or i]
        local brx,brz=right_of(bs)
        local blat=(bp.x-w.x-bs.x)*brx+(bp.z-w.z-bs.z)*brz
        if math.abs(blat-lane)<1.3 then lane=clamp(blat+(blat>0 and -2.2 or 2.2),-2.4,2.4) end
      end
    end
  end
  for _,c in ipairs(CRATE_AT) do
    local d=c.j-i
    if d<-N/2 then d=d+N end
    if d>0 and d<24 and math.abs(c.lat-lane)<1.4 then lane=clamp(c.lat+(c.lat>0 and -2.2 or 2.2),-2.4,2.4) end
  end
  local tx,tz=w.x+s.x+rx*lane,w.z+s.z+rz*lane
  local diff=wrap_angle(yaw_of(tx-p.x,tz-p.z)-kart._yaw)
  -- Keeping within reach of the players.
  local skill=kart._skill or .9
  local best
  for _,k in ipairs(karts) do if k._rider and not k._place and (not best or k._prog>best) then best=k._prog end end
  if best then
    if kart._prog<best-N*.15 then skill=skill+.07 elseif kart._prog>best+N*.1 then skill=skill-.07 end
  end
  local c={steer=clamp(diff*2.2,-1,1),up=kart._vl<VMAX*skill}
  if math.abs(diff)>.7 and kart._vl>7 then c.up=false end
  if math.abs(diff)>1.2 and kart._vl>5 then c.down=true end
  local t=now()
  if (kart._bananas or 0)>0 and t>(kart._item_next or 0) then
    for _,k in ipairs(karts) do
      if k~=kart then
        local gap=k._prog-kart._prog
        if gap<0 and gap>-14 then c.drop=true end
        if gap>8 and gap<28 then
          local dx,dz=k._p.x-p.x,k._p.z-p.z
          if math.abs(wrap_angle(yaw_of(dx,dz)-kart._yaw))<.25 then c.throw=true end
        end
      end
    end
    if c.drop or c.throw then kart._item_next=t+2+math.random()*3 end
  end
  return c
end
-- How a player steers: "keys" (A/D, the view fixed behind the kart, the default) or "mouse"
-- (the kart turns where they look), and whether smart steering helps them keep on the road.
local function steer_mode(p) return p:get_meta():get_string("brickcraft_kart_steer")=="mouse" and "mouse" or "keys" end
local function assisted(p) return p:get_meta():get_string("brickcraft_kart_assist")~="off" end
local function controls(kart,karts)
  if kart._input then return kart._input end -- (tests)
  if kart._bot or kart._place or kart._autopilot then return bot_controls(kart,karts) end -- (finished: it drives itself)
  local p=rider_of(kart)
  if not p then return {} end
  local c=p:get_player_control()
  -- A/D or the arrows steer; so do Q (each press steers left for a moment: the engine only
  -- sends it as repeated presses) and E (held: zoom).
  local steer=clamp((c.left and 1 or 0)-(c.right and 1 or 0)+((q_until[p:get_player_name()] or 0)>now() and 1 or 0)-(c.zoom and 1 or 0),-1,1)
  -- Steering with the mouse (/kart mouse): the kart turns the way its driver looks.
  if steer_mode(p)=="mouse" then steer=clamp(wrap_angle(p:get_look_horizontal()-kart._yaw)*2.5,-1,1) end
  return {up=c.up,down=c.down,steer=steer,drift=c.jump,throw=c.dig or c.sneak,drop=c.place,jump=c.jump,reset=c.aux1,human=true}
end

-- Puts a fallen kart back on the middle of the road where it was, stopped.
local function rescue(kart)
  local w=game.w
  local s=S[kart._i]
  kart._p={x=w.x+s.x,y=s.h-.5,z=w.z+s.z}
  kart._yaw=yaw_of(s.tx,s.tz)
  kart._vl,kart._vt,kart._vy,kart._air,kart._fell,kart._spin,kart._gy=0,0,0,false,nil,nil,nil
  kart.object:set_pos(kart._p)
  local p=rider_of(kart)
  if p then p:set_look_horizontal(kart._yaw); C.chat_send_player(p:get_player_name(),C.colorize("#9ee6c6","Back on the track!")) end
end

local function drive(kart,dt,karts)
  local w=game.w
  local t=now()
  local c=controls(kart,karts)
  local was=kart._was or {}
  kart._was=c
  if (kart._fell or 0)>0 then
    if t>=kart._fell then rescue(kart) end
    return
  end
  -- Tab (or /kart reset): back on the middle of the road; so is a kart stuck for 3 s.
  if c.reset and not was.reset and t>(kart._reset_at or 0) then kart._reset_at=t+1; rescue(kart); return end
  if c.up and math.abs(kart._vl)<.5 and not kart._air then
    kart._stuck=kart._stuck or t
    if t-kart._stuck>3 then kart._stuck=nil; rescue(kart); return end
  else kart._stuck=nil end
  local spun=(kart._spin or 0)>t
  if spun then c={} end
  local on_road=kart._road~=false
  local boosting=(kart._boost or 0)>t
  local top=boosting and BOOST_V or on_road and VMAX or VMAX_GRASS
  local vl=kart._vl
  if c.up then
    vl=vl<top and math.min(top,vl+(boosting and ACCEL*2 or ACCEL)*dt) or math.max(top,vl-ROLL*2*dt)
  elseif c.down then
    vl=vl>.3 and vl-BRAKE*dt or math.max(-REVERSE,vl-ACCEL*.5*dt)
  else
    vl=vl>0 and math.max(0,vl-ROLL*dt) or math.min(0,vl+ROLL*dt)
  end
  if vl>top+.1 then vl=math.max(top,vl-ROLL*3*dt) end
  if spun then vl=vl*math.exp(-2.5*dt) end
  -- Slopes: uphill slows a kart, downhill speeds it up.
  local s=S[kart._i]
  local f={x=-math.sin(kart._yaw),z=math.cos(kart._yaw)}
  local along=f.x*s.tx+f.z*s.tz
  if on_road and not kart._air then vl=vl-SLOPE_G*s.slope*along*dt end
  -- Drifting: Space held in a turn at speed, a hop first; let go for a mini-turbo.
  if c.drift and not was.drift and not kart._air and (c.steer or 0)~=0 and vl>5 then
    kart._drift,kart._charge=(c.steer>0 and 1 or -1),0
    kart._vy,kart._air=3,true
  end
  -- Space going straight: a jump, high enough for a banana or a crate.
  if c.drift and not was.drift and not kart._air and not kart._drift and (c.steer or 0)==0 and math.abs(vl)>=1 then
    kart._vy,kart._air=8,true
  end
  if kart._drift then
    if c.drift and vl>4 and not spun then kart._charge=kart._charge+dt
    else
      if kart._charge>=1 then kart._boost=t+(kart._charge>=2 and 1.4 or .8); vl=math.max(vl,VMAX+2) end
      kart._drift=nil
    end
  end
  -- Steering (Automobiles Pack): little turning when slow, none standing still.
  local want=c.steer or 0
  if c.human then
    -- Smart steering (as in Mario Kart): near the edge of the road and heading off it, a
    -- little steer back on.
    local pl=rider_of(kart)
    local s0=S[kart._i]
    local lat,ang=kart._lat or 0,wrap_angle(kart._yaw-yaw_of(s0.tx,s0.tz))
    if pl and assisted(pl) and kart._road~=false and not kart._drift and math.abs(lat)>HALF-1.6 and lat*ang<0 then
      want=clamp(want+clamp(lat*.25-ang*1.5,-.7,.7),-1,1)
    end
    -- The wheels turn over a moment (Automobiles Pack's steering speed), back quicker.
    local rate=(want==0 or want*(kart._steer or 0)<0) and 9 or 5
    local cur=kart._steer or 0
    kart._steer=cur<want and math.min(want,cur+rate*dt) or math.max(want,cur-rate*dt)
  else kart._steer=want end
  local steer=kart._drift and clamp(kart._drift*.75+kart._steer*.5,-1.2,1.2) or kart._steer
  local turn=TURN*(kart._drift and 1.25 or 1)*(1-1/(math.abs(vl)+1))*(vl>=0 and 1 or -1)
  local dyaw=spun and 0 or steer*turn*dt
  kart._yaw=wrap_angle(kart._yaw+dyaw)
  f={x=-math.sin(kart._yaw),z=math.cos(kart._yaw)}
  local r={x=f.z,z=-f.x}
  -- Sideways speed: what the old heading's speed has sideways now, less what the grip takes.
  local vt=kart._vt+vl*math.sin(-dyaw)
  vt=vt*math.exp(-(kart._drift and DRIFT_GRIP or spun and 1.5 or GRIP)*dt)
  if kart._drift then vt=vt-kart._drift*vl*.08 end -- the back swings out
  kart._vl,kart._vt=vl,vt
  local vx,vz=f.x*vl+r.x*vt,f.z*vl+r.z*vt
  local p=kart._p
  local nx,nz=p.x+vx*dt,p.z+vz*dt
  -- Other karts push each other apart.
  for _,k in ipairs(karts) do
    if k~=kart and k._p then
      local dx,dz=nx-k._p.x,nz-k._p.z
      local d=math.sqrt(dx*dx+dz*dz)
      if d<1.1 and d>0 and math.abs(k._p.y-p.y)<1 then
        nx,nz=nx+dx/d*(1.1-d)*.6,nz+dz/d*(1.1-d)*.6
        if dx*vx+dz*vz<0 then kart._vl=kart._vl*.85 end
      end
    end
  end
  nx,nz=clamp(nx,w.x-R+1,w.x+R-1),clamp(nz,w.z-R+1,w.z+R-1)
  -- What's under it: the road or the field, or the top of a crate it's up on.
  local function under(x,z)
    local g,jj,l,rd=ground(x-w.x,z-w.z,p.y,kart._i)
    local top=BLOCKED[key(math.floor(x-w.x+.5),math.floor(z-w.z+.5))]
    if top and p.y>=top-.35 then return math.max(g,top),jj,l,rd,nil end
    return g,jj,l,rd,top
  end
  local gy,j,lat,road,wall=under(nx,nz)
  -- The side of a raised road, a building, a tree or a crate bumps it back; but a kart
  -- already in one (landed in it, put there) drives out.
  local _,_,_,_,inside=under(p.x,p.z)
  if (gy>p.y+.6 and not ((kart._gy or p.y)>p.y+.6)) or (wall and p.y<wall and not inside) then
    nx,nz=p.x,p.z
    kart._vl,kart._vt=-kart._vl*.25,0
    gy,j,lat,road=under(nx,nz)
  end
  kart._gy=gy
  local y=p.y
  local vy=kart._vy or 0
  local fall=y+vy*dt-.5*G*dt*dt
  if gy>=fall then
    if kart._air and (kart._peak or y)-gy>.9 and not road then
      -- Off the road from up high: derailed. It's put back in a moment.
      kart._fell=t+RESCUE
      kart._drift=nil
      local pl=rider_of(kart)
      if pl then C.chat_send_player(pl:get_player_name(),C.colorize("#ff9a76","Off the track!")) end
    end
    vy=kart._air and 0 or (gy-y)/dt
    y=gy
    kart._air,kart._peak=false,nil
  else
    if not kart._air then kart._peak=y end
    kart._air=true
    y=fall
    vy=vy-G*dt
    kart._peak=math.max(kart._peak or y,y)
  end
  kart._vy=vy
  kart._road=road
  kart._lat=lat
  -- Progress the right way round (a lap is N samples); jumps over a big stretch don't count.
  local d=j-kart._i
  if d>N/2 then d=d-N elseif d<-N/2 then d=d+N end
  if math.abs(d)<=60 then kart._prog=kart._prog+d end
  kart._i=j
  -- Boost pads.
  if road and S[j].boost and math.abs(lat)<HALF-1 and not kart._air then kart._boost=t+1.2 end
  -- Going the wrong way.
  local sj=S[j]
  if f.x*sj.tx+f.z*sj.tz<-.5 and kart._vl>2 then kart._wrong=(kart._wrong or t) else kart._wrong=nil end
  -- Bananas.
  if c.throw and not was.throw and not spun then throw(kart,true) end
  if c.drop and not was.drop and not spun then throw(kart,false) end
  local np={x=nx,y=y,z=nz}
  local move={x=(nx-p.x)/dt,y=(y-p.y)/dt,z=(nz-p.z)/dt}
  kart._p=np
  -- The object follows: its velocity keeps it smooth between server steps.
  local obj=kart.object
  local off=vector.subtract(np,obj:get_pos())
  if vector.length(off)>1 then obj:set_pos(np); off={x=0,y=0,z=0} end
  obj:set_velocity(vector.add(move,vector.multiply(off,5)))
  local rot=vector.dir_to_rotation({x=f.x,y=(road and not kart._air) and sj.slope*(f.x*sj.tx+f.z*sj.tz) or 0,z=f.z})
  rot.y=kart._yaw+(spun and (1-(kart._spin-t)/SPIN)*4*math.pi or 0)
  obj:set_rotation(rot)
  local pl=rider_of(kart)
  -- Steering with the keys, the view stays behind the kart, looking a little down the road
  -- (a mouse or trackpad can't swing it off); steering with the mouse, it's theirs.
  if pl and steer_mode(pl)=="keys" then
    if math.abs(wrap_angle(pl:get_look_horizontal()-kart._yaw))>.01 then pl:set_look_horizontal(kart._yaw) end
    if math.abs(pl:get_look_vertical()-.18)>.03 then pl:set_look_vertical(.18) end
  end
  -- Drift sparks: blue after a second, orange after two.
  if kart._drift and kart._charge>=1 and math.random()<.5 then
    C.add_particle({pos={x=np.x-f.x*.7,y=np.y+.15,z=np.z-f.z*.7},velocity={x=-f.x+math.random()-.5,y=1.5,z=-f.z+math.random()-.5},
      expirationtime=.3,size=1.5,glow=14,texture=kart._charge>=2 and "brickcraft_gold.png" or "brickcraft_sky.png"})
  end
end

C.register_entity(":"..KART,{
  initial_properties={visual="mesh",mesh="brickcraft_kart.obj",
    textures={"brickcraft_cart_wheel.png","brickcraft_cream.png","brickcraft_navy.png"},
    -- visual_size 1, the mesh in engine units: the engine draws what's attached (the player,
    -- a CPU racer) in its parent's scale, and places it in it too.
    visual_size={x=1,y=1},backface_culling=false,physical=false,pointable=true,static_save=false,show_on_minimap=true,
    collisionbox={-.45,0,-.7,.45,.5,.7},selectionbox={-.45,0,-.7,.45,.5,.7,rotate=true}},
  on_activate=function(self) self.object:set_armor_groups({immortal=1}) end,
  on_rightclick=function(self,clicker)
    if not clicker or not clicker:is_player() or not game or self._g~=game then return end
    local name=clicker:get_player_name()
    if self._rider==name then return end
    if game.phase~="lobby" and game.phase~="join" then
      C.chat_send_player(name,"A race is on: the next one starts at the grid when it's over.")
      return
    end
    if self._rider or self._bot then C.chat_send_player(name,"Someone's in that kart: pick another."); return end
    if board(self,clicker) then
      C.chat_send_player(name,C.colorize("#9ee6c6","W: go   S: brake   A/D or Q/E: steer   Space: jump (in a turn: drift)   left click or Shift: throw a banana   right click: drop one behind   Tab: back on the track   Space standing still: hop out"))
    end
  end,
  on_punch=function() return true end,
  on_detach_child=function(self,child)
    if child:is_player() and child:get_player_name()==self._rider then riding[self._rider]=nil; self._rider=nil end
  end,
  on_step=function(self,dtime)
    if not game or self._g~=game then self.object:remove(); return end
    local p=rider_of(self)
    if self._rider and not p then riding[self._rider]=nil; self._rider=nil end
    -- Space standing still hops out (in a race too: that's the end of their race).
    if p then
      local jump=p:get_player_control().jump
      if jump and not self._jumped and math.abs(self._vl)<1 and not self._air and game.phase~="countdown" then
        self._jumped=jump
        drop_rider(self)
        return
      end
      self._jumped=jump
    end
    if game.phase=="race" or game.phase=="done" then
      if self._rider or self._bot or self._place then drive(self,math.min(dtime,.2),game.karts)
      else self.object:set_velocity({x=0,y=0,z=0}) end
    else
      self.object:set_velocity({x=0,y=0,z=0})
      if vector.distance(self.object:get_pos(),self._p)>.05 then self.object:set_pos(self._p) end
    end
  end,
})
C.register_entity(":brickcraft:kart_driver",{
  initial_properties={visual="mesh",mesh="brickcraft_person.obj",textures={"brickcraft_person.png"},visual_size={x=10,y=10},
    physical=false,pointable=false,static_save=false,nametag_bgcolor="#14293699"},
  on_step=function(self) if not self.object:get_attach() then self.object:remove() end end,
})

-- Bananas: thrown in an arc ahead, or dropped behind; one lying on the road spins out the
-- first kart to run over it, and one in the air the first it hits.
C.register_entity(":brickcraft:kart_banana",{
  initial_properties={visual="sprite",textures={"brickcraft_kart_banana.png"},visual_size={x=.7,y=.7},
    physical=false,pointable=false,static_save=false},
  on_step=function(self,dtime)
    local obj=self.object
    if not game or self._g~=game then bananas[self]=nil; obj:remove(); return end
    local w=game.w
    local p=obj:get_pos()
    if not self._lying then
      dtime=math.min(dtime,.2)
      local v=self._v
      v.y=v.y-G*dtime
      local n={x=p.x+v.x*dtime,y=p.y+v.y*dtime,z=p.z+v.z*dtime}
      local gy,j=ground(n.x-w.x,n.z-w.z,p.y-.3,self._i)
      self._i=j
      if math.abs(n.x-w.x)>R or math.abs(n.z-w.z)>R then bananas[self]=nil; obj:remove(); return end
      if n.y-.3<=gy then n.y=gy+.3; self._lying=true; v={x=0,y=0,z=0} end
      self._v=v
      obj:set_pos(n); obj:set_velocity(v)
      p=n
    end
    local t=now()
    for _,k in ipairs(game.karts) do
      if k._p and (k~=self._from or t-self._at>.6) then
        local dx,dz=k._p.x-p.x,k._p.z-p.z
        local over=self._lying and k._air and k._p.y>p.y+.1 -- jumped over it
        if dx*dx+dz*dz<(self._lying and .8 or 1.1)^2 and math.abs(k._p.y+.3-p.y)<1 and not over then
          if spin(k,self._from~=k and self._by.."'s" or nil) or self._lying then
            bananas[self]=nil; obj:remove(); return
          end
        end
      end
    end
  end,
})
-- Banana bunches lying on the road: a kart over one picks up a banana (sometimes three);
-- it keeps at most three. A bunch is back 3 seconds after it's taken.
C.register_entity(":brickcraft:kart_bunch",{
  initial_properties={visual="sprite",textures={"brickcraft_kart_bunch.png"},visual_size={x=.9,y=.9},
    glow=8,physical=false,pointable=false,static_save=false},
  on_step=function(self)
    local obj=self.object
    if not game or self._g~=game then boxes[self]=nil; obj:remove(); return end
    local t=now()
    if self._back then
      if t<self._back then return end
      self._back=nil; obj:set_properties({is_visible=true})
    end
    if game.phase~="race" then return end
    local p=obj:get_pos()
    for _,k in ipairs(game.karts) do
      local dx,dz=k._p.x-p.x,k._p.z-p.z
      if dx*dx+dz*dz<1.3^2 and math.abs(k._p.y+.45-p.y)<1.2 then
        local had=k._bananas or 0
        k._bananas=math.min(3,had+(math.random()<.25 and 3 or 1))
        self._back=t+3; obj:set_properties({is_visible=false})
        local pl=rider_of(k)
        if pl and k._bananas>had then C.chat_send_player(pl:get_player_name(),C.colorize("#ffe14a","Bananas: "..k._bananas)) end
        return
      end
    end
  end,
})

-- The race: lobby (karts parked on the grid) -> join (someone's in: JOIN seconds for more)
-- -> countdown (CPU racers in, three red lights, then green) -> race -> done (results;
-- the grid again a little later).
local laps,racers=LAPS,RACERS
local function grid_slot(k)
  local s=S[wrap(1-5*math.ceil(k/2))]
  local rx,rz=right_of(s)
  local lat=k%2==1 and -1.6 or 1.6
  return wrap(1-5*math.ceil(k/2)),s.x+rx*lat,s.z+rz*lat
end
local function clear(g)
  for _,k in ipairs(g.karts) do
    drop_rider(k)
    if k.object:get_pos() then k.object:remove() end
  end
  for b in pairs(bananas) do if b.object:get_pos() then b.object:remove() end end
  for b in pairs(boxes) do if b.object:get_pos() then b.object:remove() end end
  bananas,boxes={},{}
  g.karts={}
end
local function park(g)
  local w=g.w
  for k=1,8 do
    local i,x,z=grid_slot(k)
    local s=S[i]
    local p={x=w.x+x,y=-.5+s.h,z=w.z+z}
    local obj=C.add_entity(p,KART)
    local kart=obj and obj:get_luaentity()
    if kart then
      kart._g,kart._p,kart._yaw,kart._i,kart._prog=g,p,yaw_of(s.tx,s.tz),i,i-1-N
      kart._vl,kart._vt,kart._vy,kart._bananas,kart._slot=0,0,0,0,k
      obj:set_yaw(kart._yaw)
      g.karts[#g.karts+1]=kart
    end
  end
  for _,i in ipairs(BOX_AT) do
    local s=S[i]
    local rx,rz=right_of(s)
    for _,lat in ipairs({-2.4,-.8,.8,2.4}) do
      local obj=C.add_entity({x=w.x+s.x+rx*lat,y=s.h-.05,z=w.z+s.z+rz*lat},"brickcraft:kart_bunch")
      local b=obj and obj:get_luaentity()
      if b then b._g=g; boxes[b]=true end
    end
  end
  lights(w,0)
end
local function new_game(w)
  if game then clear(game); if game.loaded then forceload(game.w,false) end end
  game={w=w,phase="lobby",karts={},places={}}
  park(game)
  return game
end
local function humans(g)
  local out={}
  for _,k in ipairs(g.karts) do if rider_of(k) then out[#out+1]=k end end
  return out
end
local function standings(g)
  local list={}
  for _,k in ipairs(g.karts) do if k._rider or k._bot or k._place then list[#list+1]=k end end
  table.sort(list,function(a,b)
    if a._place or b._place then return (a._place or 99)<(b._place or 99) end
    return a._prog>b._prog
  end)
  return list
end
local function fill(g)
  local taken={}
  for _,k in ipairs(g.karts) do
    local p=rider_of(k)
    if p and brickcraft.playing_as(p) then taken[brickcraft.playing_as(p)]=true end
  end
  local looks={}
  for _,c in ipairs(CPU) do if not taken[c.id] then looks[#looks+1]=look_of(c) end end
  local n=#humans(g)
  for _,k in ipairs(g.karts) do
    if n>=racers or #looks==0 then break end
    if not k._rider then seat_bot(k,table.remove(looks,math.random(#looks))); n=n+1 end
  end
end
local function start_race(g)
  if g.phase~="lobby" and g.phase~="join" then return false end
  fill(g)
  g.phase,g.next=("countdown"),now()+4
  tell(g.w,("%d racers, %d lap%s: get ready!"):format(#standings(g),laps,laps==1 and "" or "s"),"#9ee6c6")
  return true
end
local function finish(g,kart)
  g.places[#g.places+1]=kart
  kart._place=#g.places
  kart._time=now()-g.t0
  local who=label_of(kart)
  tell(g.w,("%s finished %s (%.1f s)!"):format(who,ordinal(kart._place),kart._time),kart._rider and "#9ee6c6" or "#ffd27a")
  if kart._rider then g.human_done=now() end
end
local function results(g)
  local rows={}
  for n,k in ipairs(standings(g)) do
    local who=label_of(k)..(k._bot and " (CPU)" or "")
    rows[#rows+1]=k._place and ("%s   %s   %.1f s"):format(ordinal(k._place),who,k._time) or ("--   %s   (didn't finish)"):format(who)
  end
  tell(g.w,"Results:  "..table.concat(rows,"  /  "),"#ffd27a")
  local cells={}
  for _,r in ipairs(rows) do cells[#cells+1]=C.formspec_escape(r) end
  for _,p in ipairs(here(g.w)) do
    C.show_formspec(p:get_player_name(),"brickcraft:kart_results","formspec_version[6]size[9,7]bgcolor[#142936;true]"..
      "label[.6,.6;KART CIRCUIT / RESULTS]textlist[.6,1.1;7.8,4.8;rows;"..table.concat(cells,",")..";0;false]"..
      "button_exit[2.7,6.1;3.6,.6;ok;OK]")
  end
end

-- Each racer's line at the top of the screen, and a big word in the middle when there's one.
local huds={} -- player name -> {top, big}
local function hud(p,top,big,color)
  local name=p:get_player_name()
  local h=huds[name]
  if not h then
    h={top=p:hud_add({type="text",position={x=.5,y=0},offset={x=0,y=28},text="",number=0xffd27a,alignment={x=0,y=0},scale={x=100,y=20}}),
       big=p:hud_add({type="text",position={x=.5,y=.35},offset={x=0,y=0},text="",number=0xffffff,alignment={x=0,y=0},scale={x=100,y=20},size={x=4,y=4}})}
    huds[name]=h
  end
  p:hud_change(h.top,"text",top)
  p:hud_change(h.big,"text",big or "")
  p:hud_change(h.big,"number",color or 0xffffff)
end
local function hud_off(p)
  local h=huds[p:get_player_name()]
  if h then p:hud_remove(h.top); p:hud_remove(h.big); huds[p:get_player_name()]=nil end
end

local timer,welcomed=0,{}
C.register_globalstep(function(dt)
  timer=timer+dt
  if timer<.2 then return end
  timer=0
  local w=kart_world()
  if not w or not w.kart_built then return end
  local people=here(w)
  local names={}
  for _,p in ipairs(people) do
    local name=p:get_player_name()
    names[name]=true
    if welcomed[name]~=w then
      welcomed[name]=w
      C.chat_send_player(name,C.colorize("#ff9a76",w.name..": right click a kart on the grid at the start (or type /kart) to race! "..
        "W go, S brake, A/D or Q/E steer, Space jumps (in a turn: drifts). Drive over the banana bunches on the road to pick bananas up: left click or Shift throws one ahead, right click drops one behind."))
    end
  end
  for name in pairs(welcomed) do if not names[name] then welcomed[name]=nil end end
  for name,h in pairs(huds) do
    local p=C.get_player_by_name(name)
    if p and not riding[name] then hud_off(p) end
  end
  if #people==0 then
    if game and game.phase~="lobby" then new_game(w) end
    return
  end
  local g=(game and game.w==w) and game or new_game(w)
  local t=now()
  -- Karts aren't saved: a grid left behind unloaded is gone, and parked again.
  if g.phase=="lobby" then
    for _,k in ipairs(g.karts) do if not k.object:get_pos() then g=new_game(w); break end end
  end
  local racing=humans(g)
  if g.phase=="lobby" and #racing>0 then
    g.phase,g.next="join",t+JOIN
    tell(w,label_of(racing[1]).." is in a kart! The race starts in "..JOIN.." s: right click a kart to join.","#9ee6c6")
  elseif g.phase=="join" then
    if #racing==0 then g.phase="lobby"
    elseif t>=g.next then start_race(g) end
  elseif g.phase=="countdown" then
    local left=g.next-t
    if left<=0 then
      g.phase,g.t0="race",t
      lights(w,0,true)
      forceload(w,true); g.loaded=true
    else lights(w,math.min(3,math.floor(4-left))) end
  elseif g.phase=="race" then
    for _,k in ipairs(g.karts) do
      if not k._place and (k._rider or k._bot) and k._prog>=laps*N then finish(g,k) end
    end
    local left=0
    for _,k in ipairs(g.karts) do if k._rider and not k._place then left=left+1 end end
    local all=true
    for _,k in ipairs(g.karts) do if (k._rider or k._bot) and not k._place then all=false end end
    if (left==0 and (not g.human_done or all or t>g.human_done+10)) or t>g.t0+360 then
      g.phase,g.next="done",t+12
      results(g)
      lights(w,0)
      forceload(w,false); g.loaded=false
    end
  elseif g.phase=="done" and t>=g.next then
    new_game(w)
    tell(w,"The grid is ready: right click a kart for the next race.","#9ee6c6")
    return
  end
  -- HUDs.
  local order=standings(g)
  for n,k in ipairs(order) do k._rank=n end
  for _,k in ipairs(g.karts) do
    local p=rider_of(k)
    if p then
      local top,big,color
      if g.phase=="lobby" or g.phase=="join" then
        top=g.phase=="join" and ("Race in %d s   (%d in karts)"):format(math.max(0,math.ceil(g.next-t)),#racing) or "Waiting for the race"
      else
        local lap=clamp(math.floor(k._prog/N)+1,1,laps)
        top=("Lap %d/%d     %s of %d     Bananas %d     %.1f s"):format(lap,laps,ordinal(k._rank or 1),#order,k._bananas or 0,
          k._place and k._time or g.t0 and t-g.t0 or 0)
        local red=math.floor(4-(g.next or t)+t)
        if g.phase=="countdown" then
          if red>=1 then big,color=tostring(4-red),0xff5040 end
        elseif g.t0 and t-g.t0<1 then big,color="GO!",0x40ff70
        elseif k._place then big,color="Finished "..ordinal(k._place).."!",0xffd27a
        elseif k._wrong and t-k._wrong>1.5 then big,color="Wrong way!",0xff5040
        elseif (k._fell or 0)>0 then big,color="Off the track!",0xff9a76
        elseif k._prog>=(laps-1)*N and k._prog<(laps-1)*N+30 then big,color="Final lap!",0xffd27a end
      end
      hud(p,top,big,color)
    end
  end
end)
C.register_on_leaveplayer(function(player)
  local name=player:get_player_name()
  huds[name]=nil
  local k=riding[name]
  if k then k._rider=nil; riding[name]=nil end
end)

-- A player in a kart has their hands on the wheel: clicks throw bananas, and place or use
-- nothing they hold.
C.register_on_mods_loaded(function()
  for iname,def in pairs(C.registered_items) do
    local over={}
    for _,f in ipairs({"on_place","on_use","on_secondary_use"}) do
      local fn=def[f]
      if fn then over[f]=function(stack,user,pt) if user and user:is_player() and riding[user:get_player_name()] then return stack end return fn(stack,user,pt) end end
    end
    if next(over) then C.override_item(iname,over) end
  end
end)

C.register_chatcommand("kart",{params="[reset|leave|start|keys|mouse|assist on/off|laps <1-9>|racers <1-8>]",
  description="Kart Circuit: get in a kart on the grid, hop out, start the race now, or set the laps and how many race",
  func=function(name,param)
    local p=C.get_player_by_name(name)
    local w=kart_world()
    if not p or not w or brickcraft.world_at(p:get_pos())~=w or not w.kart_built then return false,"Go to the Kart Circuit world first (Which world?)." end
    local g=(game and game.w==w) and game or new_game(w)
    local word,n=param:lower():match("^(%a*)%s*(%d*)")
    n=tonumber(n)
    if word=="mouse" or word=="keys" then
      p:get_meta():set_string("brickcraft_kart_steer",word)
      return true,word=="mouse" and "Steering with the mouse: the kart turns where you look (/kart keys: back to A/D)."
        or "Steering with A/D; the view stays behind your kart (/kart mouse: steer by looking)."
    end
    if word=="assist" then
      local off=param:lower():find("off")~=nil
      p:get_meta():set_string("brickcraft_kart_assist",off and "off" or "")
      return true,"Smart steering "..(off and "off." or "on: it helps you keep on the road.")
    end
    if word=="reset" then
      local k=riding[name]
      if not k then return false,"You're not in a kart." end
      if game.phase~="race" and game.phase~="done" then return false,"Your kart is on the grid: the race hasn't started." end
      rescue(k); return true
    end
    if word=="leave" then
      if not riding[name] then return false,"You're not in a kart." end
      drop_rider(riding[name]); return true
    end
    if word=="start" then
      if #humans(g)==0 then return false,"Get in a kart first." end
      return start_race(g),"Starting!"
    end
    if word=="laps" and n then laps=clamp(math.floor(n),1,9); tell(w,"Races are "..laps.." lap"..(laps==1 and "" or "s").." now."); return true end
    if word=="racers" and n then racers=clamp(math.floor(n),1,8); tell(w,"Races fill up to "..racers.." karts now."); return true end
    if riding[name] then return false,"You're in a kart already (Space standing still, or /kart leave, to hop out)." end
    if g.phase~="lobby" and g.phase~="join" then return false,"A race is on: the next one starts at the grid when it's over." end
    for _,k in ipairs(g.karts) do
      if not k._rider and not k._bot and board(k,p) then return true,"In! W: go   A/D: steer   Space in a turn: drift   left click: throw a banana" end
    end
    return false,"Every kart is taken."
  end})

for _,row in ipairs({
  {"KART CIRCUIT (its own world: Which world?)",""},
  {"Right click a kart on the grid, or /kart","Get in; the race starts 15 s later"},
  {"W / S","Go / brake (and back up)"},{"A / D, Q / E or arrows","Steer"},
  {"Space going straight","Jump: over bananas and crates (and off the big ramps)"},
  {"Space in a turn","Drift; let go after 1 s (blue sparks) or 2 s (orange) for a boost"},
  {"Left click or Shift / right click","Throw a banana ahead / drop one behind (drive over a bunch to pick some up)"},
  {"Tab, /kart reset","Stuck? Back on the middle of the road"},
  {"/kart mouse, /kart keys","Steer by looking, or with A/D (the default: the view stays behind the kart)"},
  {"/kart assist off (or on)","Smart steering: a little help keeping on the road"},
  {"Space standing still, /kart leave","Hop out"},{"/kart start, /kart laps 5, /kart racers 4","Start now, laps, karts in a race"},
}) do brickcraft.help[#brickcraft.help+1]=row end

C.after(0,function()
  if brickcraft.testing and not C.settings:get_bool("brickcraft_kart_test",false) then return end
  local w=kart_world()
  if w then
    if w.built and (not w.kart_built or (w.kart_version or 1)<LAYOUT_VERSION) then
      -- (a circuit from before the buildings keeps what players built and gets them added)
      C.emerge_area({x=w.x-R,y=-2,z=w.z-R},{x=w.x+R,y=31,z=w.z+R},function(_,_,r)
        if r==0 then lay_out(w,not w.kart_built); w.kart_built,w.kart_version=true,LAYOUT_VERSION; brickcraft.save_worlds() end
      end)
    end
    return
  end
  w=brickcraft.make_world("Kart Circuit (experimental)","BrickCraft",function(w) lay_out(w,true); w.kart_built,w.kart_version=true,LAYOUT_VERSION; brickcraft.save_worlds() end)
  C.log("action","BrickCraft Kart Circuit "..(w and "being made at "..w.x..","..w.z or "has no room"))
  if w then w.kart=true; brickcraft.save_worlds() end
end)

brickcraft.kart={world=kart_world,game=function() return game end,new_game=new_game,start=start_race,board=board,
  drop_rider=drop_rider,spin=spin,steer_left=function(name) q_until[name]=now()+.35 end,throw=throw,ground=ground,riding=function(name) return riding[name] end,
  bananas=function() return bananas end,S=S,N=N,HALF=HALF,LIGHTS=LIGHTS,BOX_AT=BOX_AT,CRATE_AT=CRATE_AT,JUMPS=JUMPS,key=key,CELLS=CELLS,PIECES=PIECES,BLOCKED=BLOCKED,
  set_laps=function(n) laps=n end,set_racers=function(n) racers=n end,laps=function() return laps end,
  nearest=nearest_to,lay_out=lay_out}
