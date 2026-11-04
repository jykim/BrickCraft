-- Models: builds of real LEGO parts made with BrickWright (validated there: no collisions,
-- nothing floating, all connected), standing in the world part by part.
--
-- Size 1 is the game's own scale: a cell is 2 x 2 studs wide and one brick tall, so a
-- model's real 2 x 2 brick is exactly a game 2 x 2 brick and a plate a third of a cell
-- (tools/import_brickwright.py writes the parts that way). A model goes down at any size
-- (/model bonsai 0.3) and its size can change from its menu, until it's first changed
-- itself: before a part comes off, it's broken, rebuilt or built on, the player is warned
-- and the model goes to size 1 for good, so its parts are the game's pieces. With the separator:
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

local function def_from(data)
  local d={slug=data.slug,title=data.title or data.slug,record=data.record,pieces=data.pieces or #data.parts,
    w=data.w,h=data.h,d=data.d,prompt=data.prompt,bricks=data.bricks,parts={},adj={},ground={}}
  local prefix=data.mesh_prefix or ("brickcraft_model_"..data.slug)
  for i,p in ipairs(data.parts) do
    d.parts[i]={mesh=prefix.."_"..p[1]..".glb",color=p[2],x=p[3],y=p[4],z=p[5],hx=p[6],hy=p[7],hz=p[8],
      part=p[9] or "?",cname=p[10] or ""}
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
local by_id={}
for _,inst in ipairs(state.list) do by_id[inst.id]=inst end
local function save() storage:set_string("model_instances",C.serialize(state)) end

local function def_of(inst)
  if inst.part then
    inst._def=inst._def or single_def(inst.part)
    return inst._def
  end
  return models[inst.slug]
end

-- Quarter turns, the way set_yaw(turn * pi/2) turns a mesh.
local function rot(x,z,t)
  for _=1,t%4 do x,z=-z,x end
  return x,z
end
local MIN_SCALE,MAX_SCALE=.1,3
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

-- Parts (not gone) no ground part holds up through touching parts.
local function hanging(def,gone)
  local seen,queue={},{}
  for i in pairs(def.ground) do if not gone[i] then seen[i]=true; queue[#queue+1]=i end end
  while #queue>0 do
    local i=table.remove(queue)
    for _,j in ipairs(def.adj[i] or {}) do
      if not gone[j] and not seen[j] then seen[j]=true; queue[#queue+1]=j end
    end
  end
  local n=0
  for i=1,#def.parts do if not gone[i] and not seen[i] then n=n+1 end end
  return n
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

local function spawn(inst)
  local def=def_of(inst)
  if not def or spawned[inst.id] or (def.ready_at and C.get_us_time()<def.ready_at) then return end
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
  by_id[inst.id]=nil
  for i,o in ipairs(state.list) do if o==inst then table.remove(state.list,i); break end end
  save()
end

local timer=0
C.register_globalstep(function(dtime)
  timer=timer+dtime
  if timer<1 then return end
  timer=0
  local players=C.get_connected_players()
  for _,inst in ipairs(state.list) do
    local near=false
    for _,pl in ipairs(players) do
      local p=pl:get_pos()
      if math.abs(p.x-inst.x)<NEAR and math.abs(p.z-inst.z)<NEAR then near=true; break end
    end
    if near then
      local parts=spawned[inst.id]
      if parts then -- an entity can go with its mapblock; put it back
        for i,obj in pairs(parts) do if not obj:get_pos() then spawn_part(inst,i,def_of(inst).parts[i]) end end
      else spawn(inst) end
    elseif spawned[inst.id] then despawn(inst) end
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
  if s then return ItemStack("brickcraft:"..nearest_color(p.color).." "..s.cost),s end
  local stack=ItemStack("brickcraft:real_part")
  local meta=stack:get_meta()
  for _,f in ipairs({"mesh","color","part","cname"}) do meta:set_string(f,p[f]) end
  for _,f in ipairs({"hx","hy","hz"}) do meta:set_float(f,p[f]) end
  meta:set_string("color",p.color:sub(1,7)) -- tints the icon
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
  if strict and not all then
    local more=hanging(def,gone)-hanging(def,inst.gone)
    if more>0 then
      if not quiet then say(player,"Strict LEGO: that part holds up "..more.." other part"..(more>1 and "s" or "")..". Take those off first.") end
      return false
    end
  end
  local cells=support_cells(inst,gone)
  if strict and not all and bricks_on(inst,cells) then
    if not quiet then say(player,"Strict LEGO: a brick stands on that part. Take it off first.") end
    return false
  end
  local stack=item_for(p)
  local inv=player:get_inventory()
  if not inv:room_for_item("main",stack) then
    if not quiet then say(player,"No room in your inventory for that part.") end
    return false
  end
  inv:add_item("main",stack)
  inst.gone=gone
  local obj=spawned[inst.id] and spawned[inst.id][i]
  if obj then obj:remove(); spawned[inst.id][i]=nil end
  apply_support(inst,cells)
  local left=0
  for j=1,#def.parts do if not gone[j] then left=left+1 end end
  if left==0 then drop_instance(inst) else save() end
  return true
end

-- Every part, top first, while the inventory has room (all of them come off, so none is
-- left hanging; bricks on the model were checked first).
local function break_all(player,inst)
  local def=def_of(inst)
  if S.on(inst) and bricks_on(inst,{}) then
    return say(player,"Strict LEGO: game bricks stand on this model. Take them off first.")
  end
  local idx={}
  for i in ipairs(def.parts) do if not inst.gone[i] then idx[#idx+1]=i end end
  table.sort(idx,function(a,b) return def.parts[a].y+def.parts[a].hy>def.parts[b].y+def.parts[b].hy end)
  local n,full=0,false
  for _,i in ipairs(idx) do
    if not by_id[inst.id] then break end
    local stack=item_for(def.parts[i])
    if not player:get_inventory():room_for_item("main",stack) then full=true; break end
    if take_part(player,inst,i,true,true) then n=n+1 end
  end
  say(player,"Took "..n.." real part"..(n==1 and "" or "s").." into your inventory"..
    (full and " (it's full: the rest stays on the model)." or "."))
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
  local items={}
  for _,b in ipairs(def.bricks) do
    local x,z=rot(b[1],b[3],inst.turn)
    local pos={x=math.floor(base.x+x+.5),y=base.y+b[2],z=math.floor(base.z+z+.5)}
    if C.get_node(pos).name=="air" then items[#items+1]={pos=pos,node={name="brickcraft:"..b[4],param2=0}} end
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
  new_instance({part=p,x=foot.x,y=foot.y,z=foot.z,turn=yaw_turn(player),modified=true})
  stack:take_item(1)
  return stack
end

-- One scale before a model changes ------------------------------------------------------
-- The first change to a model (a part off, broken, rebuilt, built on) asks first: it goes
-- to size 1, the game's scale, and keeps it, so its parts are the game's pieces.
local pending={} -- player name -> {id, action}
local function unify(player,inst)
  if (inst.scale or 1)~=1 then
    local old=inst.scale
    inst.scale=1
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
  local text=s==1 and ("Changing "..def.title.." keeps it at the game's scale (size 1), where its real parts are the game's pieces. After this its size can't change.")
    or (def.title.." is at size "..s..". Changing it first resizes it to the game's scale (size 1, "..
      string.format("%.0f",def.h).." cells tall), so its real parts match the game's bricks. After this its size can't change.")
  C.show_formspec(name,"brickcraft_models:unify","formspec_version[4]size[8,4.4]"..
    "textarea[.4,.4;7.2,2.4;;;"..C.formspec_escape(text).."]"..
    "button_exit[.4,3.2;3.4,.8;yes;"..(s==1 and "Go on" or "Resize and go on").."]"..
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
  if inst.modified then return say(player,"This model has been changed, so it stays at the game's scale.") end
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
  local size=inst.modified and "label[.4,6.0;Size 1, the game's scale (fixed: it has been changed)]"
    or ("field[.4,5.7;2,.7;size;Size;"..(inst.scale or 1).."]button[2.6,5.7;4.4,.7;resize;Change size (1 = game bricks)]")
  local fs="formspec_version[4]size[7.4,8.4]"..size..
    "label[.4,.6;"..C.formspec_escape(def.title).."]"..
    "label[.4,1.1;"..C.formspec_escape(left.." of "..#def.parts.." real parts on it. This one: "..p.part..
      (p.cname~="" and " ("..p.cname..")" or "")).."]"..
    "button[3.8,1.6;3.2,.8;take;Take this part]"..
    "button[.4,1.6;3.2,.8;break;Break it apart]"..
    (def.bricks and "button[.4,2.5;6.6,.8;convert;Rebuild it in game bricks]" or "")..
    "button[.4,3.4;6.6,.8;turn;Turn it a quarter]"..
    "button[.4,4.3;6.6,.8;away;Put it away (parts don't go to the inventory)]"..
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
  elseif fields["break"] then before_change(player,inst,function() break_all(player,inst) end)
  elseif fields.convert then before_change(player,inst,function() convert(player,inst) end)
  elseif fields.turn then turn_model(player,inst); close=false
  elseif fields.away then put_away(player,inst)
  elseif fields.resize then
    local s=tonumber(fields.size)
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
  local foot={x=math.floor(at.x*2+.5)/2,y=at.y,z=math.floor(at.z*2+.5)/2}
  player:set_wielded_item(put_part(player,stack,foot))
end

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
    if name=="brickcraft:separator" then show_menu(clicker,inst,self._i)
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
  local rows={"Models (real LEGO builds from BrickWright, same scale as game bricks):"}
  for i,m in ipairs(catalog) do
    rows[#rows+1]=string.format("  %d. %s  %s: %d pieces, %.0f x %.0f cells, %.0f tall",i,m.slug,m.title,m.pieces,m.w,m.d,m.h)
  end
  rows[#rows+1]="/model <name or number> [size] puts one in front of you (size 1 = game bricks). Separator: left click takes a part, right click opens the model's menu."
  return table.concat(rows,"\n")
end

local function place(name,param)
  local player=C.get_player_by_name(name)
  if not player then return false,"No player." end
  local which,size=param:match("^%s*(%S+)%s*(%S*)%s*$")
  if not which then return true,list_text() end
  local m=models[which] or catalog[tonumber(which) or 0]
  if not m then return false,"No model called "..which..".\n"..list_text() end
  local scale=1
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
    scale==1 and " (the game's scale)" or ", size "..scale)
end

C.register_chatcommand("model",{params="[name]",
  description="Put a real LEGO model (from BrickWright) in front of you; no name lists them",func=place})
C.register_chatcommand("models",{description="List the models",func=function() return true,list_text() end})

for _,row in ipairs({
  {"/model","List the models (real LEGO builds from BrickWright)"},
  {"/model bonsai [size]","Put one in front of you (size 1 = game bricks, change it in its menu)"},
  {"Separator on a model","Left click: take a part into the inventory. Right click: menu (break apart, game bricks, turn, put away)"},
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
  new_instance({slug=m.slug,x=w.x+at.x,y=-.5,z=w.z+at.z,turn=0})
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
      d.ready_at=C.get_us_time()+2e6 -- clients get the meshes first
      local prefix=data.mesh_prefix or ("brickcraft_model_"..slug)
      local ok=true
      for k=1,data.meshes or 0 do
        local file=prefix.."_"..k..".glb"
        if not C.dynamic_add_media({filename=file,filepath=dir.."/"..file,ephemeral=false},function() end) then ok=false end
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

brickcraft.models={catalog=catalog,models=models,place=place,gallery=gallery_world,GALLERY=GALLERY,
  instances=function() return state.list end,instance=function(id) return by_id[id] end,
  spawned=function(id) return spawned[id] end,take_part=take_part,break_all=break_all,convert=convert,
  turn=turn_model,put_away=put_away,resize=resize,unify=unify,before_change=before_change,hanging=hanging,support_cells=support_cells,def_of=def_of,
  item_for=item_for,put_part=put_part,check_inbox=check_inbox,SUPPORT=SUPPORT}
