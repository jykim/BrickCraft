-- Opt-in check (tools/test_trains.py): lay a loop of track through the same on_place a
-- right click runs, put a cart on it, ride it all the way round, stop it at a gap.
local C=core
local T=brickcraft.trains
-- An 6 x 5 loop laid in order, starting mid-side so the last piece closes it.
local loop={}
for x=13,17 do loop[#loop+1]={x=x,y=0,z=2} end
for z=3,6 do loop[#loop+1]={x=17,y=0,z=z} end
for x=16,12,-1 do loop[#loop+1]={x=x,y=0,z=6} end
for z=5,2,-1 do loop[#loop+1]={x=12,y=0,z=z} end
local function key(p) return p.x..","..p.z end
local function log(msg) C.log("action","BRICKCRAFT TRAIN "..msg) end

-- Runs check() every step until it returns true, or fails after `limit` seconds.
local function wait(limit,check,done,what)
  local start=C.get_us_time()
  local function step()
    if check() then done(); return end
    assert(C.get_us_time()-start<limit*1e6,"timed out: "..what())
    C.after(0,step)
  end
  C.after(0,step)
end

C.register_on_joinplayer(function(player)
  C.after(3,function()
    local inv=player:get_inventory()
    inv:set_stack("main",13,"brickcraft:track 99"); inv:set_stack("main",14,"brickcraft:cart 2")
    player:set_look_horizontal(0); player:set_look_vertical(0)
    for x=11,18 do for z=1,7 do C.set_node({x=x,y=0,z=z},{name="air"}) end end
    local function lay(pos)
      local stack=inv:get_stack("main",13)
      stack=stack:get_definition().on_place(stack,player,{type="node",under=vector.offset(pos,0,-1,0),above=pos})
      inv:set_stack("main",13,stack)
    end
    for _,pos in ipairs(loop) do lay(pos) end
    local curves=0
    for _,pos in ipairs(loop) do
      assert(T.ends(pos),"track at "..key(pos))
      assert(#T.joined(pos)==2,"both ends joined at "..key(pos))
      if C.get_node(pos).name=="brickcraft:track_curve" then curves=curves+1 end
    end
    assert(curves==4,"4 corners curve, got "..curves)
    assert(inv:get_stack("main",13):get_count()==99-#loop,"each piece uses 1 track")
    -- Undo takes the last piece back; laying it again closes the loop.
    brickcraft.undo(player)
    assert(not T.ends(loop[#loop]) and inv:get_stack("main",13):get_count()==100-#loop,"undo lifts the last piece")
    lay(loop[#loop]); assert(#T.joined(loop[#loop])==2,"relaid piece closes the loop")
    log("LAID: "..#loop.." pieces, "..curves.." curves, loop closed")

    local item=inv:get_stack("main",14)
    item=item:get_definition().on_place(item,player,{type="node",under=loop[2],above=vector.offset(loop[2],0,1,0)})
    inv:set_stack("main",14,item)
    local cart
    for _,o in ipairs(C.get_objects_inside_radius(loop[2],.6)) do
      if o:get_luaentity() and o:get_luaentity().name=="brickcraft:cart" then cart=o end
    end
    assert(cart and item:get_count()==1,"cart put on the track")
    local ent=cart:get_luaentity()
    ent.on_rightclick(ent,player)
    assert(player:get_attach()==cart,"riding the cart")

    -- Run it round: every piece visited, back to the start, never off the centerline.
    ent._cruise=4
    local seen,count,worst,last={},0,0,key(loop[2])
    local function state() return ("cell %s v %.2f s %.2f, %d pieces passed"):format(key(ent._cell),ent._v,ent._s or -1,count) end
    wait(20,function()
      local k=key(ent._cell)
      if k~=last then count=count+1; last=k; seen[k]=true end
      local e=T.ends(ent._cell)
      local p=T.centerline(ent._cell,ent._from,T.exit_of(e,ent._from),ent._s)
      worst=math.max(worst,vector.distance({x=p.x,y=0,z=p.z},{x=cart:get_pos().x,y=0,z=cart:get_pos().z}))
      return count>=#loop
    end,function()
      for _,pos in ipairs(loop) do assert(seen[key(pos)],"visited "..key(pos)) end
      assert(key(ent._cell)==key(loop[2]),"back where it started")
      assert(worst<.35,"stays near the centerline, worst "..worst)
      log(("LAP: %d pieces, %.2f cells from the centerline at most"):format(count,worst))
      -- Take out a piece ahead: the cart stops at the gap.
      local gap=loop[9]
      assert(player:get_wielded_item():get_name()=="brickcraft:separator","holding the separator")
      C.registered_tools["brickcraft:separator"].on_use(inv:get_stack("main",1),player,
        {type="node",under=gap,above=vector.offset(gap,0,1,0)})
      assert(not T.ends(gap),"separator collects track")
      wait(20,function() return ent._v==0 and vector.distance(ent._cell,gap)==1 end,function()
        log("GAP: stopped next to "..key(gap))
        brickcraft.undo(player)
        assert(T.ends(gap) and #T.joined(gap)==2,"undo puts the collected piece back")
        ent._cruise=nil
        ent.on_rightclick(ent,player)
        assert(not player:get_attach(),"got off")
        ent.on_punch(ent,player)
        assert(not cart:get_pos() and inv:get_stack("main",14):get_count()==2,"separator picks the cart up")
        -- Leave one cart going round for a look.
        item=inv:get_stack("main",14)
        item=item:get_definition().on_place(item,player,{type="node",under=loop[1],above=vector.offset(loop[1],0,1,0)})
        inv:set_stack("main",14,item)
        for _,o in ipairs(C.get_objects_inside_radius(loop[1],.6)) do
          if o:get_luaentity() and o:get_luaentity().name=="brickcraft:cart" then o:get_luaentity()._cruise=2 end
        end
        player:set_pos({x=14.5,y=0,z=-3}); player:set_look_horizontal(0); player:set_look_vertical(.45)
        -- The Train Yard world is made at start with its own loop and a cart.
        local yard
        wait(60,function()
          for _,w in ipairs(brickcraft.worlds()) do if w.name=="Train Yard" then yard=w end end
          return yard and yard.track
        end,function()
        local a,b=brickcraft.yard,brickcraft.yard_far
        local pieces,carts=0,0
        for x=a.x,b.x do for z=a.z,b.z do
          local pos={x=yard.x+x,y=0,z=yard.z+z}
          if T.ends(pos) then pieces=pieces+1; assert(#T.joined(pos)==2,"yard loop closed at "..key(pos)) end
        end end
        assert(pieces==2*(b.x-a.x+b.z-a.z),"yard loop has "..pieces.." pieces")
        log(("YARD: Train Yard at %d,%d, %d pieces in a closed loop"):format(yard.x,yard.z,pieces))
        log("PASS: laid, rode a lap, stopped at a gap, undo, collect and pick up all work")
        C.after(6,function() C.request_shutdown("BrickCraft trains checked",false,1) end)
        end,function() return "Train Yard not built: "..(yard and "track missing" or "no world") end)
      end,state)
    end,state)
  end)
end)
