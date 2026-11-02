-- Opt-in check (tools/test_trains.py): train pieces are placed like any piece (pick it,
-- hold a color, right click through the same on_place): lay a loop of track, put a cart on
-- it, ride it round, stop it at a gap, then make a locomotive and pull two cars.
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
    local slot={}
    for i,color in ipairs(brickcraft.colors) do
      if i<=8 then slot[color]=i+1; inv:set_stack("main",i+1,"brickcraft:"..color.." 99") end
    end
    local function count(color) return inv:get_stack("main",slot[color]):get_count() end
    -- A right click with a color and the chosen piece, through the color's own on_place.
    local function place(piece,color,under,above)
      brickcraft.set_shape(player,brickcraft.shapes[piece])
      local stack=inv:get_stack("main",slot[color])
      stack=stack:get_definition().on_place(stack,player,{type="node",under=under,above=above})
      inv:set_stack("main",slot[color],stack)
    end
    -- A right click on a cart, holding a color with the chosen piece (or the separator).
    local function click(ent,piece,color)
      if piece then brickcraft.set_shape(player,brickcraft.shapes[piece]) end
      local held=inv:get_stack("main",1)
      if color then inv:set_stack("main",1,inv:get_stack("main",slot[color])) end
      ent.on_rightclick(ent,player)
      if color then inv:set_stack("main",slot[color],inv:get_stack("main",1)); inv:set_stack("main",1,held) end
    end
    local function cart_at(pos)
      for _,o in ipairs(C.get_objects_inside_radius(pos,.6)) do
        local e=o:get_luaentity()
        if e and e.name=="brickcraft:cart" then return e end
      end
    end
    player:set_look_horizontal(0); player:set_look_vertical(0)
    for x=11,18 do for z=1,7 do C.set_node({x=x,y=0,z=z},{name="air"}) end end
    local function lay(pos) place("track","navy",vector.offset(pos,0,-1,0),pos) end
    for _,pos in ipairs(loop) do lay(pos) end
    local curves=0
    for _,pos in ipairs(loop) do
      assert(T.ends(pos),"track at "..key(pos))
      assert(#T.joined(pos)==2,"both ends joined at "..key(pos))
      if C.get_node(pos).name=="brickcraft:navy_track_curve" then curves=curves+1 end
    end
    assert(curves==4,"4 corners curve, got "..curves)
    assert(count("navy")==99-#loop,"each piece uses 1 navy brick")
    -- Undo takes the last piece back; laying it again closes the loop.
    brickcraft.undo(player)
    assert(not T.ends(loop[#loop]) and count("navy")==100-#loop,"undo lifts the last piece")
    lay(loop[#loop]); assert(#T.joined(loop[#loop])==2,"relaid piece closes the loop")
    log("LAID: "..#loop.." navy pieces, "..curves.." curves, loop closed")

    place("cart","coral",loop[2],vector.offset(loop[2],0,1,0))
    local ent=cart_at(loop[2])
    assert(ent and count("coral")==97,"a coral cart on the track for 2 coral bricks")
    local cart=ent.object
    -- Landing on the deck boards it.
    local cp=cart:get_pos()
    player:set_pos({x=cp.x,y=cp.y+.15,z=cp.z})
    wait(5,function() return player:get_attach()==cart end,function()
    log("BOARD: landed on the cart and rides it")

    -- Run it round: every piece visited, back to the start, never off the centerline.
    ent._cruise=4
    local seen,moved,worst,last={},0,0,key(loop[2])
    local function state() return ("cell %s v %.2f s %.2f, %d pieces passed"):format(key(ent._cell),ent._v,ent._s or -1,moved) end
    wait(20,function()
      local k=key(ent._cell)
      if k~=last then moved=moved+1; last=k; seen[k]=true end
      local e=T.path_ends(ent._cell)
      local p=T.centerline(ent._cell,ent._from,T.other_end(e,ent._from),ent._s)
      worst=math.max(worst,vector.distance({x=p.x,y=0,z=p.z},{x=cart:get_pos().x,y=0,z=cart:get_pos().z}))
      return moved>=#loop
    end,function()
      for _,pos in ipairs(loop) do assert(seen[key(pos)],"visited "..key(pos)) end
      assert(key(ent._cell)==key(loop[2]),"back where it started")
      assert(worst<.35,"stays near the centerline, worst "..worst)
      assert(player:get_attach()==cart,"rode all the way round")
      log(("LAP: %d pieces with a rider, %.2f cells from the centerline at most"):format(moved,worst))
      -- Take out a piece ahead: the cart stops at the gap.
      local gap=loop[9]
      assert(player:get_wielded_item():get_name()=="brickcraft:separator","holding the separator")
      C.registered_tools["brickcraft:separator"].on_use(inv:get_stack("main",1),player,
        {type="node",under=gap,above=vector.offset(gap,0,1,0)})
      assert(not T.ends(gap) and count("navy")==100-#loop,"separator collects track, a brick back")
      wait(20,function() return ent._v==0 and vector.distance(ent._cell,gap)==1 end,function()
        log("GAP: stopped next to "..key(gap))
        brickcraft.undo(player)
        assert(T.ends(gap) and #T.joined(gap)==2,"undo puts the collected piece back")
        ent._cruise=nil
        T.hop_off(ent,player)
        assert(not player:get_attach(),"hopped off")
        C.after(.3,function()
        assert(not player:get_attach(),"doesn't land straight back on")
        ent.on_punch(ent,player)
        assert(not cart:get_pos() and count("coral")==99,"separator collects the cart, 2 coral back")

        -- A locomotive: a cart, then the motor and battery box pieces on it (right click it
        -- holding navy), then two cars put behind it hook on.
        place("cart","coral",loop[3],vector.offset(loop[3],0,1,0))
        local loco=cart_at(loop[3])
        local navy=count("navy")
        click(loco,"motor","navy"); click(loco,"battery","navy")
        assert(loco._motor=="navy" and loco._battery=="navy" and count("navy")==navy-2,"motor and battery box on, a navy brick each")
        assert(inv:get_stack("main",1):get_name()=="brickcraft:separator","separator back in hand")
        place("cart","gold",loop[2],vector.offset(loop[2],0,1,0))
        place("cart","gold",loop[1],vector.offset(loop[1],0,1,0))
        local car1,car2=cart_at(loop[2]),cart_at(loop[1])
        assert(car1._leader==loco._id and car2._leader==car1._id,"cars hook on behind the locomotive")
        local train={loco,car1,car2}
        local function stopped() for _,c in ipairs(train) do if c._v~=0 then return false end end return true end
        local function apart()
          local w=0
          for i=2,3 do w=math.max(w,math.abs(math.abs(T.gap(train[i],train[i-1],3) or 9)-1)) end
          return w
        end
        local function tstate() return ("loco %s v %.2f power %d, car gaps off by %.2f"):format(key(loco._cell),loco._v,loco._power,apart()) end
        C.after(.5,function()
          local parts=0
          for _,o in ipairs(loco.object:get_children()) do
            if o:get_luaentity() and o:get_luaentity().name=="brickcraft:cart_part" then parts=parts+1 end
          end
          assert(parts==2,"motor and battery box show on the locomotive, got "..parts)
          -- The separator's right click switches it forward: it pulls the cars round.
          click(loco)
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
            click(loco)
            assert(loco._power==0,"switch off")
            wait(10,stopped,function()
              -- Back: it pushes the cars the other way.
              local from_cell=key(car2._cell)
              click(loco)
              assert(loco._power==-1,"switch back")
              local backs,lc=0,key(car2._cell)
              wait(15,function()
                if key(car2._cell)~=lc then backs=backs+1; lc=key(car2._cell) end
                return backs>=4
              end,function()
                assert(apart()<.3,"cars stay coupled when pushed, off by "..apart())
                log("BACK: pushed the cars 4 pieces from "..from_cell)
                click(loco)
                wait(10,stopped,function()
                  -- Collecting the locomotive gives back its bricks and its parts' bricks.
                  local coral,nv=count("coral"),count("navy")
                  loco.on_punch(loco,player)
                  assert(not loco.object:get_pos() and count("coral")==coral+2 and count("navy")==nv+2,
                    "separator collects the locomotive: 2 coral, motor and battery box 2 navy")
                  for _,c in ipairs({car1,car2}) do c.on_punch(c,player) end
                  -- Leave a train going round for a look.
                  local look=T.put_train({loop[3],loop[2],loop[1]},"coral")
                  T.switch(look[1])
                  player:set_pos({x=14.5,y=0,z=-3}); player:set_look_horizontal(0); player:set_look_vertical(.45)
                  -- The Train Yard world is made at start with its own loop.
                  local yard
                  wait(60,function()
                    for _,w in ipairs(brickcraft.worlds()) do if w.name=="Train Yard" then yard=w end end
                    return yard and yard.track
                  end,function()
                    local a,b=brickcraft.trains.yard,brickcraft.trains.yard_far
                    local pieces=0
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
                        -- The line from the Workshop to Train Yard: one track all the way, two
                        -- curves; the shuttle waits at the Workshop end and rides across.
                        wait(60,function() return yard.line end,function()
                          local path=brickcraft.trains.line_path(yard)
                          C.load_area({x=yard.x+20,y=-1,z=yard.z-4},{x=-20,y=1,z=4})
                          local bends=0
                          for i,pos in ipairs(path) do
                            assert(T.ends(pos),"line track at "..key(pos))
                            if #T.joined(pos)~=((i==1 or i==#path) and 1 or 2) then
                              local around={}
                              for dx=-1,1 do for dz=-1,1 do
                                local n=C.get_node({x=pos.x+dx,y=0,z=pos.z+dz})
                                around[#around+1]=(pos.x+dx)..","..(pos.z+dz).."="..n.name:gsub("brickcraft:","").."/"..n.param2
                              end end
                              error("line joined "..#T.joined(pos).." at "..key(pos)..": "..table.concat(around," "))
                            end
                            if C.get_node(pos).name=="brickcraft:navy_track_curve" then bends=bends+1 end
                          end
                          assert(bends==2,"the line has 2 curves, got "..bends)
                          log(("LINE: %d pieces from the Workshop to Train Yard, %d curves"):format(#path,bends))
                          player:set_pos({x=-22,y=0,z=0})
                          wait(20,function() return yard.shuttle end,function()
                            C.after(1,function()
                              local shuttle=cart_at({x=-28,y=0,z=0})
                              assert(shuttle and shuttle._motor,"shuttle locomotive at the Workshop end")
                              local sp=shuttle.object:get_pos()
                              player:set_pos({x=sp.x,y=sp.y+.15,z=sp.z})
                              wait(5,function() return player:get_attach()==shuttle.object end,function()
                                -- Head west (toward Train Yard) at full speed.
                                shuttle._from,shuttle._flip,shuttle._cruise={x=1,y=0,z=0},false,5
                                local stop=path[#path]
                                wait(120,function() return shuttle._v==0 and vector.distance(shuttle._cell,stop)<=1 and shuttle._s end,function()
                                  local w=brickcraft.world_at(player:get_pos())
                                  assert(w.name=="Train Yard","rode into Train Yard, got "..w.name)
                                  log("RIDE: rode the shuttle from the Workshop to the end of the line in Train Yard")
                                  T.hop_off(shuttle,player)
                                  player:set_pos({x=14.5,y=0,z=-3}); player:set_look_horizontal(0); player:set_look_vertical(.45)
                                  log("PASS: train pieces placed like any piece; ride, gap, undo, collect, locomotive, switch, coupled cars and the line to Train Yard all work")
                                  C.after(6,function() C.request_shutdown("BrickCraft trains checked",false,1) end)
                                end,function() return "shuttle at "..key(shuttle._cell).." v "..shuttle._v end)
                              end,function() return "not on the shuttle" end)
                            end)
                          end,function() return "shuttle not put on" end)
                        end,function() return "line not built" end)
                      end)
                    end,function() return "Train Yard train not put on" end)
                  end,function() return "Train Yard not built: "..(yard and "track missing" or "no world") end)
                end,tstate)
              end,tstate)
            end,tstate)
          end,tstate)
        end)
        end)
      end,state)
    end,state)
    end,function() return "player not on the cart" end)
  end)
end)
