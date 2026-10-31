local C = core
local colors = {"coral", "gold", "mint", "sky", "violet", "cream", "navy", "rose"}
local labels = {"Coral", "Gold", "Mint", "Sky", "Violet", "Cream", "Navy", "Rose"}
C.register_alias("mapgen_singlenode", "air")
C.register_item(":", {type="none", wield_image="brickcraft_hand.png", range=7,
  tool_capabilities={full_punch_interval=1, groupcaps={}}})
local boxes = {{-.5,-.5,-.5,.5,.36,.5}}
for _, x in ipairs({-.25,.25}) do
  for _, z in ipairs({-.25,.25}) do
    boxes[#boxes+1] = {x-.13,.36,z-.13,x+.13,.5,z+.13}
  end
end
for i, color in ipairs(colors) do
  C.register_node("brickcraft:"..color, {
    description=labels[i].." Brick (2 x 2)", drawtype="nodebox",
    tiles={"brickcraft_"..color..".png"}, paramtype="light", paramtype2="facedir",
    node_box={type="fixed", fixed=boxes},
    collision_box={type="fixed",fixed={-.5,-.5,-.5,.5,.5,.5}},
    selection_box={type="fixed",fixed={-.5,-.5,-.5,.5,.5,.5}},
    groups={brick=1}, stack_max=999,
    on_dig=function(pos,node,player)
      if player:get_wielded_item():get_name() ~= "brickcraft:separator" then
        C.chat_send_player(player:get_player_name(), "Select the orange separator (1) to collect bricks.")
        return
      end
      if not player:get_inventory():room_for_item("main", node.name) then
        C.chat_send_player(player:get_player_name(), "Inventory full: place some bricks first.")
        return
      end
      C.node_dig(pos,node,player)
    end,
  })
end
C.register_node("brickcraft:baseplate", {
  description="Workshop Baseplate", tiles={"brickcraft_baseplate.png"},
  groups={}, diggable=false, is_ground_content=false,
})
C.register_tool("brickcraft:separator", {
  description="Brick Separator\nLeft click: collect a brick\nBricks: right click to place",
  inventory_image="brickcraft_separator.png", wield_image="brickcraft_separator.png",
  range=7, tool_capabilities={full_punch_interval=.2,groupcaps={brick={times={[1]=.15},uses=0,maxlevel=1}}},
  on_use=function(stack,user,pointed)
    if pointed.type=="node" then
      local p=pointed.under
      local n=C.get_node(p)
      if C.get_item_group(n.name,"brick")==1 then
        C.registered_nodes[n.name].on_dig(p,n,user)
      end
    end
    return stack
  end,
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

local function welcome(player)
  C.show_formspec(player:get_player_name(),"brickcraft:welcome",
    "formspec_version[6]size[10,7]bgcolor[#142936;true]"..
    "label[.6,.6;BRICKCRAFT / BUILD TOGETHER]"..
    "textarea[.6,1.3;8.8,4.8;;Welcome to your brick workshop!;"..
    C.formspec_escape("WASD: move    Mouse: look    Space: jump\n1: orange separator / left click to collect\n2–9: choose a color / right click to place\nI: inventory    C: see your brick person\nEsc: pause / Quit to Menu saves and closes world\n\nCollect the colored stacks, then build a tiny home!\nYour world and inventory save automatically.\n/home returns you safely to the workshop.")..
    "]button_exit[3,6;4, .6;go;Let's build!]")
end
C.register_on_joinplayer(function(player)
  local inv=player:get_inventory(); inv:set_size("main",32)
  player:hud_set_hotbar_itemcount(9)
  player:set_inventory_formspec("formspec_version[6]size[10.8,7.5]label[.4,.4;BRICKCRAFT / YOUR BRICKS]list[current_player;main;.4,1;8,4;]label[.4,6;1: Separator | 2-9: Colors | Right click: Build]listring[current_player;main]")
  player:set_properties({visual="mesh",mesh="brickcraft_person.obj",textures={"brickcraft_person.png"},
    visual_size={x=10,y=10},collisionbox={-.3,0,-.3,.3,1.75,.3},eye_height=1.5})
  player:set_sky({base_color="#93cddd",type="regular",clouds=true})
  player:set_sun({visible=true}); player:set_moon({visible=false})
  player:hud_add({type="text",position={x=.5,y=0},offset={x=0,y=28},
    text="BRICKCRAFT   |   1 Collect   2-9 Colors   Right click Build   I Inventory   /home",number=0xffffff,alignment={x=0,y=0},scale={x=100,y=20}})
  if player:get_meta():get_int("brickcraft_started")==0 then
    inv:set_stack("main",1,"brickcraft:separator")
    for i,color in ipairs(colors) do inv:set_stack("main",i+1,"brickcraft:"..color.." 24") end
    player:get_meta():set_int("brickcraft_started",1)
    player:set_pos({x=0,y=2,z=4}); player:set_look_horizontal(0)
    if not C.settings:get_bool("brickcraft_integration_test",false) then welcome(player) end
  end
  C.set_timeofday(.48)
end)
C.register_on_respawnplayer(function(player) player:set_pos({x=0,y=2,z=4}); return true end)
C.register_chatcommand("home",{description="Return to the workshop",func=function(name)
  local p=C.get_player_by_name(name); if p then p:set_pos({x=0,y=2,z=4}) end
  return true,"Welcome home!"
end})
C.register_chatcommand("guide",{description="Show BrickCraft controls",func=function(name)
  local p=C.get_player_by_name(name); if p then welcome(p) end
  return true
end})
local elapsed=0
C.register_globalstep(function(dt)
  elapsed=elapsed+dt; if elapsed<1 then return end; elapsed=0
  for _,p in ipairs(C.get_connected_players()) do
    if p:get_pos().y< -8 then p:set_pos({x=0,y=2,z=4}) end
  end
end)

-- Opt-in integration checks execute actual engine callbacks, in a disposable world.
if C.settings:get_bool("brickcraft_integration_test",false) then
  dofile(C.get_modpath("brickcraft").."/integration.lua")
end
