-- Opt-in check (tools/test_models.py): the display models (brickcraft_models) go into a
-- strict LEGO world with /model, life-size, facing the player; one won't stand on a plate
-- there; the scale argument sizes it; the separator turns one and puts one away. Leaves the
-- row standing for a screenshot (log "MODELS READY") before the last steps.
local C=core
local function log(msg) C.log("action","BRICKCRAFT MODELS "..msg) end
local co
local function sleep(t) C.after(t,function() local ok,err=coroutine.resume(co); if not ok then error(err) end end); coroutine.yield() end

local function models_near(pos,r)
  local found={}
  for _,obj in ipairs(C.get_objects_inside_radius(pos,r)) do
    local e=obj:get_luaentity()
    if e and e.name=="brickcraft:display_model" then found[#found+1]=e end
  end
  return found
end

C.register_on_joinplayer(function(player)
  local name=player:get_player_name()
  C.after(2,function()
    co=coroutine.create(function()
      local M=brickcraft.models
      assert(#M.catalog>=6,"the sample models are in the catalog")
      local built=false
      local w=brickcraft.make_world("Model Gallery","builder",function() built=true end,{strict=true})
      for _=1,600 do if built then break end; sleep(.1) end
      assert(built,"the gallery world was built")
      assert(brickcraft.strict.on({x=w.x,y=0,z=w.z}),"the gallery world is strict")
      local function at(x,y,z) return {x=w.x+x,y=y,z=w.z+z} end
      -- A clear stretch of baseplate (y -1) for the row: the world's piles and arch go.
      for x=-24,24 do for z=-20,20 do for y=0,20 do
        if C.get_node(at(x,y,z)).name~="air" then C.set_node(at(x,y,z),{name="air"}) end
      end end end
      local inv=player:get_inventory()
      inv:set_stack("main",1,"brickcraft:separator")
      -- A row along x at z = 6; the player steps back by each model's reach and looks +z.
      local row={bonsai=-14,house=0,cat=8,mech=15,train=21,car=-1}
      local zs={car=-6}
      for _,m in ipairs(M.catalog) do
        local x=row[m.slug] or 0
        local reach=math.max(m.w,m.d)/2+1.5
        player:set_pos(at(x,0.5,(zs[m.slug] or 6)-math.floor(reach+.5)))
        player:set_look_horizontal(0); player:set_look_vertical(0)
        sleep(.3)
        local ok,msg=M.place(name,m.slug)
        assert(ok,m.slug..": "..msg)
        log(msg)
      end
      sleep(.5)
      local all=models_near(at(0,0,6),40)
      assert(#all==#M.catalog,"one of each model is standing: "..#all)
      for _,e in ipairs(all) do
        local m
        for _,c in ipairs(M.catalog) do if c.slug==e._slug then m=c end end
        local p=e.object:get_properties()
        assert(p.mesh=="brickcraft_model_"..m.slug..".glb","mesh of "..m.slug)
        local box=p.selectionbox
        assert(math.abs((box[5]-box[2])-m.h)<.01,"life-size height of "..m.slug)
        local pos=e.object:get_pos()
        assert(math.abs(pos.y+.5)<.01,m.slug.." stands on the baseplate top: "..pos.y)
        assert((e._turn or 0)==0,m.slug.." faces the player")
      end
      log("6 life-size models stand in a row on the strict baseplate")

      -- Strict: not on a plate (no studs reach the cell above).
      C.set_node(at(-20,0,-14),{name="brickcraft:coral_plate"})
      assert(brickcraft.strict.describe(at(-20,0,-14),C.get_node(at(-20,0,-14))),"the plate is a piece")
      -- Stand so the model's middle lands on the cell at z -14.
      local function aim(slug,scale)
        local m; for _,c in ipairs(M.catalog) do if c.slug==slug then m=c end end
        player:set_pos(at(-20,0.5,-14-(math.max(m.w,m.d)*scale/2+1.5))); player:set_look_horizontal(0)
        sleep(.3)
      end
      aim("train",1)
      local ok,msg=M.place(name,"train")
      assert(not ok and msg:find("Strict"),"a model on a plate is refused: "..tostring(msg))
      C.set_node(at(-20,0,-14),{name="brickcraft:coral"})
      aim("cat",.5)
      ok,msg=M.place(name,"cat .5")
      assert(ok and msg:find("3 cells tall"),"on a brick, half size: "..tostring(msg))
      local small=models_near(at(-20,.5,-14),1.5)[1]
      assert(small and math.abs(small.object:get_pos().y-.5)<.01 and small._scale==.5,"the small cat sits on the brick")
      assert(not M.place(name,"cat 9"),"a scale out of range is refused")
      log("strict: refused on a plate, a half-size cat stands on a brick")

      -- The separator: right click turns it, left click puts it away.
      small:on_rightclick(player)
      assert(small._turn==1 and math.abs(small.object:get_yaw()-math.pi/2)<.01,"turned a quarter")
      local data=C.deserialize(small:get_staticdata())
      assert(data.slug=="cat" and data.turn==1 and data.scale==.5,"saved with its turn and scale")
      C.registered_tools["brickcraft:separator"].on_use(inv:get_stack("main",1),player,{type="object",ref=small.object})
      sleep(.2)
      assert(#models_near(at(-20,.5,-14),1.5)==0,"the separator put it away")
      log("separator turns a model and puts it away")

      -- The view for the screenshot: the whole row from behind the player's side.
      player:set_pos(at(1,4,-22)); player:set_look_horizontal(0); player:set_look_vertical(.18)
      log("READY")
      sleep(10)
      log("PASS")
    end)
    local ok,err=coroutine.resume(co); if not ok then error(err) end
  end)
end)
