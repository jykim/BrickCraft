local C=core
local store=C.get_mod_storage()
local function place(player,slot,under,above)
  local inv=player:get_inventory()
  local stack=inv:get_stack("main",slot)
  -- The item's own on_place is what a right click runs.
  stack=stack:get_definition().on_place(stack,player,{type="node",under=under,above=above})
  inv:set_stack("main",slot,stack)
  return stack:get_count()
end
local function separator(player,action,pos)
  local tool=player:get_inventory():get_stack("main",1)
  C.registered_tools["brickcraft:separator"][action](tool,player,{type="node",under=pos,above=vector.offset(pos,0,1,0)})
end
C.register_on_joinplayer(function(player)
  C.after(3,function()
    local name=player:get_player_name()
    local p={x=1,y=0,z=2}
    local inv=player:get_inventory()
    local stage=store:get_int("test_stage")
    if stage==0 then
      -- /parkour: restart works with or without a marked start; checkpoints and starts stick.
      do
        local parkour=C.registered_chatcommands.parkour
        assert(parkour,"/parkour exists")
        local function near(a,b) return vector.distance(a,b)<.01 end
        player:set_pos({x=9,y=4,z=9})
        local ok,msg=parkour.func(name,"restart")
        assert(ok and msg~="" and near(player:get_pos(),brickcraft.home_pos(player)),
          "/parkour restart with no course start goes to the world start and says so")
        player:set_pos({x=5,y=1,z=6})
        assert(parkour.func(name,"start here"),"/parkour start here marks the course start")
        player:set_pos({x=12,y=2,z=8})
        assert(parkour.func(name,"checkpoint"),"/parkour checkpoint saves this spot")
        player:set_pos({x=14,y=3,z=1})
        assert(parkour.func(name,"back") and near(player:get_pos(),{x=12,y=2,z=8}),"/parkour back returns to the checkpoint")
        player:set_pos({x=14,y=3,z=1})
        assert(parkour.func(name,"restart") and near(player:get_pos(),{x=5,y=1,z=6}),"/parkour restart returns to the course start")
        assert(player:get_meta():get_string("brickcraft_parkour_checkpoint")=="","restart forgets the checkpoint")
        player:set_pos({x=14,y=3,z=1})
        assert(parkour.func(name,"back") and near(player:get_pos(),{x=5,y=1,z=6}),"with no checkpoint, back goes to the start")
        assert(parkour.func(name,"") and near(player:get_pos(),{x=5,y=1,z=6}),"/parkour alone restarts")
        assert(not parkour.func(name,"fly"),"unknown /parkour words are refused with help")
        assert(parkour.func(name,"start clear"),"/parkour start clear removes the start")
        player:set_pos({x=14,y=3,z=1})
        assert(parkour.func(name,"restart") and near(player:get_pos(),brickcraft.home_pos(player)),"cleared start: back to the world start")
      end
      -- Move first so the client has acknowledged the position before the save.
      player:set_pos({x=2,y=.5,z=3})
      assert(C.get_node({x=1,y=-1,z=2}).name=="brickcraft:baseplate","baseplate generated")
      local have=function(item) return brickcraft.count_of(player,item) end
      -- A new player's kit is pieces: some of every brick, plate, tile, round and slope.
      assert(have("brickcraft:coral")==8 and have("brickcraft:navy_plate_1x2")==4 and have("brickcraft:gold_slope_2x1")==2 and
        have("brickcraft:navy_track")==12,"the starter kit is pieces")
      assert(inv:get_stack("main",2):get_name()=="brickcraft:coral","the kit's 2 x 2s start on the color keys")
      inv:set_list("main",{}); inv:set_list("pieces",{}); inv:set_stack("main",1,"brickcraft:separator")
      local function click(fields) for _,f in ipairs(C.registered_on_player_receive_fields) do if f(player,"",fields) then break end end end
      -- Collected bricks automatically appear in their color's empty hotbar slot.
      brickcraft.give(player,"brickcraft:coral 24")
      assert(inv:get_stack("main",2):get_name()=="brickcraft:coral" and have("brickcraft:coral")==24,
        "new pieces go straight to the hotbar")
      -- A full hotbar keeps overflow visible in the collection, alongside other shapes.
      for i=3,12 do inv:set_stack("main",i,"brickcraft:separator") end
      brickcraft.give(player,"brickcraft:green 7")
      brickcraft.give(player,"brickcraft:gold_1x1 5")
      assert(inv:contains_item("pieces","brickcraft:green 7"),"full hotbar stores harvested bricks")
      brickcraft.refresh_inventory(player)
      local fs=player:get_inventory_formspec()
      assert(fs:find("owned_2x2_green",1,true) and fs:find("owned_1x1_gold",1,true),
        "collection shows stored colors and shapes together")
      assert(fs:find("7 owned (includes hotbar and storage)",1,true),"stored count visible")
      inv:set_stack("main",10,"")
      click({owned_2x2_green="x"})
      assert(inv:get_stack("main",10):get_name()=="brickcraft:green" and have("brickcraft:green")==7,
        "collection click brings the exact stored piece into an empty hotbar slot")
      for i=3,12 do inv:set_stack("main",i,"") end
      inv:set_list("pieces",{})
      assert(brickcraft.to_hotbar(player,"brickcraft:coral",2),"to the hotbar")
      assert(inv:get_stack("main",2):get_name()=="brickcraft:coral" and inv:get_stack("main",2):get_count()==24,"all 24 on slot 2")
      assert(place(player,2,{x=1,y=-1,z=2},p)==23,"placement uses one piece")
      assert(C.get_node(p).name=="brickcraft:coral","placement callback")
      -- Free hotbar: different pieces side by side. I > a piece > a color puts it in the first
      -- empty hotbar slot.
      for _,id in ipairs({"_1x2","_2x4","_plate"}) do brickcraft.give(player,"brickcraft:gold"..id.." 24") end
      for i=3,5 do
        inv:add_item("pieces",inv:get_stack("main",i)); inv:set_stack("main",i,"")
      end
      player:set_look_horizontal(0); player:set_look_vertical(0)
      for i,id in ipairs({"1x2","2x4","plate"}) do
        brickcraft.set_shape(player,brickcraft.shapes[id]); click({take_gold="x"})
        assert(inv:get_stack("main",2+i):get_name()==brickcraft.piece_item("gold",brickcraft.shapes[id]),"gold "..id.." in slot "..(2+i))
      end
      assert(inv:get_stack("main",2):get_name()=="brickcraft:coral","the coral 2 x 2s stay beside them")
      assert(place(player,3,{x=4,y=-1,z=2},{x=4,y=0,z=2})==23,"a 1 x 2 is one piece")
      assert(C.get_node({x=4,y=0,z=2}).name=="brickcraft:gold_1x2","1 x 2 placed")
      -- Looking +z with no turn gives facedir 0, so a 2 x 4 extends to +z.
      assert(place(player,4,{x=6,y=-1,z=2},{x=6,y=0,z=2})==23,"a 2 x 4 is one piece too")
      assert(C.get_node({x=6,y=0,z=2}).name=="brickcraft:gold_2x4","2 x 4 placed")
      assert(C.get_node({x=6,y=0,z=3}).name=="brickcraft:gold_2x4_tail","2 x 4 end cell")
      -- A 2 x 4 that would overlap a brick is refused without spending it.
      assert(place(player,4,{x=6,y=-1,z=1},{x=6,y=0,z=1})==23,"blocked 2 x 4 refused")
      assert(C.get_node({x=6,y=0,z=1}).name=="air","blocked 2 x 4 leaves no node")
      -- Q (drop) turns the view 45° left and throws nothing away; I > Turn turns the brick.
      local look=player:get_look_horizontal()
      local had=inv:get_stack("main",5):get_count()
      local kept=inv:get_stack("main",5):get_definition().on_drop(inv:get_stack("main",5),player,player:get_pos())
      assert(kept:get_count()==had and math.abs((player:get_look_horizontal()-look)%(2*math.pi)-math.pi/4)<.01,"Q turns left instead of dropping")
      click({turn="x"})
      assert(player:get_meta():get_int("brickcraft_turn")==1,"I > Turn turns the next brick")
      assert(place(player,5,{x=8,y=-1,z=2},{x=8,y=0,z=2})==23,"a plate is one piece")
      local plate=C.get_node({x=8,y=0,z=2})
      assert(plate.name=="brickcraft:gold_plate" and plate.param2==1,"plate placed with turn")
      -- A collected piece joins its stack in the hotbar.
      separator(player,"on_use",{x=8,y=0,z=2})
      assert(inv:get_stack("main",5):get_count()==24,"the plate came back to its slot")
      assert(place(player,5,{x=8,y=-1,z=2},{x=8,y=0,z=2})==23,"and goes down again")
      -- "All colors to hotbar": the chosen piece on every color key it has.
      brickcraft.give(player,"brickcraft:sky_plate 3")
      brickcraft.set_shape(player,brickcraft.shapes.plate); click({fill="x"})
      assert(inv:get_stack("main",3):get_name()=="brickcraft:gold_plate" and inv:get_stack("main",3):get_count()==23 and
        inv:get_stack("main",5):get_name()=="brickcraft:sky_plate","all colors: gold plates on 3, sky on 5")
      assert(inv:get_stack("main",2):get_name()=="brickcraft:coral" and have("brickcraft:gold_1x2")==23,
        "colors with no plates keep their slot; the 1 x 2s are put away, not lost")
      -- Put the slots back for the rest: coral 2 x 2s on 2, the gold pieces as they were.
      brickcraft.to_hotbar(player,"brickcraft:gold_1x2",3); brickcraft.to_hotbar(player,"brickcraft:gold_2x4",4)
      brickcraft.to_hotbar(player,"brickcraft:gold_plate",5)
      brickcraft.set_shape(player,brickcraft.shapes["2x2"])
      -- Undo placement refunds the exact cost; undo collection restores the
      -- exact node and consumes the refund again.
      local undo_pos={x=10,y=0,z=2}
      assert(place(player,2,{x=10,y=-1,z=2},undo_pos)==22,"undo test placement")
      assert(brickcraft.undo(player),"undo placement succeeds")
      assert(C.get_node(undo_pos).name=="air" and inv:get_stack("main",2):get_count()==23,
        "undo placement removes node and refunds brick")
      assert(place(player,2,{x=10,y=-1,z=2},undo_pos)==22,"collect undo setup")
      separator(player,"on_use",undo_pos)
      assert(C.get_node(undo_pos).name=="air" and inv:get_stack("main",2):get_count()==23,
        "collect undo setup collected")
      assert(brickcraft.undo(player),"undo collection succeeds")
      assert(C.get_node(undo_pos).name=="brickcraft:coral" and inv:get_stack("main",2):get_count()==22,
        "undo collection restores node and removes refund")
      C.remove_node(undo_pos); brickcraft.give(player,"brickcraft:coral")
      -- Sort: the hotbar stays as it is, pieces in the bag are put away, LEGO parts in the bag
      -- line up by part then color, a row per part.
      do
        local keep,keep_pieces=inv:get_list("main"),inv:get_list("pieces")
        local function part(id,name,color)
          local st=ItemStack("brickcraft:real_part"); local m=st:get_meta()
          m:set_string("part",id); m:set_string("cname",name); m:set_string("bc_color",color); return st
        end
        inv:set_list("main",{}); inv:set_list("pieces",{})
        inv:set_stack("main",1,"brickcraft:separator")
        inv:set_stack("main",5,"brickcraft:navy 27"); inv:set_stack("main",20,"brickcraft:navy 48")
        inv:set_stack("main",9,"brickcraft:gold_1x2 3"); inv:set_stack("main",30,"brickcraft:tan 2")
        inv:set_stack("main",14,part("3062","Round 1 x 1","#0055BF"))
        inv:set_stack("main",25,part("3062","Round 1 x 1","#C91A09"))
        inv:set_stack("main",13,part("3062","Round 1 x 1","#0055BF"))
        inv:set_stack("main",16,part("3040","Slope 45 2 x 1","#FFFFFF"))
        for _,f in ipairs(C.registered_on_player_receive_fields) do if f(player,"",{sort="x"}) then break end end
        local function at(i) return inv:get_stack("main",i) end
        assert(at(1):get_name()=="brickcraft:separator","sort: separator in slot 1")
        assert(at(5):get_count()==27 and at(9):get_name()=="brickcraft:gold_1x2","sort: the hotbar stays as it is")
        assert(at(20):is_empty() and at(30):is_empty() and have("brickcraft:navy")==75 and have("brickcraft:tan")==2,
          "sort: pieces in the bag put away, not lost")
        assert(at(13):get_meta():get_string("bc_color")=="#C91A09" and at(14):get_count()==2 and at(15):is_empty(),
          "sort: round 1 x 1 red then two blue merged")
        assert(at(23):get_meta():get_string("part")=="3040","sort: the slope starts the next row")
        inv:set_list("main",keep); inv:set_list("pieces",keep_pieces)
      end
      assert(C.registered_chatcommands.keys.func(name),"/keys opens the help screen")
      assert(C.registered_items["brickcraft:gold"].range==7,"bricks reach as far as the separator")
      C.close_formspec(name,"brickcraft:help")
      store:set_int("test_stage",1)
      C.log("action","BRICKCRAFT TEST PHASE 1 PASS: generation, placement, inventory debit, 1x2/2x4/plate shapes, turn; saving")
    else
      assert(C.get_node(p).name=="brickcraft:coral","brick survives restart")
      assert(C.get_node({x=26,y=-1,z=0}).name=="brickcraft:grass","grass ring around the baseplate")
      assert(C.get_node({x=0,y=0,z=0}).name=="air","landscape leaves the workshop clear")
      local have=function(item) return brickcraft.count_of(player,item) end
      assert(inv:get_stack("main",2):get_count()==23,"inventory survives restart")
      assert(have("brickcraft:gold_1x2")==23 and have("brickcraft:gold_2x4")==23 and have("brickcraft:gold_plate")==23,
        "pieces survive restart")
      assert(C.get_node({x=6,y=0,z=3}).name=="brickcraft:gold_2x4_tail","2 x 4 survives restart")
      assert(math.abs(player:get_pos().x-2)<.5,"position survives restart")
      assert(player:get_wielded_item():get_name()=="brickcraft:separator","separator selected")
      separator(player,"on_use",p)
      assert(C.get_node(p).name=="air","separator removes brick")
      assert(inv:get_stack("main",2):get_count()==24,"separator gives the brick back")
      -- Turning a 2 x 4 moves its end cell from +z to +x.
      separator(player,"on_place",{x=6,y=0,z=3})
      assert(C.get_node({x=6,y=0,z=2}).param2==1,"2 x 4 turned")
      assert(C.get_node({x=6,y=0,z=3}).name=="air","old end cell cleared")
      assert(C.get_node({x=7,y=0,z=2}).name=="brickcraft:gold_2x4_tail","new end cell")
      assert(brickcraft.undo(player),"undo turn succeeds")
      assert(C.get_node({x=6,y=0,z=2}).param2==0,"undo restores old turn")
      assert(C.get_node({x=6,y=0,z=3}).name=="brickcraft:gold_2x4_tail","undo restores old end")
      separator(player,"on_place",{x=6,y=0,z=2})
      -- Collecting from the end cell removes the whole brick once.
      separator(player,"on_use",{x=7,y=0,z=2})
      assert(C.get_node({x=6,y=0,z=2}).name=="air" and C.get_node({x=7,y=0,z=2}).name=="air","2 x 4 removed")
      assert(have("brickcraft:gold_2x4")==24,"the 2 x 4 comes back as a 2 x 4")
      separator(player,"on_use",{x=4,y=0,z=2})
      separator(player,"on_use",{x=8,y=0,z=2})
      assert(have("brickcraft:gold_1x2")==24 and have("brickcraft:gold_plate")==24,"the 1 x 2 and the plate come back as themselves")
      C.node_dig({x=1,y=-1,z=2},C.get_node({x=1,y=-1,z=2}),player)
      assert(C.get_node({x=1,y=-1,z=2}).name=="brickcraft:baseplate","baseplate protected")
      -- Harvest: every landscape cell above the bottom layer gives one brick of its color.
      local function count(item) return brickcraft.count_of(player,item) end
      local edge={x=46,y=26,z=46}
      for scenery,item in pairs({trunk="brown",leaves="green",grass="green",dirt="tan"}) do
        local found=C.find_nodes_in_area(vector.multiply(edge,-1),edge,"brickcraft:"..scenery)[1]
        assert(found,"landscape has "..scenery)
        local before=count("brickcraft:"..item)
        separator(player,"on_use",found)
        assert(C.get_node(found).name=="air",scenery.." harvested")
        assert(count("brickcraft:"..item)==before+1,scenery.." gives one "..item.." brick")
        local color_slot=({green=10,brown=11,tan=12})[item]
        assert(inv:get_stack("main",color_slot):get_name()=="brickcraft:"..item,
          "mined "..item.." appears on its hotbar color key")
        if scenery=="trunk" then
          assert(brickcraft.undo(player),"undo harvest succeeds")
          assert(C.get_node(found).name=="brickcraft:trunk" and count("brickcraft:brown")==before,
            "undo harvest restores the trunk and takes the brick back")
        end
      end
      -- The green ground next to the workshop can be dug; the gray floor below it cannot.
      local ground={x=26,y=-1,z=0}
      local greens=count("brickcraft:green")
      separator(player,"on_use",ground)
      assert(C.get_node(ground).name=="air" and count("brickcraft:green")==greens+1,"green ground harvested")
      local floor=vector.offset(ground,0,-1,0)
      assert(C.get_node(floor).name=="brickcraft:baseplate","gray floor under the hills")
      separator(player,"on_use",floor)
      C.node_dig(floor,C.get_node(floor),player)
      assert(C.get_node(floor).name=="brickcraft:baseplate","gray floor protected")
      brickcraft.give(player,"brickcraft:brown")
      local slot=11
      assert(brickcraft.to_hotbar(player,"brickcraft:brown",slot),"a harvested brown 2 x 2 comes out to the hotbar")
      assert(place(player,slot,{x=2,y=-1,z=6},{x=2,y=0,z=6})>=0 and C.get_node({x=2,y=0,z=6}).name=="brickcraft:brown",
        "harvested brown brick places as a real brick")
      C.log("action","BRICKCRAFT TEST PHASE 2 PASS: restart persistence, separator recovery, inventory credit, 2x4 turn and whole-brick refund, base protection, landscape harvest")
    end
    C.request_shutdown("BrickCraft integration phase passed",false,1)
  end)
end)
