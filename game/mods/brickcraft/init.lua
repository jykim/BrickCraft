local C = core
-- Automated checks skip the welcome and look pickers.
local testing = C.settings:get_bool("brickcraft_integration_test",false) or
  C.settings:get_bool("brickcraft_multiplayer_test",false) or C.settings:get_bool("brickcraft_house_test",false) or
  C.settings:get_bool("brickcraft_ai_test",false)
-- The first 8 colors are the starter kit; the last 3 come from harvesting the landscape.
local colors = {"coral", "gold", "mint", "sky", "violet", "cream", "navy", "rose", "green", "brown", "tan"}
local labels = {"Coral", "Gold", "Mint", "Sky", "Violet", "Cream", "Navy", "Rose", "Green", "Brown", "Tan"}
local STARTER_COLORS = 8
C.register_alias("mapgen_singlenode", "air")
C.register_item(":", {type="none", wield_image="brickcraft_hand.png", range=7,
  tool_capabilities={full_punch_interval=1, groupcaps={}}})

-- Shapes share one inventory item per color: the hotbar stays 1 separator + 8 colors.
-- cost = voxel cells occupied; the 2 x 2 node keeps its original name for saved worlds.
-- One cell = 2 x 2 studs wide and one brick tall; a plate is a third of a brick.
-- Bodies fill their cell and studs poke into the cell above, so a brick stacked on top
-- hides the studs it covers, like real bricks clicking together.
-- Every shape mirrors a real catalog part (design ID in `part`), so a build can be listed
-- as real parts later. Long shapes span two cells along +z and keep an invisible end cell.
local function studs(boxes,xs,zs,y0,y1)
  for _, x in ipairs(xs) do
    for _, z in ipairs(zs) do boxes[#boxes+1] = {x-.13,y0,z-.13,x+.13,y1,z+.13} end
  end
  return boxes
end
local PLATE_TOP=-.5+1/3
local function plate(x1,z1,xs,zs)
  return studs({{-.5,-.5,-.5,x1,PLATE_TOP,z1}},xs,zs,PLATE_TOP,PLATE_TOP+.14)
end
local shapes = {
  {id="2x2", suffix="", label="Brick 2 x 2", part="3003", group="Bricks", cost=1,
   boxes=studs({{-.5,-.5,-.5,.5,.5,.5}},{-.25,.25},{-.25,.25},.5,.64)},
  {id="1x2", suffix="_1x2", label="Brick 1 x 2", part="3004", group="Bricks", cost=1,
   boxes=studs({{-.5,-.5,-.5,0,.5,.5}},{-.25},{-.25,.25},.5,.64),
   collision={-.5,-.5,-.5,0,.5,.5}},
  {id="2x4", suffix="_2x4", label="Brick 2 x 4", part="3001", group="Bricks", cost=2, long=true,
   boxes=studs({{-.5,-.5,-.5,.5,.5,1.5}},{-.25,.25},{-.25,.25,.75,1.25},.5,.64)},
  {id="1x1", suffix="_1x1", label="Brick 1 x 1", part="3005", group="Bricks", cost=1,
   boxes=studs({{-.5,-.5,-.5,0,.5,0}},{-.25},{-.25},.5,.64),
   collision={-.5,-.5,-.5,0,.5,0}},
  {id="plate", suffix="_plate", label="Plate 2 x 2", part="3022", group="Plates", cost=1,
   boxes=plate(.5,.5,{-.25,.25},{-.25,.25}),
   collision={-.5,-.5,-.5,.5,PLATE_TOP,.5}},
  {id="plate_1x2", suffix="_plate_1x2", label="Plate 1 x 2", part="3023", group="Plates", cost=1,
   boxes=plate(0,.5,{-.25},{-.25,.25}),
   collision={-.5,-.5,-.5,0,PLATE_TOP,.5}},
  {id="plate_2x4", suffix="_plate_2x4", label="Plate 2 x 4", part="3020", group="Plates", cost=2, long=true,
   boxes=plate(.5,1.5,{-.25,.25},{-.25,.25,.75,1.25}),
   collision={-.5,-.5,-.5,.5,PLATE_TOP,.5}},
  {id="plate_1x1", suffix="_plate_1x1", label="Plate 1 x 1", part="3024", group="Plates", cost=1,
   boxes=plate(0,0,{-.25},{-.25}),
   collision={-.5,-.5,-.5,0,PLATE_TOP,0}},
  -- Tiles are smooth plates: no studs, a flat finish for floors and roof ridges.
  {id="tile_2x2", suffix="_tile_2x2", label="Tile 2 x 2", part="3068", group="Tiles & Round", cost=1,
   boxes=plate(.5,.5,{},{}),
   collision={-.5,-.5,-.5,.5,PLATE_TOP,.5}},
  {id="tile_1x2", suffix="_tile_1x2", label="Tile 1 x 2", part="3069", group="Tiles & Round", cost=1,
   boxes=plate(0,.5,{},{}),
   collision={-.5,-.5,-.5,0,PLATE_TOP,.5}},
  {id="round_2x2", suffix="_round_2x2", label="Round Brick 2 x 2", part="3941", group="Tiles & Round", cost=1,
   mesh="brickcraft_round_2x2.obj"},
  {id="round_1x1", suffix="_round_1x1", label="Round Brick 1 x 1", part="3062", group="Tiles & Round", cost=1,
   mesh="brickcraft_round_1x1.obj",
   collision={-.5,-.5,-.5,0,.5,0}},
  {id="slope_2x2", suffix="_slope_2x2", label="Slope 45 2 x 2", part="3039", group="Slopes", cost=1,
   mesh="brickcraft_slope_2x2.obj",
   collision={{-.5,-.5,-.5,.5,0,.5},{-.5,0,0,.5,.5,.5}}},
  {id="slope_2x1", suffix="_slope_2x1", label="Slope 45 2 x 1", part="3040", group="Slopes", cost=1,
   mesh="brickcraft_slope_2x1.obj",
   collision={{-.5,-.5,-.5,0,0,.5},{-.5,0,0,0,.5,.5}}},
  -- Inverted: full studded top, the 45-degree face underneath toward the builder.
  {id="slope_inv_2x2", suffix="_slope_inv_2x2", label="Inverted Slope 45 2 x 2", part="3660", group="Slopes", cost=1,
   mesh="brickcraft_slope_inv_2x2.obj",
   collision={{-.5,0,-.5,.5,.5,.5},{-.5,-.5,0,.5,0,.5}}},
}
local shape_by_id = {}
for i, s in ipairs(shapes) do s.index=i; shape_by_id[s.id]=s end

local function get_shape(player)
  return shape_by_id[player:get_meta():get_string("brickcraft_shape")] or shapes[1]
end
local function get_turn(player) return player:get_meta():get_int("brickcraft_turn")%4 end

-- One in-memory action per player is enough for a predictable Undo button. The
-- node is checked before reversal so one builder can never undo over a friend's
-- later change to the same space.
local history={}
local function copy_pos(pos) return {x=pos.x,y=pos.y,z=pos.z} end
local function same_node(pos,node)
  local current=C.get_node(pos)
  return current.name==node.name and current.param2==node.param2
end
local function remember(player,action)
  if player and player:is_player() then history[player:get_player_name()]=action end
end

-- A long piece is one primary node (drawn across both cells) plus an invisible tail cell.
local function tail_pos(pos,param2) return vector.add(pos,C.facedir_to_dir(param2%4)) end
local function primary_of(pos,node)
  if C.get_item_group(node.name,"brick_tail")==1 then
    local p=vector.subtract(pos,C.facedir_to_dir(node.param2%4))
    return p, C.get_node(p)
  end
  return pos, node
end
local function is_free(pos)
  local def=C.registered_nodes[C.get_node(pos).name]
  return def and def.buildable_to and pos.y>=0
end

local place_brick, turn_next
local function collect(pos,node,player)
  local clicked=pos
  pos,node=primary_of(pos,node)
  local name=player:get_player_name()
  if player:get_wielded_item():get_name() ~= "brickcraft:separator" then
    C.chat_send_player(name, "Select the orange separator (1) to collect bricks.")
    return false
  end
  local def=C.registered_nodes[node.name]
  if not def or C.get_item_group(node.name,"brick")~=1 then
    -- An end cell whose brick is already gone is tidied up without a refund.
    if pos~=clicked then C.remove_node(clicked) end
    return false
  end
  if not player:get_inventory():room_for_item("main", def.drop) then
    C.chat_send_player(name, "Inventory full: place some bricks first.")
    return false
  end
  local tail,tail_node
  if def.brickcraft_long then
    tail=tail_pos(pos,node.param2)
    tail_node=C.get_node(tail)
  end
  local result=C.node_dig(pos,node,player)
  if not same_node(pos,node) then
    remember(player,{kind="collect",pos=copy_pos(pos),node={name=node.name,param2=node.param2},
      drop=def.drop,tail=tail and copy_pos(tail),tail_node=tail_node and
        {name=tail_node.name,param2=tail_node.param2}})
  end
  return result
end

for i, color in ipairs(colors) do
  local item="brickcraft:"..color
  for _, s in ipairs(shapes) do
    local nodename=item..s.suffix
    local box={type="fixed",fixed=s.collision or {-.5,-.5,-.5,.5,.5,.5}}
    local def={
      description=labels[i].." "..s.label.."\nPart "..s.part,
      drawtype=s.mesh and "mesh" or "nodebox", mesh=s.mesh,
      node_box=not s.mesh and {type="fixed", fixed=s.boxes} or nil,
      tiles={"brickcraft_"..color..".png"}, paramtype="light", paramtype2="facedir",
      collision_box=box, selection_box=box,
      groups={brick=1, not_in_creative_inventory=s.suffix~="" and 1 or nil}, stack_max=999,
      drop=item..(s.cost>1 and " "..s.cost or ""),
      sunlight_propagates=s.id~="2x2", brickcraft_shape=s.id, brickcraft_long=s.long,
      on_dig=collect,
    }
    if s.id=="2x2" then
      def.description=labels[i].." Bricks"
      -- Node items default to 4 nodes of reach; match the separator so building works
      -- from as far away as collecting does (and in third-person view).
      def.range=7
      def.on_place=function(stack,placer,pointed) return place_brick(stack,placer,pointed,item) end
      -- Q turns the next brick instead of throwing it into the world.
      def.on_drop=function(stack,dropper) turn_next(dropper); return stack end
    end
    if s.long then
      def.on_destruct=function(pos)
        local t=tail_pos(pos,C.get_node(pos).param2)
        if C.get_node(t).name==nodename.."_tail" then C.remove_node(t) end
      end
      -- The end cell of a plate is only plate-high so bricks can sit on both halves.
      local tail_box={type="fixed",fixed=s.collision or {-.5,-.5,-.5,.5,.5,.5}}
      C.register_node(nodename.."_tail", {
        description=labels[i].." "..s.label.." (end)", drawtype="airlike", paramtype="light",
        paramtype2="facedir", sunlight_propagates=true, walkable=true, pointable=true,
        groups={brick_tail=1, not_in_creative_inventory=1}, drop="",
        collision_box=tail_box, selection_box=tail_box, on_dig=collect,
      })
    end
    C.register_node(nodename, def)
  end
end

local hud={}
local held={} -- keys each player held last step
local function update_hud(player)
  local name=player:get_player_name()
  local sh=get_shape(player)
  local text="Piece: "..sh.label.." (part "..sh.part..")  [Tab]     Turn: "..(get_turn(player)*90).."°  [Q]"
  if hud[name] then player:hud_change(hud[name],"text",text)
  else
    hud[name]=player:hud_add({type="text",position={x=.5,y=1},offset={x=0,y=-96},
      text=text,number=0xffffff,alignment={x=0,y=0},scale={x=100,y=20}})
  end
end
local inventory_formspec
local function set_shape(player,shape)
  player:get_meta():set_string("brickcraft_shape",shape.id)
  player:set_inventory_formspec(inventory_formspec(player))
  update_hud(player)
end
function turn_next(player)
  if not player or not player:is_player() then return end
  player:get_meta():set_int("brickcraft_turn",(get_turn(player)+1)%4)
  update_hud(player)
end

function place_brick(stack,placer,pointed,item)
  if pointed.type~="node" or not placer or not placer:is_player() then return stack end
  local udef=C.registered_nodes[C.get_node(pointed.under).name]
  local name=placer:get_player_name()
  local s=get_shape(placer)
  if stack:get_count()<s.cost then
    C.chat_send_player(name,"A "..s.label.." needs "..s.cost.." bricks of this color.")
    return stack
  end
  local pos=(udef and udef.buildable_to) and pointed.under or pointed.above
  local param2=(C.dir_to_facedir(placer:get_look_dir())+get_turn(placer))%4
  local tail=s.long and tail_pos(pos,param2)
  if tail and not is_free(tail) then
    C.chat_send_player(name,"No room for a "..s.label.." here. Press Q to turn it.")
    return stack
  end
  local _,placed=C.item_place_node(ItemStack(item..s.suffix),placer,pointed,param2)
  if not placed then return stack end
  if tail then C.set_node(tail,{name=item..s.suffix.."_tail",param2=param2}) end
  stack:take_item(s.cost)
  remember(placer,{kind="place",pos=copy_pos(pos),node={name=item..s.suffix,param2=param2},
    drop=item.." "..s.cost,tail=tail and copy_pos(tail),tail_node=tail and
      {name=item..s.suffix.."_tail",param2=param2}})
  return stack
end

-- Separator right click turns a placed brick a quarter turn in place.
local function turn_placed(pos,node,player)
  pos,node=primary_of(pos,node)
  local def=C.registered_nodes[node.name]
  if not def or not def.brickcraft_shape then return end
  local param2=(node.param2+1)%4
  local old_tail,new_tail
  if def.brickcraft_long then
    old_tail,new_tail=tail_pos(pos,node.param2),tail_pos(pos,param2)
    if not is_free(new_tail) then
      C.chat_send_player(player:get_player_name(),"No room to turn this long piece.")
      return
    end
    C.set_node(new_tail,{name=node.name.."_tail",param2=param2})
    C.remove_node(old_tail)
  end
  C.swap_node(pos,{name=node.name,param2=param2})
  remember(player,{kind="turn",pos=copy_pos(pos),before={name=node.name,param2=node.param2},
    after={name=node.name,param2=param2},old_tail=old_tail and copy_pos(old_tail),
    new_tail=new_tail and copy_pos(new_tail),tail_name=def.brickcraft_long and node.name.."_tail"})
end

local function undo_last(player)
  local name=player:get_player_name()
  local action=history[name]
  if not action then C.chat_send_player(name,"Nothing to undo yet."); return false end
  local inv=player:get_inventory()
  if action.kind=="place" then
    if not same_node(action.pos,action.node) or
       (action.tail and not same_node(action.tail,action.tail_node)) then
      C.chat_send_player(name,"Can't undo: that brick was changed by someone else.")
      return false
    end
    if not inv:room_for_item("main",action.drop) then
      C.chat_send_player(name,"Can't undo: your inventory is full.")
      return false
    end
    C.remove_node(action.pos) -- long-piece on_destruct also removes its tail
    inv:add_item("main",action.drop)
  elseif action.kind=="collect" then
    if not is_free(action.pos) or (action.tail and not is_free(action.tail)) then
      C.chat_send_player(name,"Can't undo: another brick now occupies that space.")
      return false
    end
    if not inv:contains_item("main",action.drop) then
      C.chat_send_player(name,"Can't undo: you no longer have the collected brick.")
      return false
    end
    inv:remove_item("main",action.drop)
    C.set_node(action.pos,action.node)
    if action.tail then C.set_node(action.tail,action.tail_node) end
  elseif action.kind=="turn" then
    if not same_node(action.pos,action.after) or
       (action.new_tail and not same_node(action.new_tail,
         {name=action.tail_name,param2=action.after.param2})) or
       (action.old_tail and not is_free(action.old_tail)) then
      C.chat_send_player(name,"Can't undo: that brick was changed by someone else.")
      return false
    end
    if action.new_tail then C.remove_node(action.new_tail) end
    C.swap_node(action.pos,action.before)
    if action.old_tail then
      C.set_node(action.old_tail,{name=action.tail_name,param2=action.before.param2})
    end
  end
  history[name]=nil
  C.chat_send_player(name,"Undid your last "..action.kind.." action.")
  return true
end

C.register_node("brickcraft:baseplate", {
  description="Workshop Baseplate", tiles={"brickcraft_baseplate.png"},
  groups={}, diggable=false, is_ground_content=false,
})
C.register_tool("brickcraft:separator", {
  description="Brick Separator\nLeft click: collect a brick\nRight click: turn a placed brick",
  inventory_image="brickcraft_separator.png", wield_image="brickcraft_separator.png",
  range=7, tool_capabilities={full_punch_interval=.2,groupcaps={brick={times={[1]=.15},uses=0,maxlevel=1}}},
  on_use=function(stack,user,pointed)
    if pointed.type=="node" then collect(pointed.under,C.get_node(pointed.under),user) end
    return stack
  end,
  on_place=function(stack,user,pointed)
    if pointed.type=="node" then turn_placed(pointed.under,C.get_node(pointed.under),user) end
    return stack
  end,
  on_drop=function(stack,dropper) turn_next(dropper); return stack end,
})

-- The workshop's own pieces at x, z -24..24 and y -1..4, relative to its center:
-- base is the baseplate's content id, ids the colors'. nil where it is air.
local function workshop_node(x,y,z,base,ids)
  local id=nil
  if y== -1 then id=base end
  -- Eight finite collection stacks behind the workshop.
  for i=1,8 do
    local cx=-18+(i-1)*5
    if math.abs(x-cx)<=1 and z>=10 and z<=12 and y>=0 and y<=2 then id=ids[i] end
  end
  -- A small open arch and a welcoming mosaic.
  if z== -7 and ((math.abs(x)==4 and y<=2 and y>=0) or (math.abs(x)<=4 and y==3)) then
    id=ids[y==3 and 2 or 1]
  end
  if z>= -8 and z<= -5 and math.abs(x)<=3 and y== -1 then id=ids[(x-z)%8+1] end
  return id
end
local function workshop_ids()
  local ids={}
  for i,color in ipairs(colors) do ids[i]=C.get_content_id("brickcraft:"..color) end
  return C.get_content_id("brickcraft:baseplate"),ids
end

-- Deterministic generation runs only for new mapblocks: saved construction wins.
-- Only the shared workshop at the origin is generated; worlds players make are built
-- when they are made (make_world).
C.register_on_generated(function(minp,maxp)
  if minp.y>4 or maxp.y< -1 or minp.x>24 or maxp.x< -24 or minp.z>24 or maxp.z< -24 then return end
  local vm,emin,emax=C.get_mapgen_object("voxelmanip")
  local area=VoxelArea:new({MinEdge=emin,MaxEdge=emax})
  local data=vm:get_data()
  local base,ids=workshop_ids()
  for z=math.max(minp.z,-24),math.min(maxp.z,24) do
    for x=math.max(minp.x,-24),math.min(maxp.x,24) do
      for y=math.max(minp.y,-1),math.min(maxp.y,4) do
        local id=workshop_node(x,y,z,base,ids)
        if id then data[area:index(x,y,z)]=id end
      end
    end
  end
  vm:set_data(data); vm:write_to_map()
end)

-- Scenery around the workshop is harvestable: each cell is one brick of its color.
-- The nodes stay plain cubes (cheap to draw across the hills) and keep their saved names;
-- what the separator collects is an ordinary brick. A gray baseplate floor at y -2
-- stays put under the hills, so digging the green ground never opens a hole to the void.
for _, n in ipairs({
  {"grass","Grass","green",{"brickcraft_grass.png","brickcraft_dirt.png","brickcraft_grass_side.png"}},
  {"dirt","Dirt","tan",{"brickcraft_dirt.png"}},
  {"trunk","Tree Trunk","brown",{"brickcraft_trunk_top.png","brickcraft_trunk_top.png","brickcraft_trunk.png"}},
  {"leaves","Leaves","green",{"brickcraft_leaves.png"}},
}) do
  C.register_node("brickcraft:"..n[1], {description=n[2].."\nCollect for a "..n[3].." brick", tiles=n[4],
    groups={brick=1, scenery=1, not_in_creative_inventory=1}, drop="brickcraft:"..n[3],
    brickcraft_scenery=true, is_ground_content=false, on_dig=collect})
end

-- The landscape is written once per world after its area loads, so worlds created
-- before hills existed get them too. Only air is filled: saved builds always win.
-- v1: hills and trees. v2: protected floor under them, added alone to v1 worlds so
-- nothing harvested grows back.
local LANDSCAPE_VERSION, EDGE = 2, 46 -- saved worlds only have map blocks to about ±48
local function noise(x,z) return (math.sin(x*12.9898+z*78.233)*43758.5453)%1 end
local function hill_height(x,z)
  local d=math.max(math.abs(x),math.abs(z))-27 -- 3-node flat grass ring past the baseplate
  if d<=0 then return -1 end
  local h=d*.55+2.5*math.sin(x*.21)+2*math.cos(z*.17)+1.5*math.sin((x+z)*.11)
  return math.max(-1,math.min(18,math.floor(h)-1))
end
-- c is the world's center (the workshop's is the origin); with core, the workshop's
-- baseplate, stacks, arch and mosaic are written too, for a world made in play.
local function build_landscape(from,c,core)
  c=c or {x=0,z=0}
  local minp,maxp={x=c.x-EDGE,y=-2,z=c.z-EDGE},{x=c.x+EDGE,y=26,z=c.z+EDGE}
  local vm=C.get_voxel_manip()
  local emin,emax=vm:read_from_map(minp,maxp)
  local area=VoxelArea:new({MinEdge=emin,MaxEdge=emax})
  local data=vm:get_data()
  local air=C.get_content_id("air")
  local grass,dirt=C.get_content_id("brickcraft:grass"),C.get_content_id("brickcraft:dirt")
  local trunk,leaves=C.get_content_id("brickcraft:trunk"),C.get_content_id("brickcraft:leaves")
  local floor=C.get_content_id("brickcraft:baseplate")
  -- x and z are relative to the center.
  local function put(x,y,z,id)
    if math.abs(x)>EDGE or math.abs(z)>EDGE or y>maxp.y then return end
    local i=area:index(c.x+x,y,c.z+z)
    if data[i]==air then data[i]=id end
  end
  if core then
    local base,ids=workshop_ids()
    for z=-24,24 do for x=-24,24 do for y=-1,4 do
      local id=workshop_node(x,y,z,base,ids)
      if id then put(x,y,z,id) end
    end end end
  end
  for z=-EDGE,EDGE do
    for x=-EDGE,EDGE do
      if math.max(math.abs(x),math.abs(z))>24 then
        put(x,-2,z,floor)
        if from<1 then
          local top=hill_height(x,z)
          for y=-1,top do put(x,y,z,y==top and grass or dirt) end
        end
      end
    end
  end
  if from>=1 then vm:set_data(data); vm:write_to_map(true); return end
  -- Trees on a loose 3-node grid, kept off the baseplate and the steep outer ridge.
  for z=-EDGE+3,EDGE-3,3 do
    for x=-EDGE+3,EDGE-3,3 do
      local r=noise(x,z)
      if math.max(math.abs(x),math.abs(z))>=27 and r<.3 then
        local base=hill_height(x,z)+1
        local h=3+math.floor(noise(z,x)*2)
        for y=base,base+h-1 do put(x,y,z,trunk) end
        for dy=h-2,h do
          local rad=dy==h and 1 or 2
          for dz=-rad,rad do
            for dx=-rad,rad do
              if math.abs(dx)+math.abs(dz)<rad*2 or rad==1 then put(x+dx,base+dy,z+dz,leaves) end
            end
          end
        end
      end
    end
  end
  vm:set_data(data); vm:write_to_map(true)
end
local storage=C.get_mod_storage()
C.after(0,function()
  local from=storage:get_int("landscape_version")
  if from>=LANDSCAPE_VERSION then return end
  C.emerge_area({x=-EDGE,y=-2,z=-EDGE},{x=EDGE,y=26,z=EDGE},function(_,_,remaining)
    if remaining>0 then return end
    build_landscape(from)
    storage:set_int("landscape_version",LANDSCAPE_VERSION)
    C.log("action","BrickCraft landscape v"..LANDSCAPE_VERSION.." built")
  end)
end)

-- Worlds: the shared Workshop at the origin, plus worlds players make. Each is a fresh
-- copy of the workshop with its own hills, in its own square of the one map, SPACING
-- apart so their hills (±EDGE) never meet. Saved in mod storage as
-- {id, name, owner (player id), x, z (center), built}.
local SPACING=128
local WORKSHOP={id=0,name="Workshop",x=0,z=0,built=true}
local worlds=C.deserialize(storage:get_string("worlds")) or {}
local function save_worlds() storage:set_string("worlds",C.serialize(worlds)) end
local function world_by_id(id)
  if id==0 then return WORKSHOP end
  for _,w in ipairs(worlds) do if w.id==id then return w end end
end
-- The world whose square holds pos; the Workshop for squares no world uses.
local function world_at(pos)
  local x,z=math.floor(pos.x/SPACING+.5)*SPACING,math.floor(pos.z/SPACING+.5)*SPACING
  for _,w in ipairs(worlds) do if w.x==x and w.z==z and w.built then return w end end
  return WORKSHOP
end
-- Squares in rings around the workshop, as far as the map reaches (mapgen_limit; worlds
-- made before worlds existed had 64, which the launchers raise).
local function free_center()
  local limit=tonumber(C.get_mapgen_setting("mapgen_limit")) or 31007
  local used={}
  for _,w in ipairs(worlds) do used[w.x..","..w.z]=true end
  for r=1,math.floor((limit-EDGE-16)/SPACING) do
    for gz=-r,r do for gx=-r,r do
      local x,z=gx*SPACING,gz*SPACING
      if math.max(math.abs(gx),math.abs(gz))==r and not used[x..","..z] then return {x=x,z=z} end
    end end
  end
end
local function build_world(w,done)
  local c={x=w.x,z=w.z}
  C.emerge_area({x=c.x-EDGE,y=-2,z=c.z-EDGE},{x=c.x+EDGE,y=26,z=c.z+EDGE},function(_,_,remaining)
    if remaining>0 then return end
    build_landscape(0,c,true)
    w.built=true; save_worlds()
    C.log("action","BrickCraft world "..w.id.." ("..w.name..") built at "..c.x..","..c.z)
    if done then done(w) end
  end)
end
-- Makes a world for owner; done(world) runs once it is built. nil when the map is full.
local function make_world(name,owner,done)
  local c=free_center()
  if not c then return nil end
  local id=1
  for _,w in ipairs(worlds) do id=math.max(id,w.id+1) end
  local w={id=id,name=name,owner=owner,x=c.x,z=c.z,built=false}
  worlds[#worlds+1]=w; save_worlds()
  build_world(w,done)
  return w
end
-- A world left half-built by a shutdown is finished on the next start.
C.after(0,function()
  for _,w in ipairs(worlds) do if not w.built then build_world(w) end end
end)

local function welcome(player)
  C.show_formspec(player:get_player_name(),"brickcraft:welcome",
    "formspec_version[6]size[10,7.6]bgcolor[#142936;true]"..
    "label[.6,.6;BRICKCRAFT / BUILD TOGETHER]"..
    "textarea[.6,1.3;8.8,5.4;;Welcome to your brick workshop!;"..
    C.formspec_escape("WASD / arrows: move    Mouse: look    Space: jump\n1: orange separator / left click to collect\n2–9, 0, -, = / B, N / wheel: choose a color / right click to place\nTab / E: next piece    Q: turn    U: undo\nSeparator right click: turn a placed brick\nI: inventory    C: see your brick person    ?: all keys\nEsc: pause / Quit to Menu saves and closes world\n\nCollect the colored stacks, trees and hills, then build a tiny home!\n/home takes you back to the start of your world.")..
    "]button_exit[1.2,6.7;3.6,.6;go;Let's build!]button[5.2,6.7;3.6,.6;help;Keys and commands]")
end
-- One list feeds the help screen; keep it in sync with the controls above.
local help_rows={
  {"MOVE",""},
  {"W A S D or arrows","Walk"},{"Mouse","Look around"},{"Space","Jump"},{"C","1st / 3rd person camera"},
  {"BUILD",""},
  {"1","Orange separator"},{"Left click (separator)","Collect a brick"},
  {"Right click (separator)","Turn a placed brick"},
  {"2 – 9 / mouse wheel","Choose a color"},{"0  -  =","Harvested green, brown, tan"},{"B / N","Previous / next hotbar slot (no wheel needed)"},{"Right click (color)","Place a brick"},
  {"F or Control+click","Same as right click (trackpad)"},
  {"E or Tab","Next piece"},{"Q","Turn the next brick 90°"},
  {"Left click tree / hill","Harvest a green, brown or tan brick"},{"U or I > Undo","Undo your last build action"},
  {"MENUS",""},
  {"?","This help screen"},
  {"I","Inventory and shape buttons"},{"T","Chat (type a command)"},
  {"Esc","Pause / Exit to Menu saves the world"},{"F1 / F2","Hide HUD / chat"},
  {"COMMANDS",""},
  {"/keys","This help screen"},{"/guide","Welcome screen"},{"/home","Back to the start of this world"},
  {"/world","Go to another world or make a new one"},
  {"/undo","Undo your last build action"},
  {"/shape slope_2x2","Pick a piece by name (/shape lists them)"},
}
local function show_help(player)
  local cells={}
  for _,row in ipairs(help_rows) do
    local heading=row[2]==""
    cells[#cells+1]=heading and "#f5872c" or "#ffffff"
    cells[#cells+1]=C.formspec_escape(row[1])
    cells[#cells+1]=C.formspec_escape(row[2])
  end
  C.show_formspec(player:get_player_name(),"brickcraft:help",
    "formspec_version[6]size[11,9.4]bgcolor[#142936;true]"..
    "label[.6,.6;BRICKCRAFT / KEYS AND COMMANDS]"..
    "tablecolumns[color;text,width=14;text]"..
    "table[.6,1.1;9.8,7.2;keys;"..table.concat(cells,",")..";0]"..
    "button_exit[3.7,8.5;3.6,.6;close;Back to building]")
end
-- The family's players, each with a block-person look; the nametag shows the name in
-- the look's color. Players are chosen in the game window ("Who's playing?").
local styles={
  {id="builder",label="Builder",mesh="brickcraft_person.obj",tex="brickcraft_person.png",
   tag="#8fd0ff",swatch={"#4aa1d9","#304c6e","#232630"}},
  {id="dad",label="Dad",mesh="brickcraft_person_short.obj",tex="brickcraft_person_dad.png",
   tag="#a9c4e8",swatch={"#304c6e","#464a54","#3e2c20"}},
  {id="daughter",label="Leona",mesh="brickcraft_person_long.obj",tex="brickcraft_person_daughter.png",
   tag="#ffb3cf",swatch={"#e583a5","#9774cb","#6e4228"}},
  {id="explorer",label="Explorer",mesh="brickcraft_person_short.obj",tex="brickcraft_person_explorer.png",
   tag="#9ee6c6",swatch={"#4ab793","#eee5c7","#e8be5c"}},
}
local style_by_id={}
for _,st in ipairs(styles) do style_by_id[st.id]=st end
local function get_style(player)
  return style_by_id[player:get_meta():get_string("brickcraft_style")] or styles[1]
end
-- Each player's bricks live in mod storage, not with the connection, so any computer
-- can play as anyone. The connection name only tells computers apart. A connection
-- holds the bricks of the player it plays as; they are saved back on switch and leave.
local pstore=C.get_mod_storage()
local function playing_as(player)
  local meta=player:get_meta()
  local id=meta:get_string("brickcraft_profile")
  -- Connections from before the picker own the bricks of the look they chose.
  if id=="" and meta:get_int("brickcraft_style_chosen")==1 then id=meta:get_string("brickcraft_style") end
  return style_by_id[id] and id or nil
end
-- Chat shows who's playing ("<Dad> hi") in their nametag color, not the computer's
-- connection name. Connections still at "Who's playing?" keep the connection name.
local format_chat=C.format_chat_message
function C.format_chat_message(name,message)
  local p=C.get_player_by_name(name)
  local st=p and style_by_id[playing_as(p) or ""]
  return format_chat(st and C.colorize(st.tag,st.label) or name,message)
end
local function save_bricks(player)
  local id=playing_as(player)
  if not id then return end
  local items={}
  for i,stack in ipairs(player:get_inventory():get_list("main")) do items[i]=stack:to_string() end
  pstore:set_string("bricks_"..id,C.serialize(items))
end
local function load_bricks(player,id)
  local saved=pstore:get_string("bricks_"..id)
  if saved=="" then return false end
  saved=C.deserialize(saved) or {}
  local inv=player:get_inventory()
  for i=1,inv:get_size("main") do inv:set_stack("main",i,saved[i] or "") end
  return true
end
local function give_starter(inv)
  inv:set_list("main",{})
  inv:set_stack("main",1,"brickcraft:separator")
  for i=1,STARTER_COLORS do inv:set_stack("main",i+1,"brickcraft:"..colors[i].." 24") end
end
local function taken_by(player,id)
  for _,p in ipairs(C.get_connected_players()) do
    if p~=player and playing_as(p)==id then return p end
  end
end
local function apply_style(player)
  local st=get_style(player)
  player:set_properties({visual="mesh",mesh=st.mesh,textures={st.tex},
    visual_size={x=10,y=10},collisionbox={-.3,0,-.3,.3,1.75,.3},eye_height=1.5,zoom_fov=0})
  player:set_nametag_attributes({color=st.tag,bgcolor="#14293699",
    text=playing_as(player) and st.label or player:get_player_name()})
end
-- Returns true when the player was switched; false when someone else already plays them.
local function choose_player(player,st)
  local name=player:get_player_name()
  if taken_by(player,st.id) then
    C.chat_send_player(name,st.label.." is already playing on another computer. Pick someone else.")
    return false
  end
  local current=playing_as(player)
  local fresh=false
  if current~=st.id then
    save_bricks(player)
    if not load_bricks(player,st.id) then
      -- A player's first time: a new connection keeps the starter kit it just got,
      -- a switch from another player starts with a fresh kit.
      if current then give_starter(player:get_inventory()) end
      fresh=true
    end
    history[name]=nil -- an undo must not move bricks between players
  end
  local meta=player:get_meta()
  meta:set_string("brickcraft_profile",st.id); meta:set_string("brickcraft_style",st.id)
  meta:set_int("brickcraft_style_chosen",1)
  apply_style(player)
  return true,fresh
end
local function show_style_picker(player)
  local current=playing_as(player)
  local fs="formspec_version[6]size[11,6.4]bgcolor[#142936;true]"..
    "label[.6,.6;BRICKCRAFT / WHO'S PLAYING?]"..
    "label[.6,1.1;"..C.formspec_escape("Pick yourself. Your bricks and look come with you on any computer.").."]"
  for i,st in ipairs(styles) do
    local x=.6+(i-1)*2.55
    local other=taken_by(player,st.id)
    -- Hair (or cap), shirt and pants swatches stacked like the figure.
    fs=fs.."box["..(x+.6)..",1.7;1.1,.5;"..st.swatch[3].."]"..
      "box["..(x+.6)..",2.2;1.1,1;"..st.swatch[1].."]"..
      "box["..(x+.6)..",3.2;1.1,.9;"..st.swatch[2].."]"..
      "style[style_"..st.id..";bgcolor="..(st.id==current and "#f5872c" or other and "#24343d" or "#3a5566").."]"..
      "button["..x..",4.4;2.3,.7;style_"..st.id..";"..st.label.."]"
    if other then fs=fs.."label["..(x+.35)..",5.3;(playing)]" end
  end
  C.show_formspec(player:get_player_name(),"brickcraft:style",fs..
    "label[.6,5.9;Switch later: I > Switch player, or /player]")
end

-- Each new player gets their own free spot so friends don't spawn inside each other.
local spots={{x=0,z=4},{x=-3,z=4},{x=3,z=4},{x=-6,z=4},{x=6,z=4},{x=-3,z=1},{x=3,z=1},{x=0,z=1}}
-- The spot is the same in every world, around that world's center.
local function home_pos(player,world)
  local w=world or world_at(player:get_pos())
  local s=spots[player:get_meta():get_int("brickcraft_spot")] or spots[1]
  return {x=w.x+s.x,y=2,z=w.z+s.z}
end
local function claim_spot(player)
  local used={}
  for _,p in ipairs(C.get_connected_players()) do
    if p~=player then used[p:get_meta():get_int("brickcraft_spot")]=true end
  end
  for i=1,#spots do
    if not used[i] then player:get_meta():set_int("brickcraft_spot",i); return end
  end
  player:get_meta():set_int("brickcraft_spot",1)
end

-- "Which world?" comes right after "Who's playing?": go to the Workshop or any world
-- someone made, or make a new one. Each player's last world is picked to start with.
local picker_ids,picked,welcome_after={},{},{}
local function owner_label(w)
  if w.id==0 then return "everyone" end
  return style_by_id[w.owner] and style_by_id[w.owner].label or w.owner
end
local function new_world_name(player)
  local id=playing_as(player)
  local who=id and style_by_id[id].label or player:get_player_name()
  local n=1
  for _,w in ipairs(worlds) do if w.owner==(id or who) then n=n+1 end end
  return who.."'s World"..(n>1 and " "..n or "")
end
local function show_world_picker(player)
  local name=player:get_player_name()
  local here=world_at(player:get_pos())
  local last=tonumber(pstore:get_string("world_"..(playing_as(player) or name)))
  local counts={}
  for _,p in ipairs(C.get_connected_players()) do
    local w=world_at(p:get_pos()).id; counts[w]=(counts[w] or 0)+1
  end
  if not world_by_id(picked[name] or -1) then picked[name]=world_by_id(last or -1) and last or here.id end
  local ids,items,sel={},{},1
  for i=0,#worlds do
    local w=i==0 and WORKSHOP or worlds[i]
    if w.built then
      ids[#ids+1]=w.id
      if w.id==picked[name] then sel=#ids end
      local n=counts[w.id] or 0
      items[#items+1]=(w.id==0 and "#f5872c" or "")..C.formspec_escape(w.name.."  ("..owner_label(w)..")"..
        (n>0 and "   "..n.." here" or "")..(w==here and "   < you are here" or ""))
    end
  end
  picker_ids[name]=ids
  local who=playing_as(player)
  C.show_formspec(name,"brickcraft:world","formspec_version[6]size[11,8.2]bgcolor[#142936;true]"..
    "label[.6,.6;BRICKCRAFT / WHICH WORLD?]"..
    "label[.6,1.1;"..C.formspec_escape((who and style_by_id[who].label..", g" or "G")..
      "o to a world, or make a new one of your own.").."]"..
    "textlist[.6,1.5;9.8,3.6;world;"..table.concat(items,",")..";"..sel..";false]"..
    "style[go;bgcolor=#f5872c]button[.6,5.3;4.6,.7;go;Go to this world]"..
    "field[.6,6.6;6.4,.7;name;New world;"..C.formspec_escape(new_world_name(player)).."]"..
    "field_close_on_enter[name;false]button[7.2,6.6;3.2,.7;new;Make new world]"..
    "label[.6,7.7;Switch later: I > Switch world, or /world]")
end
local function after_world(player)
  local name=player:get_player_name()
  if welcome_after[name] then welcome_after[name]=nil; welcome(player)
  else C.close_formspec(name,"brickcraft:world") end
end
-- Staying in the world you are already in keeps your place; another world starts at your spot.
local function enter_world(player,w)
  pstore:set_string("world_"..(playing_as(player) or player:get_player_name()),tostring(w.id))
  if world_at(player:get_pos())~=w then
    player:set_pos(home_pos(player,w)); player:set_look_horizontal(0)
  end
end
local function new_world(player,title)
  local name=player:get_player_name()
  title=(title or ""):gsub("[%c,;#%[%]\\]",""):gsub("^%s+",""):gsub("%s+$",""):sub(1,30)
  if title=="" then title=new_world_name(player) end
  local w=make_world(title,playing_as(player) or name,function(w)
    local p=C.get_player_by_name(name)
    if not p then return end
    enter_world(p,w)
    C.chat_send_player(name,"Welcome to "..w.name.."! Your own fresh workshop. /world goes back.")
  end)
  if not w then C.chat_send_player(name,"There's no room for another world on this map."); return false end
  C.chat_send_player(name,"Making "..w.name.."...")
  return true
end

function inventory_formspec(player)
  local current=get_shape(player)
  local fs="formspec_version[6]size[10.8,11.2]label[.4,.4;BRICKCRAFT / YOUR BRICKS   (Tab or E: next piece)]"
  -- One row per piece family; the tooltip names the real catalog part.
  local rows,order={}, {}
  for _,s in ipairs(shapes) do
    if not rows[s.group] then rows[s.group]={}; order[#order+1]=s.group end
    table.insert(rows[s.group],s)
  end
  for r,group in ipairs(order) do
    local y=.8+(r-1)*.8
    fs=fs.."label[.4,"..(y+.3)..";"..C.formspec_escape(group).."]"
    for i,s in ipairs(rows[group]) do
      local x=2.2+(i-1)*2.1
      fs=fs.."style[shape_"..s.id..";bgcolor="..(s==current and "#f5872c" or "#3a5566").."]"..
        "button["..x..","..y..";2,.6;shape_"..s.id..";"..
        C.formspec_escape((s.label:gsub("^Brick ",""):gsub("^Plate ",""):gsub("^Round Brick","Round")
          :gsub("^Inverted Slope 45","Inverted"):gsub("^Slope 45","Slope"))).."]"..
        "tooltip[shape_"..s.id..";"..C.formspec_escape(s.label.." - part "..s.part.." - uses "..s.cost.." brick"..(s.cost>1 and "s" or "")).."]"
    end
  end
  return fs.."list[current_player;main;.4,4.1;8,4;]"..
    "label[.4,9.3;1: Separator | 2-9 0 - =, wheel: Colors | Right click or F: Build | Q: Turn | U: Undo]"..
    "label[.4,9.8;2 x 4 pieces use 2 bricks of their color. The others use 1.]listring[current_player;main]"..
    "style[undo;bgcolor=#f5872c]button[.4,10.2;2.4,.6;undo;Undo last action]"..
    "button[2.95,10.2;2.4,.6;look;Switch player]button[5.5,10.2;2.4,.6;world;Switch world]"..
    "button[8.05,10.2;2.4,.6;help;Help: all keys]"
end
C.register_on_player_receive_fields(function(player,formname,fields)
  if formname=="brickcraft:welcome" and fields.help then show_help(player); return true end
  if formname=="brickcraft:style" then
    for _,st in ipairs(styles) do
      if fields["style_"..st.id] then
        local ok,fresh=choose_player(player,st)
        if not ok then show_style_picker(player)
        elseif testing then C.close_formspec(player:get_player_name(),formname)
        else
          -- A player's first time is followed by the welcome, after picking a world.
          welcome_after[player:get_player_name()]=fresh or nil
          picked[player:get_player_name()]=nil
          show_world_picker(player)
        end
      end
    end
    return true
  end
  if formname=="brickcraft:world" then
    local name=player:get_player_name()
    local ev=fields.world and C.explode_textlist_event(fields.world)
    if ev and ev.type~="INV" then picked[name]=(picker_ids[name] or {})[ev.index] end
    if fields.go or (ev and ev.type=="DCL") then
      local w=world_by_id(picked[name] or 0)
      if w then enter_world(player,w) end
      after_world(player)
    elseif fields.new or fields.key_enter_field=="name" then
      if new_world(player,fields.name) then after_world(player) end
    elseif fields.quit then
      if welcome_after[name] then after_world(player) end
    end
    return true
  end
  if formname~="" then return end
  if fields.undo then undo_last(player); return true end
  if fields.help then show_help(player); return true end
  if fields.look then show_style_picker(player); return true end
  if fields.world then picked[player:get_player_name()]=nil; show_world_picker(player); return true end
  for _,s in ipairs(shapes) do
    if fields["shape_"..s.id] then set_shape(player,s); return true end
  end
end)
C.register_on_joinplayer(function(player)
  local inv=player:get_inventory(); inv:set_size("main",32)
  -- 1 separator + 8 starter colors + 3 slots for harvested green/brown/tan bricks.
  player:hud_set_hotbar_itemcount(12)
  player:set_inventory_formspec(inventory_formspec(player))
  apply_style(player)
  player:set_sky({base_color="#93cddd",type="regular",clouds=true})
  player:set_sun({visible=true}); player:set_moon({visible=false})
  player:hud_add({type="text",position={x=.5,y=0},offset={x=0,y=28},
    text="BRICKCRAFT   |   1 Collect   2-9 0 - = Colors   Right click Build   Tab Piece   Q Turn   U Undo   ? Help",number=0xffffff,alignment={x=0,y=0},scale={x=100,y=20}})
  update_hud(player)
  if player:get_meta():get_int("brickcraft_started")==0 then
    give_starter(inv)
    player:get_meta():set_int("brickcraft_started",1)
    claim_spot(player)
    player:set_pos(home_pos(player)); player:set_look_horizontal(0)
  end
  -- Every start asks who is playing; a player's first time is followed by the welcome.
  if not testing then show_style_picker(player) end
  C.set_timeofday(.48)
end)
C.register_on_leaveplayer(function(player)
  save_bricks(player)
  local name=player:get_player_name()
  hud[name]=nil; held[name]=nil; history[name]=nil
end)
C.register_on_shutdown(function()
  for _,p in ipairs(C.get_connected_players()) do save_bricks(p) end
end)
C.register_on_respawnplayer(function(player) player:set_pos(home_pos(player)); return true end)
C.register_chatcommand("home",{description="Back to the start of this world",func=function(name)
  local p=C.get_player_by_name(name); if p then p:set_pos(home_pos(p)) end
  return true,"Welcome home!"
end})
C.register_chatcommand("guide",{description="Show BrickCraft controls",func=function(name)
  local p=C.get_player_by_name(name); if p then welcome(p) end
  return true
end})
for _,cmd in ipairs({"player","look"}) do
  C.register_chatcommand(cmd,{description="Choose who is playing on this computer",func=function(name)
    local p=C.get_player_by_name(name); if p then show_style_picker(p) end
    return true
  end})
end
C.register_chatcommand("world",{description="Go to another world or make a new one",func=function(name)
  local p=C.get_player_by_name(name)
  if p then picked[name]=nil; show_world_picker(p) end
  return true
end})
C.register_chatcommand("who",{description="List the builders here",func=function()
  local names={}
  for _,p in ipairs(C.get_connected_players()) do
    local id=playing_as(p)
    names[#names+1]=(id and style_by_id[id].label or "Not picked yet").." (on "..p:get_player_name()..
      ", in "..world_at(p:get_pos()).name..")"
  end
  return true,"Builders here: "..table.concat(names,", ")
end})
C.register_chatcommand("keys",{description="Show every BrickCraft key and command",func=function(name)
  local p=C.get_player_by_name(name); if p then show_help(p) end
  return true
end})
C.register_chatcommand("undo",{description="Undo your last build action",func=function(name)
  local p=C.get_player_by_name(name)
  if not p then return false,"Player is not connected." end
  return undo_last(p)
end})
C.register_chatcommand("shape",{params="<piece>",description="Choose the piece to build with",
  func=function(name,param)
    local p,s=C.get_player_by_name(name),shape_by_id[param]
    if not s then
      local ids={}
      for _,sh in ipairs(shapes) do ids[#ids+1]=sh.id end
      return false,"Pieces: "..table.concat(ids,", ")
    end
    if p then set_shape(p,s) end
    return true,"Shape: "..s.label
  end})
local elapsed=0
-- Key presses the server can see: E or Tab (aux1, fast movement is off) picks the next
-- piece, U (sneak) undoes, and the ?/ key (zoom with zoom_fov 0) opens help.
local key_actions={
  aux1=function(p) set_shape(p,shapes[get_shape(p).index%#shapes+1]) end,
  sneak=undo_last,
  zoom=show_help,
}
C.register_globalstep(function(dt)
  for _,p in ipairs(C.get_connected_players()) do
    local name,ctrl=p:get_player_name(),p:get_player_control()
    held[name]=held[name] or {}
    for key,action in pairs(key_actions) do
      if ctrl[key] and not held[name][key] then action(p) end
      held[name][key]=ctrl[key]
    end
  end
  elapsed=elapsed+dt; if elapsed<1 then return end; elapsed=0
  for _,p in ipairs(C.get_connected_players()) do
    if p:get_pos().y< -8 then p:set_pos(home_pos(p)) end
  end
end)

brickcraft={shapes=shape_by_id,shape_list=shapes,colors=colors,set_shape=set_shape,turn=turn_next,undo=undo_last,styles=style_by_id,
  get_style=get_style,home_pos=home_pos,playing_as=playing_as,world_at=world_at,worlds=function() return worlds end}

-- AI builders (one per player, and jms) live on the shared server (server.conf) only.
if C.settings:get_bool("brickcraft_ai_builder",false) then
  -- Luanti only hands out HTTP from init.lua's main scope (secure.http_mods = brickcraft).
  brickcraft.http=C.request_http_api and C.request_http_api()
  dofile(C.get_modpath("brickcraft").."/ai_builder.lua")
  if C.settings:get_bool("brickcraft_ai_test",false) then
    dofile(C.get_modpath("brickcraft").."/ai_test.lua")
  end
end
-- Opt-in integration checks execute actual engine callbacks, in a disposable world.
if C.settings:get_bool("brickcraft_integration_test",false) then
  dofile(C.get_modpath("brickcraft").."/integration.lua")
end
if C.settings:get_bool("brickcraft_multiplayer_test",false) then
  dofile(C.get_modpath("brickcraft").."/multiplayer_test.lua")
end
if C.settings:get_bool("brickcraft_house_test",false) then
  dofile(C.get_modpath("brickcraft").."/house_test.lua")
end
