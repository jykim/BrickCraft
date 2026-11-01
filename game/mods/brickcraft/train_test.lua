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
        -- A locomotive: fit a motor and a battery box (right click holding them), and two
        -- cars put behind it hook on.
        inv:set_stack("main",14,"brickcraft:cart 5")
        local function put(pos)
          local it=inv:get_stack("main",14)
          it=it:get_definition().on_place(it,player,{type="node",under=pos,above=vector.offset(pos,0,1,0)})
          inv:set_stack("main",14,it)
          for _,o in ipairs(C.get_objects_inside_radius(pos,.6)) do
            local e2=o:get_luaentity()
            if e2 and e2.name=="brickcraft:cart" then return e2 end
          end
        end
        local loco=put(loop[3])
        for _,item in ipairs({"brickcraft:train_motor","brickcraft:battery_box"}) do
          inv:set_stack("main",1,item)
          loco.on_rightclick(loco,player)
        end
        inv:set_stack("main",1,"brickcraft:separator")
        assert(loco._motor and loco._battery and inv:get_stack("main",1):get_name()=="brickcraft:separator","motor and battery fitted")
        local car1,car2=put(loop[2]),put(loop[1])
        assert(car1._leader==loco._id and car2._leader==car1._id,"cars hook on behind the locomotive")
        local train={loco,car1,car2}
        local function stopped() for _,c in ipairs(train) do if c._v~=0 then return false end end return true end
        local function apart()
          local worst=0
          for i=2,3 do worst=math.max(worst,math.abs(math.abs(T.gap(train[i],train[i-1],3) or 9)-1)) end
          return worst
        end
        local function tstate() return ("loco %s v %.2f power %d, car gaps off by %.2f"):format(key(loco._cell),loco._v,loco._power,apart()) end
        C.after(.5,function()
          local parts=0
          for _,o in ipairs(loco.object:get_children()) do
            if o:get_luaentity() and o:get_luaentity().name=="brickcraft:cart_part" then parts=parts+1 end
          end
          assert(parts==2,"motor and battery box show on the locomotive, got "..parts)
          -- Switch forward: it pulls the cars round the loop with no one aboard.
          T.switch(loco,player)
          assert(loco._power==1,"switch forward")
          local moves,lastc,worst2,seen2=0,key(loco._cell),0,{}
          wait(30,function()
            if key(loco._cell)~=lastc then moves=moves+1; lastc=key(loco._cell) end
            seen2[key(car2._cell)]=true
            if moves>2 then worst2=math.max(worst2,apart()) end
            return moves>=#loop+2
          end,function()
            local n=0 for _ in pairs(seen2) do n=n+1 end
            assert(n==#loop,"the last car went all the way round, "..n.." pieces")
            assert(worst2<.3,"cars stay coupled, gaps off by "..worst2)
            log(("MOTOR: locomotive pulled 2 cars round the loop, gaps within %.2f of a cell"):format(worst2))
            T.switch(loco,player)
            assert(loco._power==0,"switch off")
            wait(10,stopped,function()
              -- Back: it pushes the cars the other way.
              local from_cell=key(car2._cell)
              T.switch(loco,player)
              assert(loco._power==-1,"switch back")
              local backs,lc=0,key(car2._cell)
              wait(15,function()
                if key(car2._cell)~=lc then backs=backs+1; lc=key(car2._cell) end
                return backs>=4
              end,function()
                assert(apart()<.3,"cars stay coupled when pushed, off by "..apart())
                log("BACK: pushed the cars 4 pieces from "..from_cell)
                T.switch(loco,player)
                wait(10,stopped,function()
                  -- Picking the locomotive up gives back the cart, motor and battery box.
                  local before={inv:get_stack("main",14):get_count()}
                  loco.on_punch(loco,player)
                  assert(not loco.object:get_pos() and inv:contains_item("main","brickcraft:train_motor") and
                    inv:contains_item("main","brickcraft:battery_box"),"separator picks the locomotive up with its parts")
                  for _,c in ipairs({car1,car2}) do c.on_punch(c,player) end
                  -- Leave a train going round for a look.
                  local look=T.put_train({loop[3],loop[2],loop[1]})
                  T.switch(look[1])
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
        -- Its train goes on when someone comes by.
        player:set_pos({x=yard.x+14.5,y=0,z=yard.z+2})
        wait(20,function() return yard.train end,function()
        C.after(1,function()
        local found=0
        for _,o in ipairs(C.get_objects_inside_radius({x=yard.x+16,y=0,z=yard.z+b.z},3)) do
          local e3=o:get_luaentity()
          if e3 and e3.name=="brickcraft:cart" then found=found+1 end
        end
        assert(found==3,"Train Yard train: "..found.." cars")
        log("YARD TRAIN: a locomotive and 2 cars on the Train Yard loop")
        player:set_pos({x=14.5,y=0,z=-3}); player:set_look_horizontal(0); player:set_look_vertical(.45)
        log("PASS: laid, rode a lap, stopped at a gap, undo, collect, pick up, motor, switch and coupled cars all work")
        C.after(6,function() C.request_shutdown("BrickCraft trains checked",false,1) end)
        end)
        end,function() return "Train Yard train not put on" end)
        end,function() return "Train Yard not built: "..(yard and "track missing" or "no world") end)
                end,tstate)
              end,tstate)
            end,tstate)
          end,tstate)
        end)
      end,state)
    end,state)
  end)
end)
