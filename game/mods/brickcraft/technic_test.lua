-- Opt-in check (tools/test_technic.py): technic pieces placed like any piece (pick it,
-- hold a color, right click through the same on_place) make a gear train that a motor
-- turns; the battery box's switch (separator right click) runs it forward, stops it and
-- runs it back; a second motor jams it; the Technic Lab world runs its machines.
local C=core
local T=brickcraft.technic
local function log(msg) C.log("action","BRICKCRAFT TECHNIC "..msg) end
local function wait(limit,check,done,what)
  local start=C.get_us_time()
  local function step()
    if check() then done(); return end
    assert(C.get_us_time()-start<limit*1e6,"timed out: "..what())
    C.after(0,step)
  end
  C.after(0,step)
end
local function near(a,b) return math.abs(a-b)<1e-6 end

C.register_on_joinplayer(function(player)
  C.after(3,function()
    local inv=player:get_inventory()
    local slot={}
    for i,color in ipairs(brickcraft.colors) do
      if i<=8 then slot[color]=i+1; inv:set_stack("main",i+1,"brickcraft:"..color.." 99") end
    end
    local function count(color) return inv:get_stack("main",slot[color]):get_count() end
    local function place(piece,color,pos,yaw)
      player:set_look_horizontal(yaw or 0); player:set_look_vertical(0)
      brickcraft.set_shape(player,brickcraft.shapes[piece])
      local stack=inv:get_stack("main",slot[color])
      stack=stack:get_definition().on_place(stack,player,{type="node",under=vector.offset(pos,0,-1,0),above=pos})
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
    local function parts(ent)
      local out={}
      for _,o in ipairs(ent.object:get_children()) do
        local e=o:get_luaentity()
        if e and e.name=="brickcraft:cart_part" then out[#out+1]=o end
      end
      return out
    end
    local function switch(pos)
      C.registered_tools["brickcraft:separator"].on_place(inv:get_stack("main",1),player,
        {type="node",under=pos,above=vector.offset(pos,0,1,0)})
    end
    for x=14,24 do for y=0,2 do for z=5,9 do C.set_node({x=x,y=y,z=z},{name="air"}) end end end
    -- Battery box, a motor facing +z, then gears at their meshing spacing: an 8, a 24 right
    -- next to it, a 40 two cells on, another 24 two cells on, and a 24 on a diagonal from it.
    local bat,motor={x=15,y=0,z=6},{x=16,y=0,z=6}
    local g8,g24,g40,g24a,g24b={x=16,y=0,z=7},{x=17,y=0,z=7},{x=19,y=0,z=7},{x=21,y=0,z=7},{x=22,y=1,z=7}
    place("battery","navy",bat); place("motor","navy",motor)
    place("gear8","gold",g8); place("gear24","coral",g24); place("gear40","sky",g40)
    place("gear24","coral",g24a)
    C.set_node({x=22,y=0,z=7},{name="brickcraft:cream"})
    place("gear24","coral",g24b)
    assert(C.get_node(g24b).name=="brickcraft:coral_gear24","a 24 fits on a diagonal from a 24")
    -- A gear that would bump another (a 24 right next to a 24) doesn't go in.
    local before=count("coral")
    place("gear24","coral",{x=18,y=0,z=7})
    assert(C.get_node({x=18,y=0,z=7}).name=="air" and count("coral")==before,"a gear can't overlap another")
    assert(C.get_node(g24).name=="brickcraft:coral_gear24" and C.get_node(g24).param2==T.axis_param({x=0,y=0,z=1}),
      "a gear points the way you look")
    assert(count("navy")==97 and count("coral")==96,"each piece uses 1 brick")
    local function still() return T.spin(g8)==0 and T.spin(g24)==0 and T.spin(g40)==0 end
    C.after(.5,function()
      assert(still(),"nothing turns while the switch is off")
      switch(bat)
      wait(5,function() return T.spin(g8)~=0 end,function()
        assert(near(T.spin(g8),1) and near(T.spin(g24),-1/3) and near(T.spin(g40),.2) and
          near(T.spin(g24a),-1/3) and near(T.spin(g24b),1/3),
          ("speeds 8: %s 24: %s 40: %s 24: %s 24: %s"):format(T.spin(g8),T.spin(g24),T.spin(g40),T.spin(g24a),T.spin(g24b)))
        for _,pair in ipairs({{g8,g24},{g24,g40},{g40,g24a},{g24a,g24b}}) do
          assert(T.phase_off(pair[1],pair[2])<1e-6,"teeth start interlocked")
        end
        log("RATIOS: 8 -> 24 -> 40 -> 24 -> diagonal 24 turn at 1, -1/3, 1/5, -1/3, 1/3, teeth interlocked")
        assert(C.get_node(g24).name=="brickcraft:coral_gear24_spin","a turning gear's spinner draws it")
        local a=T.active[g24.x..","..g24.y..","..g24.z]
        assert(a.obj and a.obj:get_pos() and near(a.obj:get_properties().automatic_rotate,-2*math.pi/3),"the 24 spins a third as fast, the other way")
        log("TRAIN: motor turns the 8 once a second, the 24 a third as fast the other way, the 40 a fifth")
        switch(bat)
        wait(5,still,function()
          assert(C.get_node(g24).name=="brickcraft:coral_gear24","a still gear is drawn again")
          switch(bat)
          wait(5,function() return T.spin(g8)~=0 end,function()
            assert(near(T.spin(g8),-1),"switched back: it turns the other way")
            log("SWITCH: forward, off and back")
            -- A second motor on the 8's axle, facing the first (-z). The first runs back;
            -- facing it, forward turns the axle the same way, back fights it.
            local bat2,motor2={x=15,y=0,z=8},{x=16,y=0,z=8}
            place("battery","navy",bat2); place("motor","navy",motor2,math.pi)
            assert(C.get_node(motor2).param2==2,"the second motor faces -z")
            switch(bat2)
            C.after(.5,function()
            assert(near(T.spin(g8),-1) and not next(T.jammed()),"two motors turning it the same way")
            switch(bat2); switch(bat2) -- off, then back
            wait(5,function() return still() and next(T.jammed()) end,function()
              log("JAM: two motors turning it different ways stop it")
              switch(bat2); switch(bat2) -- off, then forward again
              wait(5,function() return near(T.spin(g8),-1) and near(T.spin(g40),-.2) end,function()
                log("UNJAM: switched the other way, both motors turn it together")
                -- Collecting the 24 cuts the train: the 40 stops, the 8 still turns.
                local coral=count("coral")
                C.registered_tools["brickcraft:separator"].on_use(inv:get_stack("main",1),player,
                  {type="node",under=g24,above=vector.offset(g24,0,1,0)})
                assert(C.get_node(g24).name=="air" and count("coral")==coral+1,"separator collects a turning gear")
                wait(5,function() return T.spin(g40)==0 and T.spin(g8)~=0 end,function()
                  log("COLLECT: taking the 24 out stops the 40")
                  -- A geared locomotive: a cart, a motor and battery box, then an 8 on the
                  -- motor and a 24 on the wheels: it runs a third as fast as straight drive,
                  -- pulling a passenger car.
                  for x=-23,-11 do for y=0,2 do for z=-5,5 do C.set_node({x=x,y=y,z=z},{name="air"}) end end end
                  local cells=brickcraft.trains.lay_loop({x=-22,y=0,z=-4},{x=-12,y=0,z=4},"navy")
                  local function put(piece,color,pos) brickcraft.set_shape(player,brickcraft.shapes[piece])
                    local st=inv:get_stack("main",slot[color])
                    st=st:get_definition().on_place(st,player,{type="node",under=pos,above=vector.offset(pos,0,1,0)})
                    inv:set_stack("main",slot[color],st) end
                  put("cart","coral",cells[3])
                  local loco=cart_at(cells[3])
                  click(loco,"motor","navy"); click(loco,"battery","navy")
                  click(loco,"gear8","gold"); click(loco,"gear24","coral")
                  assert(loco._gear_m.teeth==8 and loco._gear_w.teeth==24,"an 8 on the motor, a 24 on the wheels")
                  assert(near(brickcraft.trains.motor_speed(loco),1),"8 to 24: a third of straight drive")
                  put("coach","sky",cells[2])
                  local coach=cart_at(cells[2])
                  assert(coach and coach._coach and coach._leader==loco._id,"the passenger car hooks on")
                  click(loco) -- the separator switches it on
                  local fast=0
                  wait(20,function()
                    if math.abs(loco._v-1)<.01 then fast=fast+1 end
                    return fast>20 and coach._v>.9
                  end,function()
                    local lp,cp=parts(loco),parts(coach)
                    assert(#lp==6 and #cp==1,"locomotive shows motor, battery box, 2 gears, 2 drive wheels; the car its cabin: "..#lp.." "..#cp)
                    local mg,wg=loco._parts.gear_m:get_properties().automatic_rotate,loco._parts.gear_w:get_properties().automatic_rotate
                    assert(math.abs(mg/wg+3)<.01,"the 8 turns 3 times as fast as the 24, the other way: "..mg.." "..wg)
                    assert(math.abs(math.abs(brickcraft.trains.gap(coach,loco,3))-1)<.3,"the car follows a cell behind")
                    log(("GEARED: an 8 on the motor drives a 24 on the wheels: 1 cell a second (straight drive 3); gears turn %.2f and %.2f rad/s; passenger car follows"):format(mg,wg))
                    click(loco)
                  local lab
                  wait(60,function()
                    for _,w in ipairs(brickcraft.worlds()) do if w.name=="Technic Lab" then lab=w end end
                    return lab and lab.machines
                  end,function()
                    player:set_pos({x=lab.x+0,y=0,z=lab.z+0})
                    local function at(x,y,z) return {x=lab.x+x,y=y,z=lab.z+z} end
                    wait(15,function() return T.spin(at(16,2,3))~=0 and T.spin(at(19,4,4))~=0 and T.spin(at(15,3,-1))~=0 end,function()
                      assert(near(T.spin(at(13,2,3)),.2) and near(T.spin(at(16,2,3)),1),"lab gear train: the 40 a fifth, the last 8 as fast as the first")
                      assert(T.spin(at(19,1,-3))==0,"lab jam demo is jammed")
                      local moving
                      wait(20,function()
                        for _,o in ipairs(C.get_objects_inside_radius(at(-15,0,1),12)) do
                          local e=o:get_luaentity()
                          if e and e.name=="brickcraft:cart" and e._gear_m and e._v>2.9 then moving=e end
                        end
                        return moving
                      end,function()
                      log("LAB TRAIN: the lab's geared train (24 to 24) runs at 3 cells a second with its passenger car")
                      log("LAB: Technic Lab gear train, windmill and bearing line turn; the jam demo is jammed")
                      player:set_pos({x=lab.x+13,y=0,z=lab.z-8}); player:set_look_horizontal(0); player:set_look_vertical(.2)
                      log("PASS: technic pieces placed like any piece; gears, switch, jam, collect and the Technic Lab all work")
                      C.after(4,function() C.request_shutdown("BrickCraft technic checked",false,1) end)
                      end,function() return "lab geared train not running" end)
                    end,function() return "lab machines not turning" end)
                  end,function() return "geared loco v "..loco._v.." car v "..coach._v end)
                  end,function() return "Technic Lab not built" end)
                end,function() return "after collect: 40 "..T.spin(g40).." 8 "..T.spin(g8) end)
              end,function() return "unjam: 8 "..T.spin(g8) end)
            end,function() return "no jam: 8 "..T.spin(g8) end)
            end)
          end,function() return "not back" end)
        end,function() return "didn't stop" end)
      end,function() return "nothing turned" end)
    end)
  end)
end)
