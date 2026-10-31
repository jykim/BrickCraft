local C = core
-- Automated checks skip the welcome and look pickers.
local testing = C.settings:get_bool("brickcraft_integration_test",false) or
  C.settings:get_bool("brickcraft_multiplayer_test",false) or C.settings:get_bool("brickcraft_house_test",false)
local colors = {"coral", "gold", "mint", "sky", "violet", "cream", "navy", "rose"}
local labels = {"Coral", "Gold", "Mint", "Sky", "Violet", "Cream", "Navy", "Rose"}
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
  {id="plate", suffix="_plate", label="Plate 2 x 2", part="3022", group="Plates", cost=1,
   boxes=plate(.5,.5,{-.25,.25},{-.25,.25}),
   collision={-.5,-.5,-.5,.5,PLATE_TOP,.5}},
  {id="plate_1x2", suffix="_plate_1x2", label="Plate 1 x 2", part="3023", group="Plates", cost=1,
   boxes=plate(0,.5,{-.25},{-.25,.25}),
   collision={-.5,-.5,-.5,0,PLATE_TOP,.5}},
  {id="plate_2x4", suffix="_plate_2x4", label="Plate 2 x 4", part="3020", group="Plates", cost=2, long=true,
   boxes=plate(.5,1.5,{-.25,.25},{-.25,.25,.75,1.25}),
   collision={-.5,-.5,-.5,.5,PLATE_TOP,.5}},
  {id="round_2x2", suffix="_round_2x2", label="Round Brick 2 x 2", part="3941", group="Round & Slopes", cost=1,
   mesh="brickcraft_round_2x2.obj"},
  {id="slope_2x2", suffix="_slope_2x2", label="Slope 45 2 x 2", part="3039", group="Round & Slopes", cost=1,
   mesh="brickcraft_slope_2x2.obj",
   collision={{-.5,-.5,-.5,.5,0,.5},{-.5,0,0,.5,.5,.5}}},
  {id="slope_2x1", suffix="_slope_2x1", label="Slope 45 2 x 1", part="3040", group="Round & Slopes", cost=1,
   mesh="brickcraft_slope_2x1.obj",
   collision={{-.5,-.5,-.5,0,0,.5},{-.5,0,0,0,.5,.5}}},
}
local shape_by_id = {}
for i, s in ipairs(shapes) do s.index=i; shape_by_id[s.id]=s end

local function get_shape(player)
  return shape_by_id[player:get_meta():get_string("brickcraft_shape")] or shapes[1]
end
local function get_turn(player) return player:get_meta():get_int("brickcraft_turn")%4 end

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
  return C.node_dig(pos,node,player)
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
  return stack
end

-- Separator right click turns a placed brick a quarter turn in place.
local function turn_placed(pos,node,player)
  pos,node=primary_of(pos,node)
  local def=C.registered_nodes[node.name]
  if not def or C.get_item_group(node.name,"brick")~=1 then return end
  local param2=(node.param2+1)%4
  if def.brickcraft_long then
    local old,new=tail_pos(pos,node.param2),tail_pos(pos,param2)
    if not is_free(new) then
      C.chat_send_player(player:get_player_name(),"No room to turn this long piece.")
      return
    end
    C.set_node(new,{name=node.name.."_tail",param2=param2})
    C.remove_node(old)
  end
  C.swap_node(pos,{name=node.name,param2=param2})
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

-- Deterministic generation runs only for new mapblocks: saved construction wins.
C.register_on_generated(function(minp,maxp)
  if minp.y>4 or maxp.y< -1 or minp.x>24 or maxp.x< -24 or minp.z>24 or maxp.z< -24 then return end
  local vm,emin,emax=C.get_mapgen_object("voxelmanip")
  local area=VoxelArea:new({MinEdge=emin,MaxEdge=emax})
  local data=vm:get_data()
  local base=C.get_content_id("brickcraft:baseplate")
  local ids={}
  for i,color in ipairs(colors) do ids[i]=C.get_content_id("brickcraft:"..color) end
  for z=math.max(minp.z,-24),math.min(maxp.z,24) do
    for x=math.max(minp.x,-24),math.min(maxp.x,24) do
      for y=math.max(minp.y,-1),math.min(maxp.y,4) do
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
        if id then data[area:index(x,y,z)]=id end
      end
    end
  end
  vm:set_data(data); vm:write_to_map()
end)

-- Scenery around the workshop: fixed, not collectable, so brick counts stay unchanged.
for _, n in ipairs({
  {"grass","Grass",{"brickcraft_grass.png","brickcraft_dirt.png","brickcraft_grass_side.png"}},
  {"dirt","Dirt",{"brickcraft_dirt.png"}},
  {"trunk","Tree Trunk",{"brickcraft_trunk_top.png","brickcraft_trunk_top.png","brickcraft_trunk.png"}},
  {"leaves","Leaves",{"brickcraft_leaves.png"}},
}) do
  C.register_node("brickcraft:"..n[1], {description=n[2], tiles=n[3], groups={scenery=1},
    diggable=false, is_ground_content=false})
end

-- The landscape is written once per world after its area loads, so worlds created
-- before hills existed get them too. Only air is filled: saved builds always win.
local LANDSCAPE_VERSION, EDGE = 1, 46 -- saved worlds only have map blocks to about ±48
local function noise(x,z) return (math.sin(x*12.9898+z*78.233)*43758.5453)%1 end
local function hill_height(x,z)
  local d=math.max(math.abs(x),math.abs(z))-27 -- 3-node flat grass ring past the baseplate
  if d<=0 then return -1 end
  local h=d*.55+2.5*math.sin(x*.21)+2*math.cos(z*.17)+1.5*math.sin((x+z)*.11)
  return math.max(-1,math.min(18,math.floor(h)-1))
end
local function build_landscape()
  local minp,maxp={x=-EDGE,y=-1,z=-EDGE},{x=EDGE,y=26,z=EDGE}
  local vm=C.get_voxel_manip()
  local emin,emax=vm:read_from_map(minp,maxp)
  local area=VoxelArea:new({MinEdge=emin,MaxEdge=emax})
  local data=vm:get_data()
  local air=C.get_content_id("air")
  local grass,dirt=C.get_content_id("brickcraft:grass"),C.get_content_id("brickcraft:dirt")
  local trunk,leaves=C.get_content_id("brickcraft:trunk"),C.get_content_id("brickcraft:leaves")
  local function put(x,y,z,id)
    if math.abs(x)>EDGE or math.abs(z)>EDGE or y>maxp.y then return end
    local i=area:index(x,y,z)
    if data[i]==air then data[i]=id end
  end
  for z=-EDGE,EDGE do
    for x=-EDGE,EDGE do
      if math.max(math.abs(x),math.abs(z))>24 then
        local top=hill_height(x,z)
        for y=-1,top do put(x,y,z,y==top and grass or dirt) end
      end
    end
  end
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
  if storage:get_int("landscape_version")>=LANDSCAPE_VERSION then return end
  C.emerge_area({x=-EDGE,y=-1,z=-EDGE},{x=EDGE,y=26,z=EDGE},function(_,_,remaining)
    if remaining>0 then return end
    build_landscape()
    storage:set_int("landscape_version",LANDSCAPE_VERSION)
    C.log("action","BrickCraft landscape v"..LANDSCAPE_VERSION.." built")
  end)
end)

local function welcome(player)
  C.show_formspec(player:get_player_name(),"brickcraft:welcome",
    "formspec_version[6]size[10,7.6]bgcolor[#142936;true]"..
    "label[.6,.6;BRICKCRAFT / BUILD TOGETHER]"..
    "textarea[.6,1.3;8.8,5.4;;Welcome to your brick workshop!;"..
    C.formspec_escape("WASD / arrows: move    Mouse: look    Space: jump\n1: orange separator / left click to collect\n2–9: choose a color / right click to place\nTab / E: next piece (Shift: back)    Q: turn\nSeparator right click: turn a placed brick\nI: inventory    C: see your brick person    ?: all keys\nEsc: pause / Quit to Menu saves and closes world\n\nCollect the colored stacks, then build a tiny home!\n/home returns you safely to the workshop.")..
    "]button_exit[1.2,6.7;3.6,.6;go;Let's build!]button[5.2,6.7;3.6,.6;help;Keys and commands]")
end
-- One list feeds the help screen; keep it in sync with the controls above.
local help_rows={
  {"MOVE",""},
  {"W A S D or arrows","Walk"},{"Mouse","Look around"},{"Space","Jump"},{"C","1st / 3rd person camera"},
  {"BUILD",""},
  {"1","Orange separator"},{"Left click (separator)","Collect a brick"},
  {"Right click (separator)","Turn a placed brick"},
  {"2 – 9","Choose a color"},{"Right click (color)","Place a brick"},
  {"F or Control+click","Same as right click (trackpad)"},
  {"E or Tab","Next piece (Shift: previous)"},{"Q","Turn the next brick 90°"},
  {"Mouse wheel","Next / previous hotbar slot"},
  {"MENUS",""},
  {"?","This help screen"},
  {"I","Inventory and shape buttons"},{"T","Chat (type a command)"},
  {"Esc","Pause / Exit to Menu saves the world"},{"F1 / F2","Hide HUD / chat"},
  {"COMMANDS",""},
  {"/keys","This help screen"},{"/guide","Welcome screen"},{"/home","Back to the workshop"},
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
-- Block-person looks; each player picks one, and the nametag takes its color.
local styles={
  {id="builder",label="Builder",mesh="brickcraft_person.obj",tex="brickcraft_person.png",
   tag="#8fd0ff",swatch={"#4aa1d9","#304c6e","#232630"}},
  {id="dad",label="Dad",mesh="brickcraft_person_short.obj",tex="brickcraft_person_dad.png",
   tag="#a9c4e8",swatch={"#304c6e","#464a54","#3e2c20"}},
  {id="daughter",label="Daughter",mesh="brickcraft_person_long.obj",tex="brickcraft_person_daughter.png",
   tag="#ffb3cf",swatch={"#e583a5","#9774cb","#6e4228"}},
  {id="explorer",label="Explorer",mesh="brickcraft_person_short.obj",tex="brickcraft_person_explorer.png",
   tag="#9ee6c6",swatch={"#4ab793","#eee5c7","#e8be5c"}},
}
local style_by_id={}
for _,st in ipairs(styles) do style_by_id[st.id]=st end
local function get_style(player)
  return style_by_id[player:get_meta():get_string("brickcraft_style")] or styles[1]
end
local function apply_style(player)
  local st=get_style(player)
  player:set_properties({visual="mesh",mesh=st.mesh,textures={st.tex},
    visual_size={x=10,y=10},collisionbox={-.3,0,-.3,.3,1.75,.3},eye_height=1.5,zoom_fov=0})
  player:set_nametag_attributes({color=st.tag,bgcolor="#14293699"})
end
local function show_style_picker(player)
  local current=get_style(player)
  local fs="formspec_version[6]size[11,6.4]bgcolor[#142936;true]"..
    "label[.6,.6;BRICKCRAFT / CHOOSE YOUR LOOK]"..
    "label[.6,1.1;"..C.formspec_escape("Hi "..player:get_player_name().."! Friends see this look and your name.").."]"
  for i,st in ipairs(styles) do
    local x=.6+(i-1)*2.55
    -- Hair (or cap), shirt and pants swatches stacked like the figure.
    fs=fs.."box["..(x+.6)..",1.7;1.1,.5;"..st.swatch[3].."]"..
      "box["..(x+.6)..",2.2;1.1,1;"..st.swatch[1].."]"..
      "box["..(x+.6)..",3.2;1.1,.9;"..st.swatch[2].."]"..
      "style[style_"..st.id..";bgcolor="..(st==current and "#f5872c" or "#3a5566").."]"..
      "button["..x..",4.4;2.3,.7;style_"..st.id..";"..st.label.."]"
  end
  C.show_formspec(player:get_player_name(),"brickcraft:style",fs..
    "label[.6,5.6;You can change it later: I > Change look, or /look]")
end

-- Each new player gets their own free spot so friends don't spawn inside each other.
local spots={{x=0,z=4},{x=-3,z=4},{x=3,z=4},{x=-6,z=4},{x=6,z=4},{x=-3,z=1},{x=3,z=1},{x=0,z=1}}
local function home_pos(player)
  local s=spots[player:get_meta():get_int("brickcraft_spot")] or spots[1]
  return {x=s.x,y=2,z=s.z}
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

function inventory_formspec(player)
  local current=get_shape(player)
  local fs="formspec_version[6]size[10.8,10.4]label[.4,.4;BRICKCRAFT / YOUR BRICKS   (Tab or E: next piece)]"
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
      local x=2.5+(i-1)*2.75
      fs=fs.."style[shape_"..s.id..";bgcolor="..(s==current and "#f5872c" or "#3a5566").."]"..
        "button["..x..","..y..";2.6,.6;shape_"..s.id..";"..
        C.formspec_escape(s.label:gsub("^Brick ",""):gsub("^Plate ",""):gsub("^Round Brick","Round")).."]"..
        "tooltip[shape_"..s.id..";"..C.formspec_escape(s.label.." - part "..s.part.." - uses "..s.cost.." brick"..(s.cost>1 and "s" or "")).."]"
    end
  end
  return fs.."list[current_player;main;.4,3.3;8,4;]"..
    "label[.4,8.5;1: Separator | 2-9: Colors | Right click or F: Build | Q: Turn]"..
    "label[.4,9;2 x 4 pieces use 2 bricks of their color. The others use 1.]listring[current_player;main]"..
    "button[4.6,9.4;2.8,.6;look;Change look]button[7.6,9.4;2.8,.6;help;Help: all keys]"
end
C.register_on_player_receive_fields(function(player,formname,fields)
  if formname=="brickcraft:welcome" and fields.help then show_help(player); return true end
  if formname=="brickcraft:style" then
    for _,st in ipairs(styles) do
      if fields["style_"..st.id] then
        local meta=player:get_meta()
        meta:set_string("brickcraft_style",st.id); apply_style(player)
        local first=meta:get_int("brickcraft_style_chosen")==0
        meta:set_int("brickcraft_style_chosen",1)
        if first then welcome(player) else C.close_formspec(player:get_player_name(),formname) end
      end
    end
    return true
  end
  if formname~="" then return end
  if fields.help then show_help(player); return true end
  if fields.look then show_style_picker(player); return true end
  for _,s in ipairs(shapes) do
    if fields["shape_"..s.id] then set_shape(player,s); return true end
  end
end)
C.register_on_joinplayer(function(player)
  local inv=player:get_inventory(); inv:set_size("main",32)
  player:hud_set_hotbar_itemcount(9)
  player:set_inventory_formspec(inventory_formspec(player))
  apply_style(player)
  player:set_sky({base_color="#93cddd",type="regular",clouds=true})
  player:set_sun({visible=true}); player:set_moon({visible=false})
  player:hud_add({type="text",position={x=.5,y=0},offset={x=0,y=28},
    text="BRICKCRAFT   |   1 Collect   2-9 Colors   Right click Build   Tab Piece   Q Turn   I Inventory   ? Help",number=0xffffff,alignment={x=0,y=0},scale={x=100,y=20}})
  update_hud(player)
  if player:get_meta():get_int("brickcraft_started")==0 then
    inv:set_stack("main",1,"brickcraft:separator")
    for i,color in ipairs(colors) do inv:set_stack("main",i+1,"brickcraft:"..color.." 24") end
    player:get_meta():set_int("brickcraft_started",1)
    claim_spot(player)
    player:set_pos(home_pos(player)); player:set_look_horizontal(0)
  end
  -- New players pick a look first; the welcome screen follows their choice.
  if not testing and player:get_meta():get_int("brickcraft_style_chosen")==0 then
    show_style_picker(player)
  end
  C.set_timeofday(.48)
end)
C.register_on_leaveplayer(function(player) hud[player:get_player_name()]=nil; held[player:get_player_name()]=nil end)
C.register_on_respawnplayer(function(player) player:set_pos(home_pos(player)); return true end)
C.register_chatcommand("home",{description="Return to the workshop",func=function(name)
  local p=C.get_player_by_name(name); if p then p:set_pos(home_pos(p)) end
  return true,"Welcome home!"
end})
C.register_chatcommand("guide",{description="Show BrickCraft controls",func=function(name)
  local p=C.get_player_by_name(name); if p then welcome(p) end
  return true
end})
C.register_chatcommand("look",{description="Choose how your block person looks",func=function(name)
  local p=C.get_player_by_name(name); if p then show_style_picker(p) end
  return true
end})
C.register_chatcommand("who",{description="List the builders here",func=function()
  local names={}
  for _,p in ipairs(C.get_connected_players()) do
    names[#names+1]=p:get_player_name().." ("..get_style(p).label..")"
  end
  return true,"Builders here: "..table.concat(names,", ")
end})
C.register_chatcommand("keys",{description="Show every BrickCraft key and command",func=function(name)
  local p=C.get_player_by_name(name); if p then show_help(p) end
  return true
end})
C.register_chatcommand("shape",{params="<piece>",description="Choose the piece to build with",
  func=function(name,param)
    local p,s=C.get_player_by_name(name),shape_by_id[param]
    if not s then return false,"Pieces: 2x2, 1x2, 2x4, plate, plate_1x2, plate_2x4, round_2x2, slope_2x2, slope_2x1" end
    if p then set_shape(p,s) end
    return true,"Shape: "..s.label
  end})
local elapsed=0
-- Key presses the server can see: E or Tab (aux1, fast movement is off) picks the next
-- piece, with Shift the previous one; the ?/ key, bound to zoom in brickcraft.conf with
-- zoom_fov 0, opens help.
local key_actions={
  aux1=function(p)
    local step=p:get_player_control().sneak and -2 or 0
    set_shape(p,shapes[(get_shape(p).index+step)%#shapes+1])
  end,
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

brickcraft={shapes=shape_by_id,shape_list=shapes,colors=colors,set_shape=set_shape,turn=turn_next,styles=style_by_id,
  get_style=get_style,home_pos=home_pos}

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
