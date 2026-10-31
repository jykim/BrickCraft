-- Opt-in check for a dedicated server with two networked clients (tools/test_multiplayer.py).
local C=core
local DAD,KID="MPDad","MPLeona"
-- Picks through the real "Who's playing?" form handler.
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
    local tag=kid:get_nametag_attributes()
    assert(tag.color and tag.color.r==0xff and tag.color.g==0xb3,"daughter nametag color")
    assert(tag.text=="Leona","nametag shows the chosen player")
    -- One player per computer: Leona's computer cannot also be Dad.
    choose_look(kid,"dad")
    assert(brickcraft.playing_as(kid)=="daughter","a player already playing cannot be picked twice")
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
    assert(ok and who:find(DAD) and who:find(KID) and who:find("Leona"),"/who lists both")
    -- Bricks belong to the player, not the computer: Dad's computer switches to
    -- Explorer (a fresh kit), Leona's computer gives up Leona, and Dad's computer then
    -- plays Leona with her collected brick, then Dad again with his spent one.
    choose_look(dad,"explorer")
    assert(brickcraft.playing_as(dad)=="explorer" and inv_dad:get_stack("main",2):get_count()==24,"explorer starts fresh")
    choose_look(kid,"builder")
    choose_look(dad,"daughter")
    assert(inv_dad:get_stack("main",2):get_count()==25,"leona's bricks follow her to another computer")
    choose_look(dad,"dad")
    assert(inv_dad:get_stack("main",2):get_count()==23,"dad's bricks come back")
    C.log("action","BRICKCRAFT MULTIPLAYER PASS: two network clients, own spots and looks, shared building, "..who)
    C.request_shutdown("BrickCraft multiplayer check passed",false,1)
  end)
end)
