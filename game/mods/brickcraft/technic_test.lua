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
    local function switch(pos)
      C.registered_tools["brickcraft:separator"].on_place(inv:get_stack("main",1),player,
        {type="node",under=pos,above=vector.offset(pos,0,1,0)})
    end
    for x=14,19 do for z=5,9 do C.set_node({x=x,y=0,z=z},{name="air"}) end end
    -- Battery box, a motor facing +z, and gears with 8, 24 and 40 teeth side by side.
    local bat,motor={x=15,y=0,z=6},{x=16,y=0,z=6}
    local g8,g24,g40={x=16,y=0,z=7},{x=17,y=0,z=7},{x=18,y=0,z=7}
    place("battery","navy",bat); place("motor","navy",motor)
    place("gear8","gold",g8); place("gear24","coral",g24); place("gear40","sky",g40)
    assert(C.get_node(g24).name=="brickcraft:coral_gear24" and C.get_node(g24).param2==T.axis_param({x=0,y=0,z=1}),
      "a gear points the way you look")
    assert(count("navy")==97 and count("coral")==98,"each piece uses 1 brick")
    local function still() return T.spin(g8)==0 and T.spin(g24)==0 and T.spin(g40)==0 end
    C.after(.5,function()
      assert(still(),"nothing turns while the switch is off")
      switch(bat)
      wait(5,function() return T.spin(g8)~=0 end,function()
        assert(near(T.spin(g8),1) and near(T.spin(g24),-1/3) and near(T.spin(g40),.2),
          ("speeds 8: %s 24: %s 40: %s"):format(T.spin(g8),T.spin(g24),T.spin(g40)))
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
                  local lab
                  wait(60,function()
                    for _,w in ipairs(brickcraft.worlds()) do if w.name=="Technic Lab" then lab=w end end
                    return lab and lab.machines
                  end,function()
                    player:set_pos({x=lab.x+12,y=0,z=lab.z+0})
                    local function at(x,y,z) return {x=lab.x+x,y=y,z=lab.z+z} end
                    wait(15,function() return T.spin(at(14,1,3))~=0 and T.spin(at(18,4,4))~=0 and T.spin(at(15,2,-2))~=0 end,function()
                      assert(near(T.spin(at(12,1,3)),.2),"lab gear train: the 40 turns a fifth as fast")
                      assert(T.spin(at(18,1,-2))==0,"lab jam demo is jammed")
                      log("LAB: Technic Lab gear train, windmill and bearing line turn; the jam demo is jammed")
                      player:set_pos({x=lab.x+13,y=0,z=lab.z-8}); player:set_look_horizontal(0); player:set_look_vertical(.2)
                      log("PASS: technic pieces placed like any piece; gears, switch, jam, collect and the Technic Lab all work")
                      C.after(4,function() C.request_shutdown("BrickCraft technic checked",false,1) end)
                    end,function() return "lab machines not turning" end)
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
