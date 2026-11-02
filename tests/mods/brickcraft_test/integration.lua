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
      -- Move first so the client has acknowledged the position before the save.
      player:set_pos({x=2,y=.5,z=3})
      assert(C.get_node({x=1,y=-1,z=2}).name=="brickcraft:baseplate","baseplate generated")
      inv:set_stack("main",2,"brickcraft:coral 24")
      assert(place(player,2,{x=1,y=-1,z=2},p)==23,"placement consumes one brick")
      assert(C.get_node(p).name=="brickcraft:coral","placement callback")
      -- Shapes: looking +z with no turn gives facedir 0, so a 2 x 4 extends to +z.
      player:set_look_horizontal(0); player:set_look_vertical(0)
      inv:set_stack("main",3,"brickcraft:gold 24")
      brickcraft.set_shape(player,brickcraft.shapes["1x2"])
      assert(place(player,3,{x=4,y=-1,z=2},{x=4,y=0,z=2})==23,"1 x 2 costs one")
      assert(C.get_node({x=4,y=0,z=2}).name=="brickcraft:gold_1x2","1 x 2 placed")
      brickcraft.set_shape(player,brickcraft.shapes["2x4"])
      assert(place(player,3,{x=6,y=-1,z=2},{x=6,y=0,z=2})==21,"2 x 4 costs two")
      assert(C.get_node({x=6,y=0,z=2}).name=="brickcraft:gold_2x4","2 x 4 placed")
      assert(C.get_node({x=6,y=0,z=3}).name=="brickcraft:gold_2x4_tail","2 x 4 end cell")
      -- A 2 x 4 that would overlap a brick is refused without spending bricks.
      assert(place(player,3,{x=6,y=-1,z=1},{x=6,y=0,z=1})==21,"blocked 2 x 4 refused")
      assert(C.get_node({x=6,y=0,z=1}).name=="air","blocked 2 x 4 leaves no node")
      brickcraft.set_shape(player,brickcraft.shapes.plate)
      C.registered_items["brickcraft:gold"].on_drop(inv:get_stack("main",3),player,player:get_pos())
      assert(player:get_meta():get_int("brickcraft_turn")==1,"Q turns instead of dropping")
      assert(place(player,3,{x=8,y=-1,z=2},{x=8,y=0,z=2})==20,"plate costs one")
      local plate=C.get_node({x=8,y=0,z=2})
      assert(plate.name=="brickcraft:gold_plate" and plate.param2==1,"plate placed with turn")
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
      C.remove_node(undo_pos); inv:add_item("main","brickcraft:coral")
      assert(C.registered_chatcommands.keys.func(name),"/keys opens the help screen")
      assert(C.registered_items["brickcraft:gold"].range==7,"bricks reach as far as the separator")
      C.close_formspec(name,"brickcraft:help")
      store:set_int("test_stage",1)
      C.log("action","BRICKCRAFT TEST PHASE 1 PASS: generation, placement, inventory debit, 1x2/2x4/plate shapes, turn; saving")
    else
      assert(C.get_node(p).name=="brickcraft:coral","brick survives restart")
      assert(C.get_node({x=26,y=-1,z=0}).name=="brickcraft:grass","grass ring around the baseplate")
      assert(C.get_node({x=0,y=0,z=0}).name=="air","landscape leaves the workshop clear")
      assert(inv:get_stack("main",2):get_count()==23,"inventory survives restart")
      assert(inv:get_stack("main",3):get_count()==20,"shape debits survive restart")
      assert(C.get_node({x=6,y=0,z=3}).name=="brickcraft:gold_2x4_tail","2 x 4 survives restart")
      assert(math.abs(player:get_pos().x-2)<.5,"position survives restart")
      assert(player:get_wielded_item():get_name()=="brickcraft:separator","separator selected")
      separator(player,"on_use",p)
      assert(C.get_node(p).name=="air","separator removes brick")
      assert(inv:get_stack("main",2):get_count()==24,"separator refunds exactly one brick")
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
      assert(inv:get_stack("main",3):get_count()==22,"2 x 4 refunds two")
      separator(player,"on_use",{x=4,y=0,z=2})
      separator(player,"on_use",{x=8,y=0,z=2})
      assert(inv:get_stack("main",3):get_count()==24,"1 x 2 and plate refund one each")
      C.node_dig({x=1,y=-1,z=2},C.get_node({x=1,y=-1,z=2}),player)
      assert(C.get_node({x=1,y=-1,z=2}).name=="brickcraft:baseplate","baseplate protected")
      -- Harvest: every landscape cell above the bottom layer gives one brick of its color.
      local function count(item)
        local n=0
        for _,s in ipairs(inv:get_list("main")) do if s:get_name()==item then n=n+s:get_count() end end
        return n
      end
      local edge={x=46,y=26,z=46}
      for scenery,item in pairs({trunk="brown",leaves="green",grass="green",dirt="tan"}) do
        local found=C.find_nodes_in_area(vector.multiply(edge,-1),edge,"brickcraft:"..scenery)[1]
        assert(found,"landscape has "..scenery)
        local before=count("brickcraft:"..item)
        separator(player,"on_use",found)
        assert(C.get_node(found).name=="air",scenery.." harvested")
        assert(count("brickcraft:"..item)==before+1,scenery.." gives one "..item.." brick")
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
      inv:add_item("main","brickcraft:brown")
      local slot
      for i,s in ipairs(inv:get_list("main")) do if s:get_name()=="brickcraft:brown" then slot=i end end
      assert(place(player,slot,{x=2,y=-1,z=6},{x=2,y=0,z=6})>=0 and C.get_node({x=2,y=0,z=6}).name=="brickcraft:brown",
        "harvested brown brick places as a real brick")
      C.log("action","BRICKCRAFT TEST PHASE 2 PASS: restart persistence, separator recovery, inventory credit, 2x4 turn and whole-brick refund, base protection, landscape harvest")
    end
    C.request_shutdown("BrickCraft integration phase passed",false,1)
  end)
end)
