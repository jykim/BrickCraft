-- Opt-in check (tools/test_house.py): build a small house with every piece through the
-- same on_place a right click runs, then list it as real parts.
local C=core
-- {piece, color, x, y, z, turn}; turn 0 = long side/high side toward +z, 1 = +x, 2 = -z.
-- The house spans x 12..15, z -4..-1; its front (door) faces -z.
local plan={}
local function add(piece,color,x,y,z,turn) plan[#plan+1]={piece,color,x,y,z,turn or 0} end
-- Floor inside the walls, and a threshold in the doorway.
add("plate_2x4","cream",13,0,-3); add("plate_2x4","cream",14,0,-3)
add("plate_1x2","violet",13,0,-4); add("plate_1x2","violet",14,0,-4)
-- Walls: 3 courses, joints staggered between courses like a real brick bond.
for y=0,2 do
  if y==1 then
    add("2x2","coral",12,y,-1); add("2x4","coral",13,y,-1,1); add("2x2","coral",15,y,-1)
    add("2x2","coral",12,y,-3); add("1x2","coral",12,y,-2)
    -- Round bricks frame a window on the right wall.
    add("round_2x2","mint",15,y,-3); add("round_2x2","mint",15,y,-2)
  else
    add("2x4","coral",12,y,-1,1); add("2x4","coral",14,y,-1,1)
    add("2x4","coral",12,y,-3); add("2x4","coral",15,y,-3)
  end
  if y<2 then add("2x2","coral",12,y,-4); add("2x2","coral",15,y,-4)
  else add("2x4","gold",12,y,-4,1); add("2x4","gold",14,y,-4,1) end -- lintel over the door
end
-- Roof: slopes front and back, plates in the middle, a round-brick chimney.
for x=12,15 do add("slope_2x2","navy",x,3,-4,0); add("slope_2x2","navy",x,3,-1,2) end
add("plate_2x4","navy",12,3,-3,1); add("plate_2x4","navy",14,3,-3,1)
add("plate_2x4","navy",12,3,-2,1); add("plate_2x4","navy",14,3,-2,1)
add("round_2x2","rose",15,4,-2); add("round_2x2","rose",15,5,-2)
-- Porch: small slopes rising toward the door.
add("slope_2x1","sky",13,0,-5,0); add("slope_2x1","sky",14,0,-5,0)
-- Porch posts (1 x 1 brick, round 1 x 1 lamp, 1 x 1 plate cap) hold an inverted-slope canopy.
for _,x in ipairs({12,15}) do
  add("1x1","cream",x,0,-5); add("round_1x1","gold",x,1,-5); add("plate_1x1","navy",x,2,-5)
end
add("slope_inv_2x2","navy",13,2,-5,0); add("slope_inv_2x2","navy",14,2,-5,0)
-- Smooth tiles finish the flat middle of the roof.
add("tile_2x2","cream",13,4,-3); add("tile_1x2","cream",14,4,-3)

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
