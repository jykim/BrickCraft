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
    assert(inv_dad:get_stack("main",2):get_count()==7,"dad spent one of the kit's 8 coral 2 x 2s")
    C.registered_tools["brickcraft:separator"].on_use(inv_kid:get_stack("main",1),kid,
      {type="node",under=pos,above={x=10,y=1,z=-2}})
    assert(C.get_node(pos).name=="air","leona collected it")
    assert(inv_kid:get_stack("main",2):get_count()==9,"leona received it")
    local ok,who=C.registered_chatcommands.who.func(KID,"")
    assert(ok and who:find(DAD) and who:find(KID) and who:find("Leona"),"/who lists both")
    -- Bricks belong to the player, not the computer: Dad's computer switches to
    -- Explorer (a fresh kit), Leona's computer gives up Leona, and Dad's computer then
    -- plays Leona with her collected brick, then Dad again with his spent one.
    choose_look(dad,"explorer")
    assert(brickcraft.playing_as(dad)=="explorer" and inv_dad:get_stack("main",2):get_count()==8 and brickcraft.count_of(dad,"brickcraft:sky_slope_2x1")==2,"explorer starts fresh, with the piece kit")
    choose_look(kid,"builder")
    choose_look(dad,"daughter")
    assert(inv_dad:get_stack("main",2):get_count()==9,"leona's bricks follow her to another computer")
    choose_look(dad,"dad")
    assert(inv_dad:get_stack("main",2):get_count()==7,"dad's bricks come back")
    -- Worlds: Dad makes his own through the real "Which world?" form, Leona goes there,
    -- then back to the Workshop. Each world is a fresh workshop in its own square.
    local function form(player,formname,fields)
      for _,handler in ipairs(C.registered_on_player_receive_fields) do
        if handler(player,formname,fields) then return end
      end
    end
    local function world_form(player,fields) return form(player,"brickcraft:world",fields) end
    assert(brickcraft.world_at(dad:get_pos()).id==0,"everyone starts in the Workshop")
    world_form(dad,{new="x"})
    form(dad,"brickcraft:new_world",{create="x",name="Dad's Fort",terrain="Flat Grass",style="Castle",
      characters="Knights",events="Team Battle",strict="true"})
    local tries=0
    local function check_worlds()
      local w=brickcraft.worlds()[1]
      tries=tries+1
      if not (w and w.built and brickcraft.world_at(dad:get_pos())==w) then
        assert(tries<40,"new world built and entered")
        return C.after(.5,check_worlds)
      end
      assert(w.name=="Dad's Fort" and w.owner=="dad" and (w.x~=0 or w.z~=0),"world saved with its owner")
      assert(w.write_owner==DAD and brickcraft.permissions.can_write(dad,w) and
        not brickcraft.permissions.can_write(kid,w),"new-world template preserves account-based write ownership")
      assert(w.terrain=="flat" and w.style=="castle" and w.characters=="knights" and w.events=="battle" and w.strict,
        "new-world menu settings are saved")
      assert(C.get_node({x=w.x+1,y=-1,z=w.z+2}).name=="brickcraft:baseplate","new world has its baseplate")
      assert(C.get_node({x=w.x-18,y=1,z=w.z+11}).name=="brickcraft:coral","new world has full stacks")
      assert(C.get_node({x=w.x+26,y=-1,z=w.z}).name=="brickcraft:grass","new world has its selected grass terrain")
      assert(C.get_node({x=w.x+40,y=0,z=w.z}).name=="air","flat terrain has no hills")
      assert(C.get_node({x=w.x-4,y=0,z=w.z-7}).name=="brickcraft:navy","castle style colors the welcome arch")
      assert(C.get_node({x=w.x+10,y=0,z=w.z-2}).name=="air","new world starts empty")
      local home=brickcraft.home_pos(dad)
      assert(home.x-w.x==a.x and home.z-w.z==a.z,"/home is Dad's spot in his world")
      -- Leona's computer (now Builder) picks Dad's world from the list: Workshop is item 1.
      assert(C.registered_chatcommands.world.func(KID,""),"/world opens the picker")
      world_form(kid,{world="CHG:2"}); world_form(kid,{go="x"})
      assert(brickcraft.world_at(kid:get_pos())==w,"leona entered dad's world")
      local _,who2=C.registered_chatcommands.who.func(KID,"")
      assert(who2:find("in Dad's Fort"),"/who shows the world")
      world_form(kid,{world="DCL:1"})
      assert(brickcraft.world_at(kid:get_pos()).id==0,"double click goes back to the Workshop")
      -- A Bunnies world: Dad makes one and wears bunny ears there, and so does his AI
      -- builder when it follows him in; Leona, back in the Workshop, does not.
      local dad_ai=brickcraft.ai and brickcraft.ai.workers and brickcraft.ai.workers.dad
      local function dad_bot() return dad_ai and dad_ai.state().bot end
      world_form(dad,{new="x"})
      form(dad,"brickcraft:new_world",{create="x",name="Burrow",terrain="Flat Grass",style="Nature",
        characters="Bunnies",events="Free Build"})
      local btries=0
      local function check_bunnies()
        local bw=brickcraft.worlds()[2]
        btries=btries+1
        if not (bw and bw.built and brickcraft.world_at(dad:get_pos())==bw
            and dad:get_properties().mesh=="brickcraft_person_short_bunny.obj"
            and (not dad_ai or dad_bot() and brickcraft.world_at(dad_bot():get_pos())==bw
              and dad_bot():get_properties().mesh=="brickcraft_person_short_bunny.obj")) then
          assert(btries<60,"bunny world built and dad and his builder are bunnies there")
          return C.after(.5,check_bunnies)
        end
        assert(bw.characters=="bunnies","the Bunnies theme is saved")
        assert(brickcraft.bunny_world({name="Bunny Kingdom"}) and not brickcraft.bunny_world(brickcraft.worlds()[1]),
          "a world named for bunnies is a bunny world; Dad's Fort is not")
        assert(kid:get_properties().mesh=="brickcraft_person.obj","leona, in the Workshop, is no bunny")
        local habitat=brickcraft.habitat
        if habitat then assert(habitat.set_skin(dad,"snow")) end
        C.after(1.5,function()
          if habitat then
            assert(dad:get_properties().mesh=="brickcraft_habitat_bunny_person.obj",
              "automatic bunny looks preserve the player's selected habitat skin")
            habitat.set_skin(dad,nil)
          end
          dad:set_pos(a)
          local back_tries=0
          local function check_back()
            back_tries=back_tries+1
            if dad:get_properties().mesh~="brickcraft_person_short.obj" or
                (dad_ai and (not dad_bot() or dad_bot():get_properties().mesh~="brickcraft_person_short.obj")) then
              assert(back_tries<40,"Dad and his builder regain their own looks in the Workshop")
              return C.after(.5,check_back)
            end
            C.log("action","BRICKCRAFT MULTIPLAYER PASS: two network clients, own spots and looks, shared building, new world, "..
              "bunny world"..(dad_ai and " (Dad and Dad bot are bunnies)" or "")..
              ", selected habitat skin preserved, normal looks restored on return, "..who)
            C.request_shutdown("BrickCraft multiplayer check passed",false,1)
          end
          check_back()
        end)
      end
      check_bunnies()
    end
    check_worlds()
  end)
end)
