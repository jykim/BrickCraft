-- Strict LEGO worlds: a world made with "Strict LEGO" on only takes builds real bricks could
-- make. On the game's grid (a cell is 2 x 2 studs and one brick tall) that means:
--   * a piece clicks onto studs right below it or hangs from a piece right above it; touching
--     at the side holds nothing, and tiles, plates (their studs are too low to reach the cell
--     above) and the sloped side of a slope have no studs to click onto;
--   * a piece can't be pushed into a gap that holds it from above and below at once;
--   * nothing comes loose: a piece can't be collected (or turned) while something would then
--     hang in the air, joined to the ground by no studs at all;
--   * an axle or gear sits on a line through a technic brick's hole (or a motor's output);
--   * every piece is a real part (shapes marked `invented` can't be used).
-- The ground, the baseplate and anything else that isn't a piece count as studs all over.
-- A cell is split into four quarters, one per stud; studs and the hollow underside that
-- grips them are kept per quarter, so a 1 x 2 offset over two bricks clicks onto both.
local C=core
return function(env)
local world_at,primary_of,tail_pos=env.world_at,env.primary_of,env.tail_pos
local M={}

-- Stud spots (quarter centers) in a piece's own cells, its long side toward +z.
local ALL={{-.25,-.25},{.25,-.25},{-.25,.25},{.25,.25}}
local HALF={{-.25,-.25},{-.25,.25}} -- a 1 x 2 on the -x half of its cell
local ONE={{-.25,-.25}}
local BACK={{-.25,.25},{.25,.25}} -- a slope's top row, an inverted slope's foot
local LONG={{-.25,-.25},{.25,-.25},{-.25,.25},{.25,.25},{-.25,.75},{.25,.75},{-.25,1.25},{.25,1.25}}
-- top: studs that reach the cell above (nil: none); bottom: where it grips (default: its body).
local SPEC={
  ["2x2"]={bottom=ALL,top=ALL}, ["1x2"]={bottom=HALF,top=HALF},
  ["2x4"]={bottom=LONG,top=LONG}, ["1x1"]={bottom=ONE,top=ONE},
  plate={bottom=ALL}, plate_1x2={bottom=HALF}, plate_2x4={bottom=LONG}, plate_1x1={bottom=ONE},
  tile_2x2={bottom=ALL}, tile_1x2={bottom=HALF},
  round_2x2={bottom=ALL,top=ALL}, round_1x1={bottom=ONE,top=ONE},
  slope_2x2={bottom=ALL,top=BACK}, slope_2x1={bottom=HALF,top={{-.25,.25}}},
  slope_inv_2x2={bottom=BACK,top=ALL},
}
local BRICK_LIKE={bottom=ALL,top=ALL}
local FOOT_ONLY={bottom=ALL} -- track, a motor or battery box on the ground
-- Why nothing clicks onto a piece's top, for the refusal.
local NO_TOP={plate="a plate's studs are too low to reach",plate_1x2="a plate's studs are too low to reach",
  plate_2x4="a plate's studs are too low to reach",plate_1x1="a plate's studs are too low to reach",
  tile_2x2="tiles are smooth",tile_1x2="tiles are smooth",slope_2x2="the sloped side has no studs",
  slope_2x1="the sloped side has no studs",track="track has no studs on top"}

local function key(p) return p.x..","..p.y..","..p.z end
local function rot(x,z,r)
  if r==1 then return z,-x elseif r==2 then return -x,-z elseif r==3 then return -z,x end
  return x,z
end
local function quarter(u) return u>0 and 1 or 0 end
-- Spots (local x, z) turned by r into {cell key -> {cell, {quarter index -> true}}}.
local function spread(pos,spots,r,into)
  for _,s in ipairs(spots or {}) do
    local u,v=rot(s[1],s[2],r)
    local ox,oz=math.floor(u+.5),math.floor(v+.5)
    local cell={x=pos.x+ox,y=pos.y,z=pos.z+oz}
    local k=key(cell)
    into[k]=into[k] or {cell=cell,q={}}
    into[k].q[quarter(u-ox)+2*quarter(v-oz)+1]=true
  end
  return into
end

local AXES={[0]={x=0,y=1,z=0},{x=0,y=0,z=1},{x=0,y=0,z=-1},{x=1,y=0,z=0},{x=-1,y=0,z=0},{x=0,y=-1,z=0}}
local function is_piece(def,name)
  return def and (C.get_item_group(name,"brick_tail")==1 or
    (C.get_item_group(name,"brick")==1 and not def.brickcraft_scenery))
end
-- What a piece at pos (its primary cell) would be as node: its cells, studs on top, grip
-- underneath, and for technic pieces the line it lies on. nil if node isn't a piece.
function M.describe(pos,node)
  local def=C.registered_nodes[node.name]
  if not is_piece(def,node.name) then return end
  local shape,power=def.brickcraft_shape,def.brickcraft_power
  local d={pos=vector.copy(pos),node=node,shape=shape,power=power,cells={}}
  local r=node.param2%4
  if power=="axle" or power=="gear" then
    d.axis=AXES[math.floor(node.param2/4)%6]
    d.cells[key(pos)]={cell=vector.copy(pos)}
    return d
  end
  if power=="brick" or power=="motor" then d.axis=C.facedir_to_dir(r) end
  local spec=SPEC[shape] or ((shape=="track" or power=="motor" or power=="battery") and FOOT_ONLY) or BRICK_LIKE
  local bottom,top=spread(pos,spec.bottom or ALL,r,{}),spread(pos,spec.top,r,{})
  for k,c in pairs(bottom) do d.cells[k]={cell=c.cell,bottom=c.q} end
  for k,c in pairs(top) do d.cells[k]=d.cells[k] or {cell=c.cell}; d.cells[k].top=c.q end
  -- A long piece's tail cell is part of it even where it has no studs.
  if def.brickcraft_long then
    local t=tail_pos(pos,node.param2)
    d.cells[key(t)]=d.cells[key(t)] or {cell=t}
  end
  return d
end

-- A view of the world while checking: `gone` cells read as air, `pieces` (cell key ->
-- description) stand where nothing is built yet. Descriptions are cached per view.
local function new_view(gone,pieces) return {gone=gone or {},pieces=pieces or {},cache={}} end
local function add_piece(view,d) for k in pairs(d.cells) do view.pieces[k]=d end end
local function piece_at(view,cell)
  local k=key(cell)
  if view.pieces[k] then return view.pieces[k] end
  if view.gone[k] then return end
  if view.cache[k]~=nil then return view.cache[k] or nil end
  local node=C.get_node(cell)
  local d=false
  if is_piece(C.registered_nodes[node.name],node.name) then
    local p,pn=primary_of(cell,node)
    d=view.cache[key(p)] or M.describe(p,pn) or false
    if d and not d.cells[k] then d=false end -- a tail cell its primary no longer claims
    if d then for ck in pairs(d.cells) do view.cache[ck]=d end end
  end
  view.cache[k]=d
  return d or nil
end
-- Ground: below the floor, or something solid that isn't a piece (hills, baseplate).
local function ground(view,cell)
  if view.gone[key(cell)] or view.pieces[key(cell)] then return false end
  if cell.y<-1 then return true end
  local node=C.get_node(cell)
  local def=C.registered_nodes[node.name]
  if not def or node.name=="ignore" then return true end
  return def.walkable and not is_piece(def,node.name)
end
local function overlap(a,b)
  if not (a and b) then return false end
  for i=1,4 do if a[i] and b[i] then return true end end
  return false
end
local function up(c) return {x=c.x,y=c.y+1,z=c.z} end
local function down(c) return {x=c.x,y=c.y-1,z=c.z} end
local function parallel(a,b) return a and b and math.abs(a.x*b.x+a.y*b.y+a.z*b.z)>.99 end

-- How d is held in view: on ground, by pieces below it, by pieces hanging under it (above:
-- pieces whose studs it would cover from below), and along its axle line. The first piece
-- below that fails to hold it is kept for the refusal message.
local function holds(view,d)
  local h={below={},above={},line={}}
  for _,c in pairs(d.cells) do
    if c.bottom then
      local b=down(c.cell)
      if d.pos.y<0 or ground(view,b) then h.ground=true
      else
        local q=piece_at(view,b)
        if q and q~=d then
          local qc=q.cells[key(b)]
          if overlap(c.bottom,qc.top) then h.below[q]=true else h.blocked=h.blocked or q end
        end
      end
    end
    if c.top then
      local a=up(c.cell)
      local q=piece_at(view,a)
      if q and q~=d and overlap(c.top,q.cells[key(a)].bottom) then h.above[q]=true end
    end
  end
  -- Axle lines: an axle or gear joins axles, gears and technic bricks on its line, and the
  -- motor whose output it's in front of; a technic brick joins axles in its hole.
  if d.power=="axle" or d.power=="gear" or d.power=="brick" or d.power=="motor" then
    for _,s in ipairs({1,-1}) do
      local n=vector.add(d.pos,vector.multiply(d.axis,s))
      local q=piece_at(view,n)
      if q and q~=d and (q.power=="axle" or q.power=="gear" or q.power=="brick" or q.power=="motor") and
         parallel(d.axis,q.axis) then
        local motor_ok=true
        if d.power=="motor" then motor_ok=s==1 and q.power~="motor" and q.power~="brick" end
        if q.power=="motor" then motor_ok=vector.equals(vector.add(q.pos,q.axis),d.pos) and d.power~="brick" end
        -- Two technic bricks side by side aren't joined by their holes alone.
        if motor_ok and not (d.power=="brick" and q.power=="brick") then h.line[q]=true end
      end
    end
  end
  return h
end
local function any(t) return next(t)~=nil end

-- Whether d reaches the ground through pieces that click together (giving up, as if it did,
-- past `cap` pieces). Results are cached per view.
local CAP=2000
local function grounded(view,d)
  view.grounded=view.grounded or {}
  if view.grounded[d]~=nil then return view.grounded[d] end
  local seen,queue,n={[d]=true},{d},0
  local ok=false
  while #queue>0 do
    local p=table.remove(queue)
    n=n+1
    if n>CAP or view.grounded[p] then ok=true; break end
    local h=holds(view,p)
    if h.ground then ok=true; break end
    -- Joined both ways: a piece on top holds p up too when it is held elsewhere (a bridge).
    for _,set in ipairs({h.below,h.above,h.line}) do
      for q in pairs(set) do
        if not seen[q] then seen[q]=true; queue[#queue+1]=q end
      end
    end
  end
  -- Everything reached is one group of pieces: all on the ground or all loose.
  for q in pairs(seen) do view.grounded[q]=ok end
  return ok
end

local function on(pos) local w=world_at(pos); return w and w.strict and true or false end
M.on=on

-- Can d go in (view already holds everything else)? Returns ok, reason.
local function fits(view,d)
  local h=holds(view,d)
  local held_below=h.ground or any(h.below)
  if d.power=="axle" or d.power=="gear" then
    if any(h.line) then return true end
    return false,"An axle or gear needs a technic brick's hole, a motor or another axle on its line."
  end
  if held_below and any(h.above) then
    return false,"That gap grips from above and below: a real brick can't be pushed in. Build this piece first, then the one on top."
  end
  if held_below or any(h.above) or any(h.line) then return true end
  if h.blocked then
    local why=NO_TOP[h.blocked.shape]
    if why then return false,"Nothing clicks on there: "..why.."." end
    return false,"The studs below miss this piece. Move it so it covers a stud."
  end
  return false,"It has to click onto studs below or hang from a piece above. Touching at the side holds nothing."
end

-- Pieces next to any cell in cells (a set of keys), other than skip.
local function around(view,cells,skip)
  local out,seen={},{}
  for _,c in pairs(cells) do
    for _,d in ipairs({{x=0,y=1,z=0},{x=0,y=-1,z=0},{x=1,y=0,z=0},{x=-1,y=0,z=0},{x=0,y=0,z=1},{x=0,y=0,z=-1}}) do
      local q=piece_at(view,vector.add(c,d))
      if q and q~=skip and not seen[q] then seen[q]=true; out[#out+1]=q end
    end
  end
  return out
end
-- Pieces that hang on now but would be loose in `after` (both views of the same place).
local function loosened(before,after,cells,skip)
  for _,q in ipairs(around(after,cells,skip)) do
    local qb=piece_at(before,q.pos)
    if not grounded(after,q) and qb and grounded(before,qb) then return q end
  end
end
local LOOSE="Pieces would come loose. Take off what's held by this one first."

-- The checks place, collect, turn and undo run in a strict world. Each returns ok, reason.
-- A new piece node at pos (its primary cell).
function M.can_place(pos,node)
  if not on(pos) then return true end
  local d=M.describe(pos,node)
  if not d then return true end
  return fits(new_view(),d)
end
-- Taking away what's at pos: a piece, or the ground under one.
function M.can_remove(pos)
  if not on(pos) then return true end
  local before=new_view()
  local d=piece_at(before,pos)
  local cells={}
  if d then for k,c in pairs(d.cells) do cells[k]=c.cell end
  else cells[key(pos)]=vector.copy(pos) end
  local gone={}
  for k in pairs(cells) do gone[k]=true end
  if loosened(before,new_view(gone),cells,d) then return false,LOOSE end
  return true
end
-- The piece at pos becoming node (a quarter turn, an axle pointed another way).
function M.can_replace(pos,node)
  if not on(pos) then return true end
  local before=new_view()
  local old=piece_at(before,pos)
  local d=M.describe(old and old.pos or pos,node)
  if not (old and d) then return true end
  local gone,cells={},{}
  for k,c in pairs(old.cells) do gone[k]=true; cells[k]=c.cell end
  local after=new_view(gone)
  add_piece(after,d)
  local ok,why=fits(after,d)
  if not ok then return false,why end
  if loosened(before,after,cells,d) then return false,LOOSE end
  return true
end

-- Orders pieces {pos, node} (to be built where nothing is in `gone`) so each goes in held
-- by the ones before it, as a player in a strict world must build. Returns the order and
-- the pieces that never fit.
function M.order(items,gone)
  local view=new_view(gone)
  local left,order={},{}
  for i,it in ipairs(items) do left[i]=it end
  -- Passes over the list in its order: plans come sorted lowest first, so this builds up
  -- layer by layer, and a piece waiting for one later in the list goes in on the next pass.
  local progress=true
  while progress do
    progress=false
    for i,it in ipairs(left) do
      local d=it and M.describe(it.pos,it.node)
      if it and (not d or fits(view,d)) then
        if d then add_piece(view,d) end
        order[#order+1]=it; left[i]=false; progress=true
      end
    end
  end
  local stuck={}
  for _,it in ipairs(left) do if it then stuck[#stuck+1]=it end end
  return order,stuck
end

-- /checkbuild: pieces within r cells of pos that hang in the air (nothing joins them to the
-- ground), as a list of positions, and how many pieces were looked at.
function M.loose_near(pos,r)
  local view=new_view()
  local loose,count,seen={},0,{}
  local c=vector.round(pos)
  for y=math.max(c.y-r,-1),c.y+r do
    for z=c.z-r,c.z+r do
      for x=c.x-r,c.x+r do
        local d=piece_at(view,{x=x,y=y,z=z})
        if d and not seen[d] then
          seen[d]=true; count=count+1
          if not grounded(view,d) then loose[#loose+1]=d.pos end
        end
      end
    end
  end
  return loose,count
end
return M
end
