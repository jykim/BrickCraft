-- Opt-in check (tools/test_models.py): the shared Model Gallery (brickcraft_models) is made
-- as a strict LEGO world in the world list, with every sample model life-size on its spot;
-- /model puts one in front of the player, facing them; one won't stand on a plate there;
-- the scale argument sizes it; the separator turns one and puts one away. Leaves the
-- gallery in view for a screenshot (log "MODELS READY") at the end.
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
      -- The shared Model Gallery is made on start, strict, with one of each model.
      local w
      for _=1,600 do w=M.gallery(); if w and w.built and w.gallery_models then break end; sleep(.1) end
      assert(w and w.gallery_models,"the Model Gallery world was made")
      assert(w.strict and brickcraft.strict.on({x=w.x,y=0,z=w.z}),"the gallery world is strict")
      local listed=false
      for _,o in ipairs(brickcraft.worlds()) do if o==w and o.name=="Model Gallery" then listed=true end end
      assert(listed,"the gallery is in the world list")
      local function at(x,y,z) return {x=w.x+x,y=y,z=w.z+z} end
      local inv=player:get_inventory()
      inv:set_stack("main",1,"brickcraft:separator")
      -- Placed while nobody was near, they were saved with the map; arriving wakes them.
      player:set_pos(at(0,1.5,2)); player:set_look_horizontal(0)
      local all
      for _=1,100 do all=models_near(at(0,0,4),40); if #all>=#M.catalog then break end; sleep(.1) end
      assert(#all==#M.catalog,"one of each model is standing: "..#all)
      for _,e in ipairs(all) do
        local m=nil
        for _,c in ipairs(M.catalog) do if c.slug==e._slug then m=c end end
        local p=e.object:get_properties()
        assert(p.mesh=="brickcraft_model_"..m.slug..".glb","mesh of "..m.slug)
        local box=p.selectionbox
        assert(math.abs((box[5]-box[2])-m.h)<.01,"life-size height of "..m.slug)
        local pos,spot=e.object:get_pos(),M.GALLERY[m.slug]
        assert(math.abs(pos.y+.5)<.01 and pos.x==w.x+spot.x and pos.z==w.z+spot.z,m.slug.." stands on its spot")
        assert((e._turn or 0)==0,m.slug.." faces the arrival spots")
        -- Footprints stay off the arrival spots and on the baseplate.
        assert(math.abs(spot.x)-m.w/2>6 or spot.z-m.d/2>4 or spot.z+m.d/2<1,m.slug.." clears the arrival spots")
        assert(math.abs(spot.x)+m.w/2<=24.5 and math.abs(spot.z)+m.d/2<=24.5,m.slug.." is on the baseplate")
      end
      assert(C.get_node(at(-18,0,10)).name=="air" and C.get_node(at(4,1,-7)).name=="air","stacks and arch made room")
      log("Model Gallery: "..#all.." life-size models in a strict world")

      -- /model puts one in front of the player and faces them.
      player:set_pos(at(20,0.5,-20)); player:set_look_horizontal(0); player:set_look_vertical(0)
      sleep(.3)
      local ok,msg=M.place(name,"train")
      assert(ok,msg); log(msg)
      local tr=models_near(at(20,-.5,-16),2)[1]
      assert(tr and tr._turn==0,"/model's train faces the player")
      tr.object:remove()

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

      -- The view for the screenshot: the gallery from behind the arrival spots.
      player:set_pos(at(0,3,-14)); player:set_look_horizontal(0); player:set_look_vertical(.12)
      log("READY")
      sleep(10)
      log("PASS")
    end)
    local ok,err=coroutine.resume(co); if not ok then error(err) end
  end)
end)
