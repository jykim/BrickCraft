-- Models: builds of real LEGO parts made with BrickWright (validated there: no collisions,
-- nothing floating, all connected), standing in the world part by part.
--
-- Parts keep their real proportions: a cell is 16 mm every way, 2 x 2 studs across and five
-- plates tall (tools/import_brickwright.py writes them so; `cell_mm` in the data). Size 1 is
-- the game's grid: a real 2 x 2 brick is a game 2 x 2 brick across. A model goes down at
-- minifig scale (DEFAULT_SCALE: a minifig as tall as a player) unless a size is given
-- (/model bonsai 0.3), and its size can change from its menu, until it's first changed
-- itself: before a part comes off, it's broken, rebuilt or built on, the player is warned
-- and the model goes to minifig scale for good, the size every changed model and loose
-- part has, so parts taken off one go on another the same size. With the separator:
--   * left click takes one part off into the inventory: a part the game has (bricks,
--     plates, tiles, round bricks, slopes) becomes game bricks of the nearest colour, any
--     other a "LEGO part" item that can be put down again;
--   * right click opens the model's menu: turn it, break it all into the inventory, rebuild
--     it in game bricks, or put it away.
-- Game bricks go on a model's parts (right click a part holding bricks), and players stand
-- on it: invisible support nodes fill the cells its parts take, as high as the parts reach.
-- In a strict LEGO world a part can't come off while it holds others up (parts touch in a
-- graph from the import; the ones on the ground hold the rest), nor while a game brick
-- stands on it, and a model or part only goes down on studs.
--
-- A model is an instance in mod storage ({slug or part, foot, turn, parts gone, support
-- cells}); its parts are entities made while someone is near and not saved with the map
-- (a big model would pass the engine's objects-per-block limit).
-- Sent from BrickWright ("Send to BrickCraft"): <world>/brickwright_models/<slug>/ holds a
-- model's meshes and model.json; they're added as dynamic media without a restart.
local C=core
local S=brickcraft.strict
local MP=C.get_modpath("brickcraft_models")
local storage=brickcraft.storage
local NEAR=96 -- a model's parts are there while someone is this close
local GAME_RGB={coral={235,93,72},gold={249,193,65},mint={74,183,147},sky={74,161,217},
  violet={151,116,203},cream={238,229,199},navy={48,76,110},rose={229,131,165},
  green={88,171,65},brown={118,80,52},tan={196,160,110}}

-- Model definitions -----------------------------------------------------------------------
local models,catalog={},{} -- slug -> def; the defs in list order

-- Meshes in real proportions (`cell_mm`), by prefix; older ones (a cell a brick tall) stay
-- as they were, stretched, until they're sent again.
local real_prefix={}
local function prefix_of(mesh) return mesh and mesh:match("^(.*)_%d+%.glb$") end

local function def_from(data)
  local d={slug=data.slug,title=data.title or data.slug,record=data.record,pieces=data.pieces or #data.parts,
    w=data.w,h=data.h,d=data.d,prompt=data.prompt,bricks=data.bricks,parts={},adj={},ground={},
    preview=data.preview,preview_colors=data.preview_colors}
  local prefix=data.mesh_prefix or ("brickcraft_model_"..data.slug)
  real_prefix[prefix]=data.cell_mm==16 or nil
  for i,p in ipairs(data.parts) do
    d.parts[i]={mesh=prefix.."_"..p[1]..".glb",color=p[2],x=p[3],y=p[4],z=p[5],hx=p[6],hy=p[7],hz=p[8],
      part=p[9] or "?",cname=p[10] or ""}
    if p[11] then -- the same part standing as in its own file, for the inventory and parts stacks
      d.parts[i].umesh=prefix.."_"..p[11]..".glb"
      d.parts[i].uhx,d.parts[i].uhy,d.parts[i].uhz=p[12],p[13],p[14]
    end
  end
  for _,l in ipairs(data.links or {}) do
    local a,b=l[1],l[2]
    d.adj[a]=d.adj[a] or {}; d.adj[b]=d.adj[b] or {}
    table.insert(d.adj[a],b); table.insert(d.adj[b],a)
  end
  for _,i in ipairs(data.ground or {}) do d.ground[i]=true end
  return d
end

local function add_def(d)
  if not models[d.slug] then catalog[#catalog+1]=d end
  for i,o in ipairs(catalog) do if o.slug==d.slug then catalog[i]=d end end
  models[d.slug]=d
end

local function read_json(path)
  local f=io.open(path,"rb"); if not f then return end
  local text=f:read("*a"); f:close()
  return C.parse_json(text),text
end

do
  local files=C.get_dir_list(MP.."/data",false) or {}
  table.sort(files)
  -- The samples in a fixed order, then any others.
  local first={bonsai=1,house=2,cat=3,mech=4,train=5,car=6}
  table.sort(files,function(a,b)
    local ra,rb=first[a:gsub("%.json$","")] or 99,first[b:gsub("%.json$","")] or 99
    if ra~=rb then return ra<rb end
    return a<b
  end)
  for _,f in ipairs(files) do
    if f:match("%.json$") then
      local data=read_json(MP.."/data/"..f)
      if data then add_def(def_from(data)) end
    end
  end
end

-- A single part put down from the inventory is a model of one part.
local function single_def(p)
  return {title="LEGO part "..p.part,pieces=1,single=true,w=p.hx*2,d=p.hz*2,h=p.hy*2,
    parts={{mesh=p.mesh,color=p.color,x=0,y=p.hy,z=0,hx=p.hx,hy=p.hy,hz=p.hz,part=p.part,cname=p.cname}},
    adj={},ground={[1]=true}}
end

-- Instances ------------------------------------------------------------------------------
local state=C.deserialize(storage:get_string("model_instances")) or {}
state.next=state.next or 1
state.list=state.list or {}
-- A group of parts that fell off a model (strict worlds): its own model, parts placed as
-- in the model it came from (same turn and scale), links between them, the ones it landed on.
local function custom_def(c)
  local d={title=c.title,pieces=#c.parts,custom=true,parts={},adj={},ground={}}
  local lo,hi={x=1e9,y=1e9,z=1e9},{x=-1e9,y=-1e9,z=-1e9}
  for i,p in ipairs(c.parts) do
    d.parts[i]=p
    for _,a in ipairs({"x","y","z"}) do
      local h=p["h"..a]
      lo[a]=math.min(lo[a],p[a]-h); hi[a]=math.max(hi[a],p[a]+h)
    end
  end
  d.w,d.h,d.d=hi.x-lo.x,hi.y-lo.y,hi.z-lo.z
  for _,l in ipairs(c.links or {}) do
    local a,b=l[1],l[2]
    d.adj[a]=d.adj[a] or {}; d.adj[b]=d.adj[b] or {}
    table.insert(d.adj[a],b); table.insert(d.adj[b],a)
  end
  for _,i in ipairs(c.ground or {}) do d.ground[i]=true end
  return d
end

local by_id={}
for _,inst in ipairs(state.list) do inst._def=nil; by_id[inst.id]=inst end
local function save() storage:set_string("model_instances",C.serialize(state)) end

local made={} -- instance id -> the def of a one-part or fallen-group instance
local function def_of(inst)
  if inst.part or inst.custom then
    made[inst.id]=made[inst.id] or (inst.part and single_def(inst.part) or custom_def(inst.custom))
    return made[inst.id]
  end
  return models[inst.slug]
end

-- Quarter turns, the way set_yaw(turn * pi/2) turns a mesh.
local function rot(x,z,t)
  for _=1,t%4 do x,z=-z,x end
  return x,z
end
local MIN_SCALE,MAX_SCALE=.1,3
-- A real minifig is about 40 mm (2.5 cells) tall; a player is 1.75 cells.
local DEFAULT_SCALE=.7

-- Once, from parts a cell a brick tall (16 x 9.6 mm cells) to real proportions: parts put
-- down or fallen off keep their sizes in the instance, so those whose meshes are real now
-- come down to real heights; every model's support is redone when its parts next appear;
-- models nobody changed go to minifig scale, the default now.
if not state.real then
  local OLD_Y=9.6/16
  local function fix(p)
    if real_prefix[prefix_of(p.mesh)] then
      for _,f in ipairs({"y","hy","uhy"}) do if p[f] then p[f]=p[f]*OLD_Y end end
    end
  end
  for _,inst in ipairs(state.list) do
    if inst.part then fix(inst.part) end
    if inst.custom then for _,q in ipairs(inst.custom.parts) do fix(q) end end
    if inst.slug and not inst.modified and (inst.scale or 1)==1 then inst.scale=DEFAULT_SCALE end
    inst.resupport=true
  end
  state.real=true
  save()
end
local function part_box(inst,p)
  local s=inst.scale or 1
  local x,z=rot(p.x*s,p.z*s,inst.turn or 0)
  local hx,hz=p.hx*s,p.hz*s
  if (inst.turn or 0)%2==1 then hx,hz=hz,hx end
  return {x=inst.x+x,y=inst.y+p.y*s,z=inst.z+z},hx,p.hy*s,hz
end
local function key(x,y,z) return x..","..y..","..z end
local function unkey(k) local x,y,z=k:match("^(-?%d+),(-?%d+),(-?%d+)$"); return {x=tonumber(x),y=tonumber(y),z=tonumber(z)} end

-- Support: every cell whose middle a part's box covers (or the nearest, for a thin part),
-- as high as the part reaches in it.
local function support_cells(inst,gone)
  local def=def_of(inst)
  local cells={}
  if not def then return cells end
  for i,p in ipairs(def.parts) do
    if not gone[i] then
      local c,hx,hy,hz=part_box(inst,p)
      local x0,x1=math.ceil(c.x-hx-1e-6),math.floor(c.x+hx+1e-6)
      local z0,z1=math.ceil(c.z-hz-1e-6),math.floor(c.z+hz+1e-6)
      if x0>x1 then x0=math.floor(c.x+.5); x1=x0 end
      if z0>z1 then z0=math.floor(c.z+.5); z1=z0 end
      local top=c.y+hy
      for cy=math.floor(c.y-hy+.5+1e-6),math.floor(top+.5-1e-6) do
        local level=math.min(1,top-(cy-.5))
        if level>.02 then
          for cx=x0,x1 do for cz=z0,z1 do
            local k=key(cx,cy,cz)
            cells[k]=math.max(cells[k] or 0,level)
          end end
        end
      end
    end
  end
  return cells
end

local SUPPORT="brickcraft:model_support"
local function apply_support(inst,cells)
  local now={}
  for k,level in pairs(cells) do
    local pos=unkey(k)
    local name=C.get_node(pos).name
    if name=="air" or name==SUPPORT then
      C.set_node(pos,{name=SUPPORT,param2=math.max(1,math.min(64,math.floor(level*64+.5)))})
      now[k]=true
    end
  end
  for k in pairs(inst.support or {}) do
    if not now[k] then
      local pos=unkey(k)
      if C.get_node(pos).name==SUPPORT then C.remove_node(pos) end
    end
  end
  inst.support=now
end

-- Strict: a game piece standing on support that would go (cells not in `cells`).
local function bricks_on(inst,cells)
  for k in pairs(inst.support or {}) do
    if not cells[k] then
      local pos=unkey(k); pos.y=pos.y+1
      local above=C.get_node(pos)
      if above.name~=SUPPORT and S.describe(pos,above) then return pos end
    end
  end
end

-- Parts (not gone) no ground part holds up through touching parts: how many, and which.
local function hanging(def,gone)
  local seen,queue={},{}
  for i in pairs(def.ground) do if not gone[i] then seen[i]=true; queue[#queue+1]=i end end
  while #queue>0 do
    local i=table.remove(queue)
    for _,j in ipairs(def.adj[i] or {}) do
      if not gone[j] and not seen[j] then seen[j]=true; queue[#queue+1]=j end
    end
  end
  local n,set=0,{}
  for i=1,#def.parts do if not gone[i] and not seen[i] then n=n+1; set[i]=true end end
  return n,set
end

-- Part entities ----------------------------------------------------------------------------
local spawned={} -- instance id -> {part index -> ObjectRef}

local function spawn_part(inst,i,p)
  local c,hx,hy,hz=part_box(inst,p)
  local obj=C.add_entity(c,"brickcraft:model_part")
  if not obj then return end
  local e=obj:get_luaentity()
  e._inst,e._i=inst.id,i
  local def=def_of(inst)
  local s=inst.scale or 1
  obj:set_properties({mesh=p.mesh,textures={"[fill:1x1:"..p.color},visual_size={x=s,y=s,z=s},
    use_texture_alpha=p.color:sub(8,9)~="ff",selectionbox={-hx,-hy,-hz,hx,hy,hz},
    infotext=(def.single and "" or def.title.."\n").."LEGO part "..p.part..(p.cname~="" and " ("..p.cname..")" or "")})
  obj:set_yaw((inst.turn or 0)*math.pi/2)
  spawned[inst.id][i]=obj
end

local hold={} -- instance id -> until when its parts wait (they're still falling)
local function resupport(inst)
  local cells=support_cells(inst,inst.gone or {})
  local lo,hi
  for _,t in ipairs({cells,inst.support or {}}) do
    for k in pairs(t) do
      local q=unkey(k)
      lo=lo and {x=math.min(lo.x,q.x),y=math.min(lo.y,q.y),z=math.min(lo.z,q.z)} or q
      hi=hi and {x=math.max(hi.x,q.x),y=math.max(hi.y,q.y),z=math.max(hi.z,q.z)} or q
    end
  end
  if lo then C.load_area(lo,hi) end
  apply_support(inst,cells)
  inst.resupport=nil
  save()
end
local function spawn(inst)
  local def=def_of(inst)
  if not def or spawned[inst.id] then return end
  if hold[inst.id] and C.get_us_time()<hold[inst.id] then return end
  if inst.resupport then resupport(inst) end
  spawned[inst.id]={}
  for i,p in ipairs(def.parts) do
    if not (inst.gone or {})[i] then spawn_part(inst,i,p) end
  end
end
local function despawn(inst)
  for _,obj in pairs(spawned[inst.id] or {}) do if obj:get_pos() then obj:remove() end end
  spawned[inst.id]=nil
end
local function respawn(inst) despawn(inst); spawn(inst) end

local function new_instance(fields)
  fields.id=state.next; state.next=state.next+1
  fields.gone=fields.gone or {}
  fields.turn=fields.turn or 0
  state.list[#state.list+1]=fields; by_id[fields.id]=fields
  apply_support(fields,support_cells(fields,fields.gone))
  save()
  return fields
end
local function drop_instance(inst)
  despawn(inst)
  apply_support(inst,{})
  by_id[inst.id]=nil; made[inst.id]=nil
  for i,o in ipairs(state.list) do if o==inst then table.remove(state.list,i); break end end
  save()
end

-- Gravity (strict LEGO worlds) --------------------------------------------------------------
-- What a part loses its hold on falls straight down as one group, each group of parts still
-- joined to one another, until a part lands on something: a node, a model's support, or
-- another model's part. A fallen group is a model of its own (custom), joined at the parts
-- it landed on, so taking those off drops it again. A model whose parts all lose what was
-- under them falls the same way.
local EPS,G=.02,20
local function box_of(inst,p)
  local c,hx,hy,hz=part_box(inst,p)
  return {x0=c.x-hx,x1=c.x+hx,z0=c.z-hz,z1=c.z+hz,yb=c.y-hy,top=c.y+hy}
end
-- The top of what a node holds up, or nil (air, or not solid).
local function node_top(pos,node)
  if node.name=="air" then return end
  if node.name=="ignore" then return pos.y+.5 end -- not loaded: don't fall into it
  if node.name==SUPPORT then return pos.y-.5+node.param2/64 end
  local def=C.registered_nodes[node.name]
  if not def or not def.walkable then return end
  local cb=def.collision_box or (def.drawtype=="nodebox" and def.node_box)
  if cb and cb.type=="fixed" and cb.fixed then
    local boxes=type(cb.fixed[1])=="table" and cb.fixed or {cb.fixed}
    local top=-.5
    for _,b in ipairs(boxes) do top=math.max(top,b[5]) end
    return pos.y+top
  end
  return pos.y+.5
end
-- The highest thing under box b: nodes (but not the cells in skip) and the boxes in others.
local function floor_under(b,skip,others)
  local best=-2.5
  local x0,x1=math.floor(b.x0+.5+EPS),math.floor(b.x1+.5-EPS)
  local z0,z1=math.floor(b.z0+.5+EPS),math.floor(b.z1+.5-EPS)
  if x0>x1 then x0=math.floor((b.x0+b.x1)/2+.5); x1=x0 end
  if z0>z1 then z0=math.floor((b.z0+b.z1)/2+.5); z1=z0 end
  for cx=x0,x1 do for cz=z0,z1 do
    for cy=math.floor(b.yb+.5-EPS),-3,-1 do
      if not skip[key(cx,cy,cz)] then
        local pos={x=cx,y=cy,z=cz}
        local top=node_top(pos,C.get_node(pos))
        if top then best=math.max(best,math.min(top,b.yb)); break end
      end
    end
  end end
  for _,o in ipairs(others) do
    if o.x0<b.x1-EPS and o.x1>b.x0+EPS and o.z0<b.z1-EPS and o.z1>b.z0+EPS and o.top<=b.yb+EPS then
      best=math.max(best,o.top)
    end
  end
  return best
end
-- Boxes of every part near (x, z) but those of `but` (an instance, left out whole).
local function boxes_near(x,z,but)
  local out={}
  for _,o in ipairs(state.list) do
    if o~=but and math.abs(o.x-x)<64 and math.abs(o.z-z)<64 then
      local d=def_of(o)
      if d then for i,p in ipairs(d.parts) do if not o.gone[i] then out[#out+1]=box_of(o,p) end end end
    end
  end
  return out
end

-- Parts already on screen drop with gravity and go when they land; the instance that
-- takes them waits as long, then shows its own.
local function drop_entities(objs,d)
  local t=math.sqrt(2*math.max(d,0)/G)
  for _,obj in ipairs(objs) do
    if obj:get_pos() then
      if t>.05 then obj:set_acceleration({x=0,y=-G,z=0}) end
      C.after(t,function() if obj:get_pos() then obj:remove() end end)
    end
  end
  return t
end

-- Parts `set` of inst (taken out of it already: gone, support updated) fall in groups.
local function drop_groups(inst,def,set,objs)
  local groups,seen={},{}
  for i in pairs(set) do
    if not seen[i] then
      local g,queue={},{i}; seen[i]=true
      while #queue>0 do
        local a=table.remove(queue); g[#g+1]=a
        for _,b in ipairs(def.adj[a] or {}) do if set[b] and not seen[b] then seen[b]=true; queue[#queue+1]=b end end
      end
      local low=1e9
      for _,a in ipairs(g) do low=math.min(low,box_of(inst,def.parts[a]).yb) end
      groups[#groups+1]={parts=g,low=low}
    end
  end
  table.sort(groups,function(a,b) return a.low<b.low end) -- the lowest land first
  local made_now={}
  for _,g in ipairs(groups) do
    local others=boxes_near(inst.x,inst.z,nil)
    local d,floors=1e9,{}
    for _,a in ipairs(g.parts) do
      local b=box_of(inst,def.parts[a])
      floors[a]=floor_under(b,{},others)
      d=math.min(d,b.yb-floors[a])
    end
    d=math.max(0,d)
    local parts,index,links,ground={},{},{},{}
    for n,a in ipairs(g.parts) do
      local p=def.parts[a]
      parts[n]=table.copy(p)
      index[a]=n
      if box_of(inst,p).yb-d-floors[a]<EPS*2 then ground[#ground+1]=n end
    end
    for _,a in ipairs(g.parts) do
      for _,b in ipairs(def.adj[a] or {}) do if index[b] and a<b then links[#links+1]={index[a],index[b]} end end
    end
    local title=(def.custom and def.title) or ("Part of "..(def.title or "a model"))
    local frag=new_instance({custom={title=title,parts=parts,links=links,ground=ground},
      x=inst.x,y=inst.y-d,z=inst.z,turn=inst.turn,scale=inst.scale,modified=true})
    local mine={}
    for _,a in ipairs(g.parts) do if objs[a] then mine[#mine+1]=objs[a] end end
    hold[frag.id]=C.get_us_time()+drop_entities(mine,d)*1e6
    made_now[#made_now+1]=frag
  end
  return made_now
end

-- Models near (x, z) whose parts all lost what was under them fall, until none does.
local function settle(x,z)
  for _=1,8 do
    local moved=false
    for _,inst in ipairs(state.list) do
      if math.abs(inst.x-x)<48 and math.abs(inst.z-z)<48 and S.on(inst) then
        local def=def_of(inst)
        if def then
          local others=boxes_near(inst.x,inst.z,inst)
          local idx={}
          for i in ipairs(def.parts) do if not inst.gone[i] then idx[#idx+1]=box_of(inst,def.parts[i]) end end
          table.sort(idx,function(a,b) return a.yb<b.yb end)
          local d=1e9
          for _,b in ipairs(idx) do
            d=math.min(d,b.yb-floor_under(b,inst.support or {},others))
            if d<EPS then break end
          end
          if #idx>0 and d>=EPS then
            local objs={}
            for _,obj in pairs(spawned[inst.id] or {}) do objs[#objs+1]=obj end
            spawned[inst.id]=nil
            inst.y=inst.y-d
            apply_support(inst,support_cells(inst,inst.gone))
            hold[inst.id]=C.get_us_time()+drop_entities(objs,d)*1e6
            moved=true
          end
        end
      end
    end
    if not moved then break end
    save()
  end
end

-- Media on demand ---------------------------------------------------------------------------
-- A model's meshes and part pictures aren't in the media every player gets on joining (they
-- would make joining slow). Each player gets a model's files when they first come near it,
-- one dynamic media file at a time, kept in their client's cache for next time.
local files={} -- file name -> path, for every model file the game has
for _,f in ipairs(C.get_dir_list(MP.."/parts",false) or {}) do files[f]=MP.."/parts/"..f end
local sent={} -- player name -> {file name -> true (there) | false (on its way)}
local function files_of(def)
  if def._files then return def._files end
  local list,seen={},{}
  for _,p in ipairs(def.parts) do
    for _,m in ipairs({p.mesh,p.umesh}) do
      if m and not seen[m] then
        seen[m]=true; list[#list+1]=m
        local png=m:gsub("%.glb$",".png")
        if files[png] then list[#list+1]=png end
      end
    end
  end
  def._files=list
  return list
end
-- Whether the player has every file in list; asks for the missing ones.
local function has_media(name,list)
  local have=sent[name]
  if not have then have={}; sent[name]=have end
  local all=true
  for _,f in ipairs(list) do
    if have[f]~=true then
      all=false
      if have[f]==nil and files[f] then
        have[f]=false
        local ok=C.dynamic_add_media({filename=f,filepath=files[f],to_player=name,ephemeral=false},function(who)
          if sent[who] then sent[who][f]=true end
        end)
        if not ok then have[f]=nil end
      end
    end
  end
  return all
end
C.register_on_leaveplayer(function(player) sent[player:get_player_name()]=nil end)

local shown={} -- instance id -> players who had its files when its parts were made
local timer=0
C.register_globalstep(function(dtime)
  timer=timer+dtime
  if timer<1 then return end
  timer=0
  local players=C.get_connected_players()
  for _,inst in ipairs(state.list) do
    local def=def_of(inst)
    local near,ready={},{}
    for _,pl in ipairs(players) do
      local p=pl:get_pos()
      if math.abs(p.x-inst.x)<NEAR and math.abs(p.z-inst.z)<NEAR then
        local name=pl:get_player_name()
        near[#near+1]=name
        if def and has_media(name,files_of(def)) then ready[name]=true end
      end
    end
    if #near>0 and next(ready) then
      local parts=spawned[inst.id]
      local late=false -- someone got the files after the parts were made: make them again
      for name in pairs(ready) do if parts and not (shown[inst.id] or {})[name] then late=true end end
      if late then respawn(inst); parts=spawned[inst.id]; shown[inst.id]=ready
      elseif parts then -- an entity can go with its mapblock; put it back
        for i,obj in pairs(parts) do if not obj:get_pos() then spawn_part(inst,i,def.parts[i]) end end
      else spawn(inst); if spawned[inst.id] then shown[inst.id]=ready end end
    elseif #near==0 and spawned[inst.id] then despawn(inst); shown[inst.id]=nil end
  end
end)

-- Inventory: the game's own piece where there is one, else a LEGO part item.
local real_shapes={}
for _,s in ipairs(brickcraft.shape_list) do
  if s.part and not s.invented and not s.train and not s.technic then real_shapes[s.part]=s end
end
local function nearest_color(hex)
  local r,g,b=tonumber(hex:sub(2,3),16),tonumber(hex:sub(4,5),16),tonumber(hex:sub(6,7),16)
  local best,bd
  for name,c in pairs(GAME_RGB) do
    local d=(c[1]-r)^2+(c[2]-g)^2+(c[3]-b)^2
    if not bd or d<bd then best,bd=name,d end
  end
  return best
end
local function item_for(p)
  local s=real_shapes[p.part:match("^%d+") or ""]
  if s then return ItemStack(brickcraft.piece_item(nearest_color(p.color),s)),s end
  local stack=ItemStack("brickcraft:real_part")
  local meta=stack:get_meta()
  -- Standing as in its own file, when the import has that: put down, it stands upright.
  local up=p.umesh and {mesh=p.umesh,hx=p.uhx,hy=p.uhy,hz=p.uhz} or p
  meta:set_string("mesh",up.mesh)
  for _,f in ipairs({"color","part","cname"}) do meta:set_string(f,p[f]) end
  for _,f in ipairs({"hx","hy","hz"}) do meta:set_float(f,up[f]) end
  meta:set_int("real",1)
  -- Its own picture (rendered at import, light grey) in its colour.
  local icon=up.mesh:gsub("%.glb$",".png").."^[multiply:"..p.color:sub(1,7)
  meta:set_string("inventory_image",icon)
  meta:set_string("wield_image",icon)
  meta:set_string("bc_color",p.color)
  meta:set_string("description","LEGO part "..p.part..(p.cname~="" and " ("..p.cname..")" or "").."\nPut it down with a right click")
  return stack
end

local function say(player,msg) C.chat_send_player(player:get_player_name(),msg) end

-- Takes part i off inst into player's inventory. Returns true when it did.
local function take_part(player,inst,i,quiet,all)
  local def=def_of(inst)
  local p=def and def.parts[i]
  if not p or inst.gone[i] then return false end
  local gone=table.copy(inst.gone); gone[i]=true
  local strict=S.on(inst)
  -- Strict: what this part held up (and nothing else does) falls.
  local falling={}
  if strict and not all then
    local _,before=hanging(def,inst.gone)
    local _,after=hanging(def,gone)
    for j in pairs(after) do if not before[j] then falling[j]=true; gone[j]=true end end
  end
  local cells=support_cells(inst,gone)
  if strict and not all and bricks_on(inst,cells) then
    if not quiet then say(player,"Strict LEGO: a brick stands on that part. Take it off first.") end
    return false
  end
  local stack=item_for(p)
  if not brickcraft.room_for(player,stack) then
    if not quiet then say(player,"No room in your inventory for that part.") end
    return false
  end
  brickcraft.give(player,stack)
  inst.gone=gone
  local obj=spawned[inst.id] and spawned[inst.id][i]
  if obj then obj:remove(); spawned[inst.id][i]=nil end
  local objs={}
  for j in pairs(falling) do
    local o=spawned[inst.id] and spawned[inst.id][j]
    if o then objs[j]=o; spawned[inst.id][j]=nil end
  end
  apply_support(inst,cells)
  local left=0
  for j=1,#def.parts do if not gone[j] then left=left+1 end end
  if left==0 then drop_instance(inst) else save() end
  local x,z=inst.x,inst.z
  if next(falling) then
    local n=0; for _ in pairs(falling) do n=n+1 end
    drop_groups(inst,def,falling,objs)
    if not quiet then say(player,n.." part"..(n>1 and "s" or "").." it held up fell.") end
  end
  if strict and not all then settle(x,z) end
  return true
end

-- Every part, top first, while the inventory has room (all of them come off, so none is
-- left hanging; bricks on the model were checked first).
local organize -- (below) sorts what doesn't fit into the inventory into stacks
-- Breaking a model needs no warning or resize: it goes away, and parts in the inventory are
-- the game's size whatever size the model was.
local function break_all(player,inst)
  local def=def_of(inst)
  if S.on(inst) and bricks_on(inst,{}) then
    return say(player,"Strict LEGO: game bricks stand on this model. Take them off first.")
  end
  local idx={}
  for i in ipairs(def.parts) do if not inst.gone[i] then idx[#idx+1]=i end end
  table.sort(idx,function(a,b) return def.parts[a].y+def.parts[a].hy>def.parts[b].y+def.parts[b].hy end)
  local n,left=0,0
  for _,i in ipairs(idx) do
    if not by_id[inst.id] then break end
    local stack=item_for(def.parts[i])
    if brickcraft.room_for(player,stack) then
      if take_part(player,inst,i,true,true) then n=n+1 end
    else left=left+1 end
  end
  local msg="Took "..n.." real part"..(n==1 and "" or "s").." into your inventory."
  if left>0 and by_id[inst.id] then
    local stacks=organize(player,inst,true)
    msg=msg.." It's full, so the other "..left.." are sorted into stacks here"..(stacks and "" or "").."."
  end
  say(player,msg)
end

local function turn_model(player,inst)
  local old=inst.turn
  inst.turn=(inst.turn+1)%4
  local cells=support_cells(inst,inst.gone)
  if S.on(inst) and bricks_on(inst,cells) then
    inst.turn=old
    return say(player,"Strict LEGO: game bricks stand on this model. Take them off first.")
  end
  apply_support(inst,cells); save(); respawn(inst)
end

local function put_away(player,inst)
  if S.on(inst) and bricks_on(inst,{}) then
    return say(player,"Strict LEGO: game bricks stand on this model. Take them off first.")
  end
  local def=def_of(inst)
  drop_instance(inst)
  say(player,"Put away "..(def and def.title or "the model")..". /model brings it back.")
end

-- The same build in game bricks (2 x 2 bricks, one per cell, the nearest colours), in the
-- cells the model took. Strict worlds leave out bricks nothing could hold.
local function convert(player,inst)
  local def=def_of(inst)
  if not def or not def.bricks then return say(player,"This one has no game-brick version.") end
  local base={x=inst.x,y=math.floor(inst.y+.5),z=inst.z}
  despawn(inst); apply_support(inst,{})
  -- The bricks are cells at size 1: at another size each goes to the cell its middle lands
  -- in, and a cell takes the colour most bricks bring it.
  local s=inst.scale or 1
  local votes,cells={},{}
  for _,b in ipairs(def.bricks) do
    local x,z=rot(b[1]*s,b[3]*s,inst.turn)
    local pos={x=math.floor(base.x+x+.5),y=base.y+math.floor((b[2]+.5)*s),z=math.floor(base.z+z+.5)}
    local k=key(pos.x,pos.y,pos.z)
    if not votes[k] then votes[k]={}; cells[#cells+1]={k=k,pos=pos} end
    votes[k][b[4]]=(votes[k][b[4]] or 0)+1
  end
  local items={}
  for _,c in ipairs(cells) do
    local best,bn
    for color,n in pairs(votes[c.k]) do if not bn or n>bn or (n==bn and color<best) then best,bn=color,n end end
    if C.get_node(c.pos).name=="air" then items[#items+1]={pos=c.pos,node={name="brickcraft:"..best,param2=0}} end
  end
  table.sort(items,function(a,b) return a.pos.y<b.pos.y end)
  local order,stuck=items,{}
  if S.on(inst) then order,stuck=S.order(items) end
  for _,it in ipairs(order) do C.set_node(it.pos,it.node) end
  by_id[inst.id]=nil
  for i,o in ipairs(state.list) do if o==inst then table.remove(state.list,i); break end end
  save()
  say(player,"Rebuilt "..def.title.." in "..#order.." game bricks"..
    (#stuck>0 and " ("..#stuck.." left out: nothing real could hold them)" or "")..".")
  return #order,#stuck
end

-- Its parts sorted into neat stacks where it stood, like a parts list: one kind of part
-- in one colour a stack (up to 8 high, standing upright), the biggest first, in rows.
-- The stacks are a model of their own (custom), each stack joined from the bottom up.
local STACK=8
function organize(player,inst,quiet)
  local def=def_of(inst)
  if S.on(inst) and bricks_on(inst,{}) then
    return say(player,"Strict LEGO: game bricks stand on this model. Take them off first.")
  end
  local kinds,order={},{}
  for i,p in ipairs(def.parts) do
    if not inst.gone[i] then
      local k=p.part.."|"..p.color
      if not kinds[k] then
        local up=p.umesh and {mesh=p.umesh,hx=p.uhx,hy=p.uhy,hz=p.uhz} or {mesh=p.mesh,hx=p.hx,hy=p.hy,hz=p.hz}
        kinds[k]={up=up,p=p,n=0}; order[#order+1]=k
      end
      kinds[k].n=kinds[k].n+1
    end
  end
  table.sort(order,function(a,b)
    local A,B=kinds[a],kinds[b]
    local fa,fb=A.up.hx*A.up.hz,B.up.hx*B.up.hz
    if math.abs(fa-fb)>1e-3 then return fa>fb end
    if A.p.part~=B.p.part then return A.p.part<B.p.part end
    return A.p.color<B.p.color
  end)
  local width=math.max(8,math.min(24,math.ceil(math.sqrt(#order)*2.2)))
  local parts,links,ground={},{},{}
  local x,z,row=0,0,0
  local placed={}
  for _,k in ipairs(order) do
    local kind=kinds[k]
    local up=kind.up
    local w,dz=up.hx*2,up.hz*2
    local left=kind.n
    while left>0 do
      if x>0 and x+w>width then x=0; z=z+row+.5; row=0 end
      local high=math.min(STACK,left)
      -- Bricks nest on the studs below; thin or odd parts just sit on one another.
      local pitch=up.hy*2>.5 and up.hy*2-.11 or up.hy*2 -- a stud is 1.7 mm
      for n=1,high do
        parts[#parts+1]={mesh=up.mesh,umesh=up.mesh,color=kind.p.color,part=kind.p.part,cname=kind.p.cname,
          x=x+w/2,y=up.hy+(n-1)*pitch,z=z+dz/2,hx=up.hx,hy=up.hy,hz=up.hz,uhx=up.hx,uhy=up.hy,uhz=up.hz}
        if n==1 then ground[#ground+1]=#parts else links[#links+1]={#parts-1,#parts} end
      end
      placed[#placed+1]=true
      x=x+w+.25; row=math.max(row,dz); left=left-high
    end
  end
  -- Centred on where the model stood, facing the same way as the model did not matter: no turn.
  local wx,wz=0,z+row
  for _,p in ipairs(parts) do wx=math.max(wx,p.x+p.hx) end
  for _,p in ipairs(parts) do p.x=p.x-wx/2; p.z=p.z-wz/2 end
  local foot={x=inst.x,y=inst.y,z=inst.z}
  local title=(def.custom and def.title or def.title or "a model")
  drop_instance(inst)
  local stacks=new_instance({custom={title="Parts of "..title:gsub("^Parts of ",""),parts=parts,links=links,ground=ground},
    x=foot.x,y=foot.y,z=foot.z,turn=0,scale=DEFAULT_SCALE,modified=true})
  spawn(stacks)
  if not quiet then say(player,"Sorted "..#parts.." parts into "..#placed.." stacks.") end
  return stacks
end

-- Where a player points on an object: the point and the face's normal.
local function hit_on(player,obj)
  local eye=vector.offset(player:get_pos(),0,player:get_properties().eye_height or 1.5,0)
  local to=vector.add(eye,vector.multiply(player:get_look_dir(),10))
  for pt in C.raycast(eye,to,true,false) do
    if pt.type=="object" and pt.ref==obj then return pt.intersection_point,pt.intersection_normal end
  end
end

local function yaw_turn(player)
  local d=player:get_look_dir()
  local yaw=math.atan2(d.x,-d.z) -- 0 looking toward +z... facing back at the player:
  return (math.floor(yaw/(math.pi/2)+.5)+2)%4
end

-- In a strict LEGO world: the cell under a model's middle must offer studs on top.
local function on_studs(below)
  local node=C.get_node(below)
  if node.name==SUPPORT then return true end
  local d=S.describe(below,node)
  if not d then return true end -- the ground, the baseplate: studs all over
  for _,c in pairs(d.cells) do
    if c.top and vector.equals(c.cell,below) then return true end
  end
  return false
end

-- A LEGO part item put down with its foot at `foot`.
local function put_part(player,stack,foot)
  local meta=stack:get_meta()
  local p={mesh=meta:get_string("mesh"),color=meta:get_string("bc_color"),part=meta:get_string("part"),
    cname=meta:get_string("cname"),hx=meta:get_float("hx"),hy=meta:get_float("hy"),hz=meta:get_float("hz")}
  if p.mesh=="" then return stack end
  -- Taken before real proportions (a cell a brick tall), its mesh real now: its real height.
  if meta:get_int("real")==0 and real_prefix[prefix_of(p.mesh)] then p.hy=p.hy*9.6/16 end
  new_instance({part=p,x=foot.x,y=foot.y,z=foot.z,turn=yaw_turn(player),scale=DEFAULT_SCALE,modified=true})
  stack:take_item(1)
  return stack
end

-- One scale before a model changes ------------------------------------------------------
-- The first change to a model (a part off, broken, rebuilt, built on) asks first: it goes
-- to minifig scale and keeps it, the size of every changed model and loose part.
local pending={} -- player name -> {id, action}
local function unify(player,inst)
  if (inst.scale or 1)~=DEFAULT_SCALE then
    local old=inst.scale
    inst.scale=DEFAULT_SCALE
    local cells=support_cells(inst,inst.gone)
    if S.on(inst) and bricks_on(inst,cells) then
      inst.scale=old
      say(player,"Strict LEGO: game bricks stand on this model. Take them off first.")
      return false
    end
    apply_support(inst,cells); respawn(inst)
  end
  inst.modified=true; save()
  return true
end
local function before_change(player,inst,action)
  if inst.modified then return action() end
  local def=def_of(inst)
  local name=player:get_player_name()
  pending[name]={id=inst.id,action=action}
  local s=inst.scale or 1
  local same=s==DEFAULT_SCALE
  local text=same and ("Changing "..def.title.." keeps it at minifig scale (size "..DEFAULT_SCALE.."), the size of every changed model and loose part. After this its size can't change.")
    or (def.title.." is at size "..s..". Changing it first resizes it to minifig scale (size "..DEFAULT_SCALE..", "..
      string.format("%.0f",def.h*DEFAULT_SCALE).." cells tall), the size of every changed model and loose part. After this its size can't change.")
  C.show_formspec(name,"brickcraft_models:unify","formspec_version[4]size[8,4.4]"..
    "textarea[.4,.4;7.2,2.4;;;"..C.formspec_escape(text).."]"..
    "button_exit[.4,3.2;3.4,.8;yes;"..(same and "Go on" or "Resize and go on").."]"..
    "button_exit[4.2,3.2;3.4,.8;no;Cancel]")
end
C.register_on_player_receive_fields(function(player,formname,fields)
  if formname~="brickcraft_models:unify" then return end
  local name=player:get_player_name()
  local p=pending[name]; pending[name]=nil
  local inst=p and by_id[p.id]
  if fields.yes and inst and unify(player,inst) then p.action() end
  return true
end)

local function resize(player,inst,scale)
  if inst.modified then return say(player,"This model has been changed, so it stays at its size.") end
  local old=inst.scale or 1
  inst.scale=scale
  local cells=support_cells(inst,inst.gone)
  if S.on(inst) and bricks_on(inst,cells) then
    inst.scale=old
    return say(player,"Strict LEGO: game bricks stand on this model. Take them off first.")
  end
  apply_support(inst,cells); save(); respawn(inst)
  say(player,string.format("%s is size %s now (%.0f cells tall).",def_of(inst).title,scale,def_of(inst).h*scale))
end

-- The menu ---------------------------------------------------------------------------------
local menu={} -- player name -> {inst id, part index}
local function show_menu(player,inst,i)
  local def=def_of(inst)
  local name=player:get_player_name()
  menu[name]={id=inst.id,i=i}
  local p=def.parts[i]
  local left=0
  for j=1,#def.parts do if not inst.gone[j] then left=left+1 end end
  local size=inst.modified and "label[.4,6.0;Size "..(inst.scale or 1).." (fixed: it has been changed)]"
    or ("field[.4,5.7;2,.7;size;Size;"..(inst.scale or 1).."]button[2.6,5.7;4.4,.7;resize;Change size ("..DEFAULT_SCALE.." = minifig)]")
  local fs="formspec_version[4]size[7.4,8.4]"..size..
    "label[.4,.6;"..C.formspec_escape(def.title).."]"..
    "label[.4,1.1;"..C.formspec_escape(left.." of "..#def.parts.." real parts on it. This one: "..p.part..
      (p.cname~="" and " ("..p.cname..")" or "")).."]"..
    "button[.4,1.6;3.2,.8;stack;Break into stacks here]"..
    "button[3.8,1.6;3.2,.8;break;Break into my inventory]"..
    "button[.4,2.5;3.2,.8;take;Take this part]"..
    (def.bricks and "button[3.8,2.5;3.2,.8;convert;Rebuild in game bricks]" or "")..
    "button[.4,3.4;3.2,.8;turn;Turn it a quarter]"..
    "button[3.8,3.4;3.2,.8;away;Put it away]"..
    "tooltip[stack;Its parts, sorted into upright stacks of one kind and colour, where it stood]"..
    "tooltip[break;Its parts into your inventory, and what doesn't fit sorted into stacks here]"..
    "tooltip[away;Gone, parts and all (/model brings it back)]"..
    "button_exit[.4,7.2;6.6,.8;close;Close]"
  C.show_formspec(name,"brickcraft_models:menu",fs)
end
C.register_on_player_receive_fields(function(player,formname,fields)
  if formname~="brickcraft_models:menu" then return end
  local ctx=menu[player:get_player_name()]
  local inst=ctx and by_id[ctx.id]
  if not inst then return true end
  local close=true
  if fields.take then before_change(player,inst,function() take_part(player,inst,ctx.i) end)
  elseif fields["break"] then break_all(player,inst)
  elseif fields.convert then before_change(player,inst,function() convert(player,inst) end)
  elseif fields.stack then organize(player,inst) -- it goes away: no warning, no resize
  elseif fields.turn then turn_model(player,inst); close=false
  elseif fields.away then put_away(player,inst)
  elseif fields.resize or fields.key_enter_field=="size" then
    local s=tonumber(((fields.size or ""):gsub(",",".")))
    if not s or s<MIN_SCALE or s>MAX_SCALE then say(player,"Size is a number from "..MIN_SCALE.." to "..MAX_SCALE.." (1 = game bricks).")
    else resize(player,inst,s) end
  else close=false end
  if close and not pending[player:get_player_name()] then C.close_formspec(player:get_player_name(),"brickcraft_models:menu") end
  return true
end)

-- Right click on a part with a game brick: the brick goes in the cell against the face
-- pointed at, above any support there.
local function brick_on_part(player,obj,stack)
  local at,normal=hit_on(player,obj)
  if not at then return end
  local target=vector.round(vector.add(at,vector.multiply(normal,.5)))
  for _=1,4 do
    if C.get_node(target).name~=SUPPORT then break end
    target.y=target.y+1
  end
  local place=stack:get_definition().on_place
  local after=place(stack,player,{type="node",under=target,above=target})
  player:set_wielded_item(after or stack)
end

-- A LEGO part on top of a part: its foot where the top was pointed at, on the stud grid.
local function part_on_part(player,obj,stack)
  local at,normal=hit_on(player,obj)
  if not at or normal.y<.5 then return say(player,"Put a part on top of another part.") end
  -- Studs every half cell at size 1, from the model's foot (parts go down at minifig scale).
  local e=obj:get_luaentity()
  local inst=e and by_id[e._inst]
  local o=inst or {x=0,z=0}
  local pitch=.5*DEFAULT_SCALE
  local foot={x=o.x+math.floor((at.x-o.x)/pitch+.5)*pitch,y=at.y,z=o.z+math.floor((at.z-o.z)/pitch+.5)*pitch}
  player:set_wielded_item(put_part(player,stack,foot))
end

-- The menu also opens from the right button seen by the server: pointing at a part with the
-- separator or an empty hand (not every right click on a part reaches on_rightclick).
local last_place,menu_at={},{}
local function part_pointed(player)
  local eye=vector.offset(player:get_pos(),0,player:get_properties().eye_height or 1.5,0)
  local to=vector.add(eye,vector.multiply(player:get_look_dir(),7))
  for pt in C.raycast(eye,to,true,false) do
    if pt.type=="object" then
      local e=pt.ref:get_luaentity()
      if e and e.name=="brickcraft:model_part" then return e end
      if not e or e.name~="brickcraft:model_part" then
        if pt.ref:is_player() and pt.ref==player then -- the ray starts in the player
        else return end
      end
    elseif pt.type=="node" then
      local n=C.get_node(pt.under).name
      if n~=SUPPORT and n~="air" then return end
    end
  end
end
local function open_menu(player,e)
  local name=player:get_player_name()
  local now=C.get_us_time()
  if menu_at[name] and now-menu_at[name]<4e5 then return end
  local inst=by_id[e._inst]
  if not inst then return end
  menu_at[name]=now
  show_menu(player,inst,e._i)
end
C.register_globalstep(function()
  for _,player in ipairs(C.get_connected_players()) do
    local name=player:get_player_name()
    local place=player:get_player_control().place
    if place and not last_place[name] then
      local w=player:get_wielded_item():get_name()
      if w=="brickcraft:separator" or w=="" then
        local e=part_pointed(player)
        if e then open_menu(player,e) end
      end
    end
    last_place[name]=place
  end
end)
C.register_on_leaveplayer(function(player) last_place[player:get_player_name()]=nil; menu_at[player:get_player_name()]=nil end)

C.register_entity(":brickcraft:model_part",{
  initial_properties={visual="mesh",mesh="brickcraft_model_cat_1.glb",textures={"[fill:1x1:#888888"},
    physical=false,pointable=true,backface_culling=false,static_save=false,
    collisionbox={0,0,0,0,0,0},selectionbox={-.5,-.5,-.5,.5,.5,.5}},
  on_activate=function(self) self.object:set_armor_groups({immortal=1}) end,
  on_step=function(self)
    if not self._inst then self.object:remove() end
  end,
  on_punch=function() return true end,
  on_rightclick=function(self,clicker)
    if not clicker or not clicker:is_player() then return end
    local inst=by_id[self._inst]
    if not inst then return end
    local stack=clicker:get_wielded_item()
    local name=stack:get_name()
    local obj=self.object
    if name=="brickcraft:separator" or name=="" then open_menu(clicker,self)
    elseif name=="brickcraft:real_part" then
      before_change(clicker,inst,function() part_on_part(clicker,obj,clicker:get_wielded_item()) end)
    elseif C.registered_nodes[name] and stack:get_definition().on_place and name:match("^brickcraft:") then
      before_change(clicker,inst,function() if obj:get_pos() then brick_on_part(clicker,obj,clicker:get_wielded_item()) end end)
    end
  end,
  -- brickcraft's separator passes objects here (left click).
  _brickcraft_collect=function(self,player)
    local inst=by_id[self._inst]
    local i=self._i
    if inst then before_change(player,inst,function() take_part(player,inst,i) end) end
  end,
})

-- The first version's one-mesh models: each becomes an instance where it stood.
C.register_entity(":brickcraft:display_model",{
  initial_properties={visual="sprite",textures={"blank.png"},is_visible=false,static_save=false,pointable=false},
  on_activate=function(self,staticdata)
    local d=C.deserialize(staticdata or "") or {}
    local pos=self.object:get_pos()
    if d.slug and models[d.slug] then
      new_instance({slug=d.slug,x=pos.x,y=pos.y,z=pos.z,turn=d.turn or 0,scale=d.scale})
      C.log("action","BrickCraft models: "..d.slug.." at "..C.pos_to_string(vector.round(pos)).." is now made of its parts")
    end
    self.object:remove()
  end,
})

C.register_on_joinplayer(function(player)
  local name=player:get_player_name()
  local inv=player:get_inventory()
  -- The pictures of LEGO parts in the inventory (media on demand), once the player is in.
  local pics={}
  for i=1,inv:get_size("main") do
    local st=inv:get_stack("main",i)
    if st:get_name()=="brickcraft:real_part" then
      local mesh=st:get_meta():get_string("mesh")
      if mesh~="" then pics[#pics+1]=mesh:gsub("%.glb$",".png") end
    end
  end
  if #pics>0 then C.after(1,function() if C.get_player_by_name(name) then has_media(name,pics) end end) end
  for i=1,inv:get_size("main") do
    local stack=inv:get_stack("main",i)
    local meta=stack:get_meta()
    if stack:get_name()=="brickcraft:real_part" and meta:get_string("inventory_image")=="" and meta:get_string("mesh")~="" then
      local icon=meta:get_string("mesh"):gsub("%.glb$",".png").."^[multiply:"..meta:get_string("bc_color"):sub(1,7)
      meta:set_string("inventory_image",icon); meta:set_string("wield_image",icon); meta:set_string("color","")
      inv:set_stack("main",i,stack)
    end
  end
end)

C.register_node(":brickcraft:model_support",{
  description="Model support (invisible)",drawtype="nodebox",tiles={"blank.png"},use_texture_alpha="clip",
  paramtype="light",paramtype2="leveled",sunlight_propagates=true,
  node_box={type="leveled",fixed={-.5,-.5,-.5,.5,.5,.5}},
  walkable=true,pointable=false,diggable=false,buildable_to=true,floodable=false,is_ground_content=false,
  drop="",groups={not_in_creative_inventory=1},
})

C.register_craftitem(":brickcraft:real_part",{
  description="LEGO part",inventory_image="brickcraft_real_part.png",stack_max=99,
  on_place=function(stack,placer,pointed)
    if pointed.type~="node" or not placer then return stack end
    local udef=C.registered_nodes[C.get_node(pointed.under).name]
    local cell=(udef and udef.buildable_to) and pointed.under or pointed.above
    local below={x=cell.x,y=cell.y-1,z=cell.z}
    if S.on(cell) and not on_studs(below) then
      say(placer,"Strict LEGO: a part goes on studs (the ground or the top of a brick), not on a plate, tile or slope.")
      return stack
    end
    return put_part(placer,stack,{x=cell.x,y=cell.y-.5,z=cell.z})
  end,
})

-- /model -----------------------------------------------------------------------------------
local function spot_for(player,def,scale)
  local pos=player:get_pos()
  local dir=player:get_look_dir(); dir.y=0
  if vector.length(dir)<.01 then dir={x=0,y=0,z=1} end
  dir=vector.normalize(dir)
  local reach=math.max(def.w,def.d)*scale/2+1.5
  local at=vector.round(vector.add(pos,vector.multiply(dir,reach)))
  for y=math.floor(pos.y+2),math.floor(pos.y-8),-1 do
    local below={x=at.x,y=y,z=at.z}
    local ndef=C.registered_nodes[C.get_node(below).name]
    if ndef and ndef.walkable and C.get_node(below).name~=SUPPORT then return {x=at.x,y=y+.5,z=at.z},below end
  end
end

local function list_text()
  local rows={"Models (real LEGO builds from BrickWright, sizes at the game's grid, size 1):"}
  for i,m in ipairs(catalog) do
    rows[#rows+1]=string.format("  %d. %s  %s: %d pieces, %.0f x %.0f cells, %.0f tall",i,m.slug,m.title,m.pieces,m.w,m.d,m.h)
  end
  rows[#rows+1]="/model <name or number> [size] puts one in front of you (minifig scale, "..DEFAULT_SCALE.."; size 1 = game bricks). Separator: left click takes a part, right click opens the model's menu."
  return table.concat(rows,"\n")
end

local function place(name,param)
  local player=C.get_player_by_name(name)
  if not player then return false,"No player." end
  local which,size=param:match("^%s*(%S+)%s*(%S*)%s*$")
  if not which then return true,list_text() end
  local m=models[which] or catalog[tonumber(which) or 0]
  if not m then return false,"No model called "..which..".\n"..list_text() end
  local scale=DEFAULT_SCALE
  if size~="" then
    scale=tonumber(size)
    if not scale or scale<MIN_SCALE or scale>MAX_SCALE then return false,"Size is a number from "..MIN_SCALE.." to "..MAX_SCALE.." (1 = game bricks)." end
  end
  local foot,below=spot_for(player,m,scale)
  if not foot then return false,"Nowhere to stand it in front of you." end
  if S.on(foot) and not on_studs(below) then
    return false,"Strict LEGO: a model has to stand on studs (the ground or the top of a brick), not on a plate, tile or slope."
  end
  local inst=new_instance({slug=m.slug,x=foot.x,y=foot.y,z=foot.z,turn=yaw_turn(player),scale=scale})
  spawn(inst)
  return true,string.format("%s: %d real parts, %.0f cells tall%s.",m.title,#m.parts,m.h*scale,
    scale==1 and " (the game's grid)" or scale==DEFAULT_SCALE and ", minifig scale (size "..scale..")" or ", size "..scale)
end


-- The gallery screen --------------------------------------------------------------------------
-- Every model to look at before it goes down: turning in 3D (drag to turn it yourself), its
-- size chosen with a slider or a preset and drawn next to a player at that size, then put in
-- front of you. The 3D view is one mesh of the whole model (the import's preview: a formspec
-- shows one mesh), lit by a grey ramp in its texture coordinates.
local PLAYER_H=1.75
local SHADE="brickcraft_model_shade.png"
local gal={} -- player name -> {i = the model's place in the catalog, scale, wait = asked for its view at}
local function main_color(def)
  local n,best,bn={},nil,0
  for _,p in ipairs(def.parts) do
    n[p.color]=(n[p.color] or 0)+1
    if n[p.color]>bn then best,bn=p.color,n[p.color] end
  end
  return (best or "#888888"):sub(1,7)
end
local function fmt(v) return (string.format("%.2f",v):gsub("0+$",""):gsub("%.$","")) end
local function times_you(h)
  local r=h/PLAYER_H
  if r>=1.15 then return string.format("%.1f x your height",r) end
  if r>=.87 then return "about your height" end
  return string.format("%d%% of your height",math.floor(r*100+.5))
end

-- The size next to a player, both to scale: a figure, the model's front as a box, the ground.
local function size_picture(def,scale,x0,y0,pw,ph)
  local mw,mh=def.w*scale,def.h*scale
  local fw=.6 -- a player's width
  local k=math.min(ph*.82/math.max(mh,PLAYER_H),(pw-.5)/(fw+.4+mw))
  local ground=y0+ph-.35
  local function box(x,y,w,h,c)
    return "box["..fmt(x)..","..fmt(y)..";"..fmt(math.max(w,.03))..","..fmt(math.max(h,.03))..";"..c.."]"
  end
  local px=x0+.25
  local fs=box(x0,y0,pw,ph,"#2a3b46")..box(x0+.1,ground,pw-.2,.04,"#7d8c94")
  -- The figure: legs, body, head (a player is 1.75 cells: head .5, body .6, legs .65).
  local h=PLAYER_H*k
  fs=fs..box(px+fw*k*.15,ground-h*.37,fw*k*.7,h*.37,"#3a5a8c")..box(px,ground-h*.71,fw*k,h*.34,"#f5872c")..
    box(px+fw*k*.2,ground-h,fw*k*.6,h*.29,"#f2c79b")
  local mx=px+fw*k+.4
  local top=ground-mh*k
  fs=fs..box(mx-.03,top-.03,math.max(mw*k,.03)+.06,math.max(mh*k,.03)+.03,"#c8d2d8")..box(mx,top,mw*k,mh*k,main_color(def))..
    "label["..fmt(x0+.15)..","..fmt(ground+.2)..";You]"..
    "label["..fmt(mx)..","..fmt(math.max(y0+.2,top-.22))..";"..C.formspec_escape(fmt(mh).." cells tall").."]"
  return fs
end

local function gallery_formspec(name)
  local g=gal[name]
  local def=catalog[g.i]
  local items={}
  for _,m in ipairs(catalog) do items[#items+1]=C.formspec_escape(m.title.."  ("..m.pieces..")") end
  local fs="formspec_version[6]size[17.4,10.6]bgcolor[#0b1218cc]"..
    "label[.4,.5;Models: look, choose a size, put one in front of you]"..
    "textlist[.4,.9;3.9,8.4;pick;"..table.concat(items,",")..";"..g.i..";false]"..
    "box[4.6,.9;7.6,8.4;#5d7381]"
  if not def then return fs.."button_exit[.4,9.6;3.9,.7;close;Close]" end
  local ready=def.preview and (sent[name] or {})[def.preview]==true
  if ready then
    local tex={}
    for _,c in ipairs(def.preview_colors) do tex[#tex+1]=C.formspec_escape(SHADE.."^[multiply:"..c:sub(1,7)) end
    fs=fs.."model[4.6,.9;7.6,8.4;view;"..def.preview..";"..table.concat(tex,",")..";-18,200;true;true]"..
      "label[4.8,9.0;Drag to turn it]"
  elseif def.preview then
    fs=fs.."label[6.9,4.9;Loading the 3D view...]"
  else
    fs=fs.."textarea[5.2,4.2;6.4,1.6;;;"..C.formspec_escape("No 3D view for this one yet (it was sent before the gallery had them). Send it from BrickWright again, or run tools/import_brickwright.py --previews.").."]"
  end
  local s=g.scale
  local x=12.6
  fs=fs.."label["..x..",1.1;"..C.formspec_escape(def.title).."]"..
    "label["..x..",1.6;"..C.formspec_escape(def.pieces.." pieces").."]"..
    "label["..x..",2.25;"..C.formspec_escape("Size "..fmt(s)..(s==DEFAULT_SCALE and " (minifig)" or s==1 and " (game bricks)" or "")).."]"..
    "scrollbaroptions[min="..math.floor(MIN_SCALE*100)..";max="..math.floor(MAX_SCALE*100)..";smallstep=5;largestep=25]"..
    "scrollbar["..x..",2.5;4.4,.45;horizontal;scale;"..math.floor(s*100+.5).."]"..
    "button["..x..",3.1;.7,.6;smaller;-]"..
    "field["..(x+.8)..",3.1;1.4,.6;size;;"..fmt(s).."]field_close_on_enter[size;false]"..
    "button["..(x+2.3)..",3.1;.7,.6;bigger;+]"..
    "button["..(x+3.1)..",3.1;1.3,.6;set;Set]"..
    "button["..x..",3.85;1.4,.6;s_small;Small]button["..(x+1.5)..",3.85;1.4,.6;s_minifig;Minifig]"..
    "button["..(x+3)..",3.85;1.4,.6;s_game;Bricks]"..
    "tooltip[s_small;Size 0.3]tooltip[s_minifig;Size "..DEFAULT_SCALE..": a minifig as tall as you]"..
    "tooltip[s_game;Size 1: its bricks the size of game bricks]"..
    "label["..x..",4.85;"..C.formspec_escape(string.format("%s x %s cells, %s tall",fmt(def.w*s),fmt(def.d*s),fmt(def.h*s))).."]"..
    "label["..x..",5.3;"..C.formspec_escape(times_you(def.h*s)).."]"..
    size_picture(def,s,x,5.6,4.4,2.6)..
    "style[place;bgcolor=#f5872c]button_exit["..x..",8.5;4.4,.8;place;Put it in front of me]"..
    "button_exit[.4,9.6;3.9,.7;close;Close]"
  return fs
end

local function show_gallery(player)
  local name=player:get_player_name()
  local g=gal[name]
  if not g then return end
  local def=catalog[g.i]
  g.open=true
  C.show_formspec(name,"brickcraft_models:gallery",gallery_formspec(name))
  if def and def.preview and not has_media(name,{def.preview}) then
    -- Its view is on its way (the screen says it's loading): shown when it's there.
    local function check(tries)
      local p=C.get_player_by_name(name)
      if not (p and gal[name] and gal[name].open and catalog[gal[name].i]==def) or tries>240 then return end
      if has_media(name,{def.preview}) then show_gallery(p) else C.after(.25,function() check(tries+1) end) end
    end
    C.after(.25,function() check(0) end)
  end
end

local function open_gallery(player,which)
  local name=player:get_player_name()
  local g=gal[name] or {i=1,scale=DEFAULT_SCALE}
  if which then
    for i,m in ipairs(catalog) do if m.slug==which or tostring(i)==which then g.i=i end end
  end
  if g.i>#catalog then g.i=1 end
  gal[name]=g
  show_gallery(player)
end

local function snap(v) return math.max(MIN_SCALE,math.min(MAX_SCALE,math.floor(v*100+.5)/100)) end
C.register_on_player_receive_fields(function(player,formname,fields)
  local name=player:get_player_name()
  if formname=="" and fields.gallery then open_gallery(player); return true end
  if formname~="brickcraft_models:gallery" then return end
  local g=gal[name]
  if not g then return true end
  if fields.quit or fields.close then g.open=false end
  local redraw=false
  if fields.pick then
    local ev=C.explode_textlist_event(fields.pick)
    if ev.type=="CHG" or ev.type=="DCL" then
      if ev.index~=g.i then g.i=ev.index; redraw=true end
    end
  end
  if fields.scale then
    local ev=C.explode_scrollbar_event(fields.scale)
    if ev.type=="CHG" then
      local s=snap(ev.value/100)
      if s~=g.scale then g.scale=s; redraw=true end
    end
  end
  local typed=tonumber(((fields.size or ""):gsub(",",".")))
  if fields.set or fields.key_enter_field=="size" then
    if typed then g.scale=snap(typed) end
    redraw=true
  end
  if fields.smaller then g.scale=snap(g.scale-(g.scale>1 and .25 or .05)); redraw=true end
  if fields.bigger then g.scale=snap(g.scale+(g.scale>=1 and .25 or .05)); redraw=true end
  if fields.s_small then g.scale=.3; redraw=true end
  if fields.s_minifig then g.scale=DEFAULT_SCALE; redraw=true end
  if fields.s_game then g.scale=1; redraw=true end
  if fields.place then
    g.open=false
    local def=catalog[g.i]
    if def then
      local ok,msg=place(name,def.slug.." "..g.scale)
      if msg then say(player,msg) end
    end
    return true
  end
  if redraw and g.open~=false then show_gallery(player) end
  return true
end)
C.register_on_leaveplayer(function(player) gal[player:get_player_name()]=nil end)

C.register_chatcommand("gallery",{params="[name]",
  description="Look at the models in 3D, choose a size, and put one in front of you",
  func=function(name,param)
    local player=C.get_player_by_name(name)
    if not player then return false,"No player." end
    open_gallery(player,param:match("%S+"))
    return true
  end})

C.register_chatcommand("model",{params="[name]",
  description="Put a real LEGO model (from BrickWright) in front of you; no name lists them",func=place})
C.register_chatcommand("models",{description="List the models",func=function() return true,list_text() end})

for _,row in ipairs({
  {"/gallery  (I > Model gallery)","See every model turning in 3D, choose its size next to you, and put it in front of you"},
  {"/model","List the models (real LEGO builds from BrickWright)"},
  {"/model bonsai [size]","Put one in front of you (minifig scale; size 1 = game bricks, change it in its menu)"},
  {"Separator on a model","Left click: take a part into the inventory. Right click or F: menu (break apart, stack parts, game bricks, turn, size, put away)"},
  {"Brick on a model","Right click a part with a brick to build on it"},
}) do brickcraft.help[#brickcraft.help+1]=row end

-- The Model Gallery -------------------------------------------------------------------------
-- A shared strict LEGO world, made once like the Kart Circuit, with one of each sample
-- round the arrival spots (x -6..6, z 1..4, looking +z), facing them. Its brick stacks and
-- arch go to make room. Models sent from BrickWright take a free spot in the front row.
local GALLERY={
  bonsai={x=0,z=15}, house={x=-16,z=14}, mech={x=16,z=14},
  cat={x=-14,z=4}, train={x=14,z=4}, car={x=-14,z=-8},
}
local EXTRA={{x=0,z=-14},{x=14,z=-10},{x=-20,z=-18},{x=20,z=-20},{x=-6,z=-21},{x=8,z=-21}}
local R=24
local function gallery_world() for _,w in ipairs(brickcraft.worlds()) do if w.gallery then return w end end end

local function gallery_place(w,m,at)
  new_instance({slug=m.slug,x=w.x+at.x,y=-.5,z=w.z+at.z,turn=0,scale=DEFAULT_SCALE})
  w.gallery_models[m.slug]=true
end

local function fill_gallery(w,fresh)
  if fresh then
    for x=-R,R do for z=-R,R do for y=0,4 do
      if (z>=10 and z<=12) or z==-7 then
        local pos={x=w.x+x,y=y,z=w.z+z}
        if C.get_node(pos).name~="air" then C.remove_node(pos) end
      end
    end end end
  end
  w.gallery_models=w.gallery_models or {}
  local placed={}
  for _,m in ipairs(catalog) do
    local at=GALLERY[m.slug]
    if at and not w.gallery_models[m.slug] then gallery_place(w,m,at); placed[#placed+1]=m.slug end
  end
  brickcraft.save_worlds()
  if #placed>0 then C.log("action","BrickCraft Model Gallery: placed "..table.concat(placed,", ")) end
end

-- A sent model in the gallery's front row, if one of its spots is free and it fits.
local function gallery_add(m)
  local w=gallery_world()
  if not w or not w.built or not w.gallery_models or w.gallery_models[m.slug] then return end
  if m.w>10 or m.d>10 then return end
  w.gallery_extra=w.gallery_extra or {}
  for n,at in ipairs(EXTRA) do
    if not w.gallery_extra[n] then
      C.emerge_area({x=w.x+at.x-6,y=-2,z=w.z+at.z-6},{x=w.x+at.x+6,y=16,z=w.z+at.z+6},function(_,_,r)
        if r>0 then return end
        gallery_place(w,m,at); w.gallery_extra[n]=m.slug; brickcraft.save_worlds()
      end)
      return true
    end
  end
end

C.after(0,function()
  if brickcraft.testing and not C.settings:get_bool("brickcraft_models_test",false) then return end
  local w=gallery_world()
  local function load_and(fn)
    C.emerge_area({x=w.x-R,y=-2,z=w.z-R},{x=w.x+R,y=31,z=w.z+R},function(_,_,r) if r==0 then fn() end end)
  end
  if w then
    local missing=false
    for slug in pairs(GALLERY) do if models[slug] and not (w.gallery_models or {})[slug] then missing=true end end
    if w.built and missing then load_and(function() fill_gallery(w,not w.gallery_models) end) end
    return
  end
  w=brickcraft.make_world("Model Gallery","BrickCraft",function(w) fill_gallery(w,true) end,{strict=true})
  C.log("action","BrickCraft Model Gallery "..(w and "being made at "..w.x..","..w.z or "has no room"))
  if w then w.gallery=true; brickcraft.save_worlds() end
end)

-- Sent from BrickWright --------------------------------------------------------------------
local INBOX=C.get_worldpath().."/brickwright_models"
local seen={} -- slug -> the model.json text last loaded
local function check_inbox(announce)
  for _,slug in ipairs(C.get_dir_list(INBOX,true) or {}) do
    local dir=INBOX.."/"..slug
    local data,text=read_json(dir.."/model.json")
    if data and text~=seen[slug] and data.slug==slug then
      seen[slug]=text
      local d=def_from(data)
      local prefix=data.mesh_prefix or ("brickcraft_model_"..slug)
      local ok=true
      for k=1,data.meshes or 0 do -- sent to each player when they come near (media on demand)
        for _,ext in ipairs({".glb",".png"}) do
          local file=prefix.."_"..k..ext
          local f=io.open(dir.."/"..file,"rb")
          if f then f:close(); files[file]=dir.."/"..file elseif ext==".glb" then ok=false end
        end
      end
      if data.preview then
        local f=io.open(dir.."/"..data.preview,"rb")
        if f then f:close(); files[data.preview]=dir.."/"..data.preview else d.preview=nil end
      end
      if ok then
        local was=models[slug]
        add_def(d)
        -- Models standing already keep their parts: the new version is for the next one.
        for _,inst in ipairs(state.list) do if inst.slug==slug then respawn(inst) end end
        if announce then
          local where=gallery_add(d) and " It's in the Model Gallery too." or ""
          C.chat_send_all((was and "Updated" or "New").." from BrickWright: "..d.title..". Type /model "..slug.." to put it in front of you."..where)
        end
        C.log("action","BrickCraft models: "..slug.." from BrickWright ("..#d.parts.." parts)")
      else
        C.log("warning","BrickCraft models: couldn't add the meshes of "..slug)
      end
    end
  end
end
local inbox_timer=0
C.after(0,function() check_inbox(false) end)
C.register_globalstep(function(dtime)
  inbox_timer=inbox_timer+dtime
  if inbox_timer<3 then return end
  inbox_timer=0
  check_inbox(true)
end)

brickcraft.models={catalog=catalog,models=models,place=place,open_gallery=open_gallery,gallery_formspec=gallery_formspec,gallery_state=gal,gallery=gallery_world,GALLERY=GALLERY,
  instances=function() return state.list end,instance=function(id) return by_id[id] end,
  spawned=function(id) return spawned[id] end,take_part=take_part,break_all=break_all,convert=convert,
  turn=turn_model,put_away=put_away,organize=organize,resize=resize,unify=unify,before_change=before_change,hanging=hanging,support_cells=support_cells,def_of=def_of,
  item_for=item_for,put_part=put_part,has_media=has_media,files_of=files_of,media=files,settle=settle,box_of=box_of,floor_under=floor_under,check_inbox=check_inbox,SUPPORT=SUPPORT,DEFAULT_SCALE=DEFAULT_SCALE}
