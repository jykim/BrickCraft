-- Opt-in check (tools/test_house.py): build a small house with every piece through the
-- same on_place a right click runs, then list it as real parts.
local C=core
local plan=dofile(C.get_modpath("brickcraft_test").."/house_plan.lua")

C.register_on_joinplayer(function(player)
  C.after(3,function()
    local inv=player:get_inventory()
    local slot={}
    for i,color in ipairs(brickcraft.colors) do
      slot[color]=i+1; inv:set_stack("main",i+1,"brickcraft:"..color.." 99")
    end
    player:set_look_horizontal(0); player:set_look_vertical(0)
    local spent,parts,cells={}, {}, 0
    for n,step in ipairs(plan) do
      local piece,color,x,y,z,turn=unpack(step)
      local shape=brickcraft.shapes[piece]
      brickcraft.set_shape(player,shape)
      player:get_meta():set_int("brickcraft_turn",turn)
      local pos={x=x,y=y,z=z}
      local stack=inv:get_stack("main",slot[color])
      local before=stack:get_count()
      stack=stack:get_definition().on_place(stack,player,{type="node",under=pos,above=vector.offset(pos,0,1,0)})
      inv:set_stack("main",slot[color],stack)
      local node=C.get_node(pos)
      assert(node.name=="brickcraft:"..color..shape.suffix,
        ("step %d %s %s at %d,%d,%d: got %s"):format(n,color,piece,x,y,z,node.name))
      assert(node.param2==turn,("step %d turned %d, wanted %d"):format(n,node.param2,turn))
      assert(before-stack:get_count()==shape.cost,("step %d cost"):format(n))
      if shape.long then
        local tail=vector.add(pos,C.facedir_to_dir(turn))
        assert(C.get_node(tail).name=="brickcraft:"..color..shape.suffix.."_tail",("step %d end cell"):format(n))
      end
      spent[color]=(spent[color] or 0)+shape.cost
      local key=shape.part.." "..shape.label.." / "..color
      parts[key]=(parts[key] or 0)+1
      cells=cells+shape.cost
    end
    for color,n in pairs(spent) do
      assert(inv:get_stack("main",slot[color]):get_count()==99-n,"inventory matches pieces for "..color)
    end
    local list={}
    for k,n in pairs(parts) do list[#list+1]=n.." x "..k end
    table.sort(list)
    C.log("action","BRICKCRAFT HOUSE PARTS: "..table.concat(list,"; "))
    -- Leave the builder facing the front door for a look around.
    brickcraft.set_shape(player,brickcraft.shapes["2x2"]); player:get_meta():set_int("brickcraft_turn",0)
    player:set_pos({x=13.5,y=0,z=-11}); player:set_look_horizontal(0); player:set_look_vertical(.25)
    C.log("action",("BRICKCRAFT HOUSE PASS: %d pieces, %d brick cells, all placed through on_place"):format(#plan,cells))
    C.request_shutdown("BrickCraft house built",false,2)
  end)
end)
