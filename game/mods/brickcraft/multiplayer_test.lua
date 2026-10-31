-- Opt-in check for a dedicated server with two networked clients (tools/test_multiplayer.py).
local C=core
local DAD,KID="MPDad","MPLeona"
local function choose_look(player,style)
  for _,handler in ipairs(C.registered_on_player_receive_fields) do
    if handler(player,"brickcraft:style",{["style_"..style]="x"}) then return end
  end
end
local started=false
C.register_on_joinplayer(function()
  C.after(2,function()
    local dad,kid=C.get_player_by_name(DAD),C.get_player_by_name(KID)
    if started or not dad or not kid then return end
    started=true
    -- Each builder spawns on their own spot.
    local a,b=brickcraft.home_pos(dad),brickcraft.home_pos(kid)
    assert(a.x~=b.x or a.z~=b.z,"different spawn spots")
    -- Looks: the real picker path sets mesh, texture and nametag color per player.
    choose_look(dad,"dad"); choose_look(kid,"daughter")
    assert(dad:get_properties().mesh=="brickcraft_person_short.obj","dad look")
    assert(kid:get_properties().mesh=="brickcraft_person_long.obj","daughter look")
    assert(kid:get_properties().textures[1]=="brickcraft_person_daughter.png","daughter colors")
    local tag=kid:get_nametag_attributes().color
    assert(tag and tag.r==0xff and tag.g==0xb3,"daughter nametag color")
    -- Shared world: Dad builds, Leona collects the same brick into her own inventory.
    local pos={x=10,y=0,z=-2}
    local inv_dad,inv_kid=dad:get_inventory(),kid:get_inventory()
    local stack=inv_dad:get_stack("main",2)
    stack=stack:get_definition().on_place(stack,dad,{type="node",under={x=10,y=-1,z=-2},above=pos})
    inv_dad:set_stack("main",2,stack)
    assert(C.get_node(pos).name=="brickcraft:coral","dad placed a brick")
    assert(inv_dad:get_stack("main",2):get_count()==23,"dad spent one")
    C.registered_tools["brickcraft:separator"].on_use(inv_kid:get_stack("main",1),kid,
      {type="node",under=pos,above={x=10,y=1,z=-2}})
    assert(C.get_node(pos).name=="air","leona collected it")
    assert(inv_kid:get_stack("main",2):get_count()==25,"leona received it")
    local ok,who=C.registered_chatcommands.who.func(KID,"")
    assert(ok and who:find(DAD) and who:find(KID),"/who lists both")
    C.log("action","BRICKCRAFT MULTIPLAYER PASS: two network clients, own spots and looks, shared building, "..who)
    C.request_shutdown("BrickCraft multiplayer check passed",false,1)
  end)
end)
