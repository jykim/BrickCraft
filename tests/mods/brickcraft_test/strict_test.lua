-- Opt-in check (tools/test_strict.py): in a strict LEGO world, pieces go in only where real
-- bricks would click, and nothing may come loose; the Workshop stays as free as before. Every
-- step runs the same on_place, separator click and undo a player's clicks do. Then the test
-- house (house_plan.lua) is tried in the strict world, and the steps it refuses are listed.
local C=core
local house=dofile(C.get_modpath("brickcraft_test").."/house_plan.lua")

C.register_on_joinplayer(function(player)
  C.after(2,function()
    local inv=player:get_inventory()
    local slot={}
    -- Plenty of every piece in every color (not the starter kit); the chosen piece is on
    -- each color's key.
    inv:set_list("main",{}); inv:set_list("pieces",{})
    for i,color in ipairs(brickcraft.colors) do
      slot[color]=i+1
      for _,s in ipairs(brickcraft.shape_list) do brickcraft.give(player,brickcraft.piece_item(color,s).." 999") end
    end
    inv:set_stack("main",1,"brickcraft:separator")
    player:set_look_horizontal(0); player:set_look_vertical(0)
    local strict=brickcraft.strict
    local o -- the world's center; x, z below are relative to it
    local function at(x,y,z) return {x=o.x+x,y=y,z=o.z+z} end
    local function put(piece,color,x,y,z,turn)
      local shape=brickcraft.shapes[piece]
      brickcraft.fill_hotbar(player,shape)
      player:get_meta():set_int("brickcraft_turn",turn or 0)
      local pos=at(x,y,z)
      local stack=inv:get_stack("main",slot[color])
      local before=stack:get_count()
      stack=stack:get_definition().on_place(stack,player,{type="node",under=pos,above=vector.offset(pos,0,1,0)})
      inv:set_stack("main",slot[color],stack)
      return before-stack:get_count()==1 -- spent only when it went in
    end
    local function yes(what,...) assert(put(...),"strict world refused "..what) end
    local function no(what,...) assert(not put(...),"strict world allowed "..what) end
    local function sep(fn,x,y,z)
      -- The separator goes in the hand for the click, and the slot gets its own stack back.
      local i=player:get_wield_index()
      local kept=inv:get_stack("main",i)
      inv:set_stack("main",i,"brickcraft:separator")
      local pos=at(x,y,z)
      C.registered_tools["brickcraft:separator"][fn](inv:get_stack("main",i),player,{type="node",under=pos,above=vector.offset(pos,0,1,0)})
      inv:set_stack("main",i,kept)
      return C.get_node(pos)
    end

    local function strict_checks(w)
      o={x=w.x,z=w.z}
      player:set_pos(at(16,0,-8))
      assert(strict.on(at(0,0,0)) and not strict.on({x=0,y=0,z=0}),"only the new world is strict")
      -- Studs: on the baseplate, on a brick, and per quarter of a cell.
      yes("a brick on the baseplate","2x2","coral",12,0,0)
      yes("a 2 x 4 on a brick, its end in the air","2x4","gold",12,1,0,1)
      yes("a 1 x 1 on the baseplate","1x1","cream",16,0,0)
      no("a 1 x 1 whose studs miss the one below","1x1","cream",16,1,0,2)
      yes("a 1 x 1 on the 1 x 1 below","1x1","cream",16,1,0,0)
      no("a brick held only at its side","2x2","coral",17,1,0)
      -- Nothing clicks onto tiles, plates or the sloped side of a slope.
      yes("a tile on the baseplate","tile_2x2","cream",12,0,3)
      no("a brick on a tile","2x2","coral",12,1,3)
      yes("a plate on the baseplate","plate","cream",14,0,3)
      no("a brick on a plate","2x2","coral",14,1,3)
      yes("a slope on the baseplate","slope_2x2","navy",16,0,3)
      no("a 1 x 1 on the sloped side","1x1","cream",16,1,3,0)
      yes("a 1 x 1 on the slope's studs","1x1","cream",16,1,3,2)
      -- Hanging a piece under an overhang; a sandwich can't be pushed in.
      yes("a column","2x2","coral",20,0,0); yes("a column","2x2","coral",20,1,0)
      yes("an overhang","2x4","gold",20,2,0,1)
      yes("a brick hung under the overhang","2x2","sky",21,1,0)
      no("a brick pushed in between baseplate and hung brick","2x2","sky",21,0,0)
      -- Nothing comes loose: the column's foot holds everything above it.
      assert(sep("on_use",20,0,0).name~="air","collected the only support")
      assert(sep("on_use",21,1,0).name=="air","couldn't collect the hung brick")
      assert(brickcraft.undo(player),"undo puts the hung brick back")
      assert(C.get_node(at(21,1,0)).name~="air","undo put the hung brick back")
      -- Turning: a 1 x 1 turned off the studs below, or a brick gripped from above too, stays.
      assert(sep("on_place",16,1,0).param2==0,"turned a 1 x 1 off its studs")
      assert(sep("on_place",12,0,0).param2==0,"turned a brick with a 2 x 4 on top")
      assert(sep("on_place",12,0,3).param2==1,"a tile with nothing on it turns in place")
      -- Technic: an axle needs a technic brick's hole on its line; a gear goes on the axle.
      no("an axle on its own","axle","navy",24,0,0)
      yes("a technic brick","technic_brick","navy",24,0,0)
      yes("an axle in its hole","axle","navy",24,0,1)
      yes("a gear on the axle","gear24","gold",24,0,2)
      no("an axle off the line","axle","navy",25,0,1)
      -- Trains: track needs studs; the passenger car isn't a real part.
      yes("track on the baseplate","track","navy",12,0,6)
      no("track on a tile","track","navy",12,1,3)
      no("the invented passenger car","coach","coral",12,0,6)
      yes("a cart on the track","cart","coral",12,0,6)
      -- The AI builder's order: a plan given top first is built bottom up; a floating piece
      -- never fits.
      local items={}
      for y=2,0,-1 do items[#items+1]={pos=at(8,y,-16),node={name="brickcraft:mint",param2=0}} end
      items[#items+1]={pos=at(10,3,-16),node={name="brickcraft:mint",param2=0}}
      local order,stuck=strict.order(items)
      assert(#order==3 and order[1].pos.y==0 and order[3].pos.y==2,"strict order builds bottom up")
      assert(#stuck==1 and stuck[1].pos.x==o.x+10,"strict order leaves out the floating piece")
      local loose=strict.loose_near(at(16,0,0),16)
      local where={}
      for i,q in ipairs(loose) do where[i]=(q.x-o.x)..","..q.y..","..(q.z-o.z) end
      assert(#loose==0,"loose pieces in the strict world at "..table.concat(where," "))
      -- The test house: which steps a strict world refuses.
      local refused={}
      for n,step in ipairs(house) do
        local piece,color,x,y,z,turn=unpack(step)
        if not put(piece,color,x-14,y,z+21,turn) then
          refused[#refused+1]=("%d %s %s at %d,%d,%d"):format(n,color,piece,x,y,z)
        end
      end
      C.log("action",("BRICKCRAFT STRICT HOUSE: %d of %d steps refused%s"):format(#refused,#house,
        #refused>0 and ": "..table.concat(refused,"; ") or ""))
      C.log("action","BRICKCRAFT STRICT PASS: placing, collecting, turning, undo, technic, track and AI order follow strict LEGO; the Workshop doesn't")
      C.request_shutdown("BrickCraft strict checks done",false,2)
    end

    -- The Workshop isn't strict: a brick held only at its side goes in, and /checkbuild
    -- finds it hanging loose.
    o={x=0,z=0}
    yes("a brick on the Workshop baseplate","2x2","coral",14,0,14)
    yes("a side-held brick in the Workshop","2x2","coral",15,1,14)
    local loose=brickcraft.strict.loose_near(at(14,0,14),3)
    assert(#loose==1 and vector.equals(loose[1],at(15,1,14)),"checkbuild finds the side-held brick")
    local w=brickcraft.make_world("Strict Test","builder",strict_checks,{strict=true})
    assert(w and w.strict,"made a strict world")
  end)
end)
