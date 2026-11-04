-- Opt-in check (tools/test_models.py): models of real parts (brickcraft_models).
--   * The shared Model Gallery is a strict LEGO world in the world list with every sample
--     at the game's scale on its spot, each made of its parts while someone is near, with
--     support nodes to stand on.
--   * /model puts one down facing the player, at any size; the menu's size changes it.
--   * The first change asks, then resizes to the game's scale for good.
--   * Parts come off into the inventory: the game's pieces as game bricks, others as LEGO
--     part items; strict refuses a part that holds others up or carries a game brick.
--   * Break apart, rebuild in game bricks, and a LEGO part put down again.
local C=core
local function log(msg) C.log("action","BRICKCRAFT MODELS "..msg) end
local co
local function sleep(t) C.after(t,function() local ok,err=coroutine.resume(co); if not ok then error(err) end end); coroutine.yield() end

C.register_on_joinplayer(function(player)
  local name=player:get_player_name()
  C.after(2,function()
    co=coroutine.create(function()
      local M=brickcraft.models
      assert(#M.catalog>=6,"the sample models are in the catalog")
      local w
      for _=1,600 do w=M.gallery(); if w and w.built and w.gallery_models then break end; sleep(.1) end
      assert(w and w.gallery_models,"the Model Gallery world was made")
      assert(w.strict and brickcraft.strict.on({x=w.x,y=0,z=w.z}),"the gallery world is strict")
      local listed=false
      for _,o in ipairs(brickcraft.worlds()) do if o==w and o.name=="Model Gallery" then listed=true end end
      assert(listed,"the gallery is in the world list")
      local function at(x,y,z) return {x=w.x+x,y=y,z=w.z+z} end
      local inv=player:get_inventory()
      for i=1,inv:get_size("main") do inv:set_stack("main",i,"") end
      inv:set_stack("main",1,"brickcraft:separator")

      -- The gallery: one instance per sample, on its spot, facing the arrival spots.
      player:set_pos(at(0,1.5,2)); player:set_look_horizontal(0)
      local insts={}
      for _,inst in ipairs(M.instances()) do insts[inst.slug]=inst end
      for _,m in ipairs(M.catalog) do
        local inst=insts[m.slug]
        assert(inst,m.slug.." stands in the gallery")
        local spot=M.GALLERY[m.slug]
        assert(inst.x==w.x+spot.x and inst.z==w.z+spot.z and inst.y==-.5 and inst.turn==0,m.slug.." on its spot")
        assert((inst.scale or 1)==1 and not inst.modified,m.slug.." at the game's scale, not changed")
      end
      sleep(2.5)
      local total=0
      for _,m in ipairs(M.catalog) do
        local parts=M.spawned(insts[m.slug].id)
        local n=0; for _ in pairs(parts or {}) do n=n+1 end
        assert(n==#m.parts,m.slug..": "..n.." of "..#m.parts.." parts are there")
        total=total+n
      end
      -- One scale: the bonsai is 27 brick rows tall; a real 2 x 2 brick is one cell.
      local bonsai=M.models.bonsai
      assert(math.abs(bonsai.h-27.17)<.1,"the bonsai is 27 cells tall: "..bonsai.h)
      for _,p in ipairs(M.models.house.parts) do
        if p.part=="3003" then assert(math.abs(p.hx-.5)<.02 and math.abs(p.hy*2-1.18)<.05,"a 3003 is one cell (with its studs)") end
      end
      -- Support to stand on: the cat's middle column.
      local cat=insts.cat
      local n=0
      for _ in pairs(cat.support) do n=n+1 end
      assert(n>10 and C.get_node(at(-14,2,4)).name==M.SUPPORT,"support nodes fill the cat: "..n)
      log("Model Gallery: "..total.." real parts in "..#M.catalog.." models at the game's scale, support to stand on")

      -- /model at a size, facing the player; the size changes until the model is changed.
      player:set_pos(at(20,0.5,-22)); player:set_look_horizontal(0); player:set_look_vertical(0)
      sleep(.3)
      local ok,msg=M.place(name,"train 0.5")
      assert(ok and msg:find("size 0.5"),tostring(msg)); log(msg)
      local tr
      for _,inst in ipairs(M.instances()) do if inst.slug=="train" and inst~=insts.train then tr=inst end end
      assert(tr and tr.turn==0 and tr.scale==.5,"/model's half-size train faces the player")
      sleep(.2)
      local _,first=next(M.spawned(tr.id))
      assert(first:get_properties().visual_size.x==.5,"its parts are drawn at half size")
      M.resize(player,tr,2)
      assert(tr.scale==2,"resized to 2")
      assert(not M.place(name,"train 9"),"a size out of range is refused")
      -- The first change asks first, then resizes to 1 and keeps it there.
      local done=false
      M.before_change(player,tr,function() done=true end)
      assert(not done and not tr.modified,"the first change waits for the warning")
      assert(M.unify(player,tr) and tr.scale==1 and tr.modified,"yes: size 1 for good")
      M.resize(player,tr,2)
      assert(tr.scale==1,"a changed model keeps the game's scale")
      M.before_change(player,tr,function() done=true end)
      assert(done,"later changes don't ask again")
      log("/model at size 0.5, resized, then size 1 for good after the warning")

      -- Parts into the inventory: the game's pieces as game bricks, others as LEGO parts.
      local bricks_part,other_part
      for _,p in ipairs(bonsai.parts) do
        if p.part=="3003" then bricks_part=p elseif not other_part and p.part=="60479" then other_part=p end
      end
      local st,shape=M.item_for(bricks_part)
      assert(shape and shape.id=="2x2" and st:get_name():match("^brickcraft:%a+$"),"a 3003 is a game 2 x 2 brick: "..st:to_string())
      local rp=M.item_for(other_part or bonsai.parts[1])
      assert(rp:get_name()=="brickcraft:real_part" and rp:get_meta():get_string("mesh")~="","a 60479 is a LEGO part item")
      -- Strict: the train's ground part holds the rest; a top part comes off.
      local def=M.def_of(tr)
      local high=1
      for i,p in ipairs(def.parts) do
        if p.y+p.hy>def.parts[high].y+def.parts[high].hy then high=i end
      end
      -- A part some others hang from (the bonsai's baseplate holds the whole tree).
      local function holder(inst)
        local d=M.def_of(inst)
        for i in ipairs(d.parts) do
          local g=table.copy(inst.gone); g[i]=true
          if M.hanging(d,g)>M.hanging(d,inst.gone) then return i end
        end
      end
      local holds=holder(tr)
      local held_by=tr
      if not holds then held_by=insts.bonsai; assert(M.unify(player,held_by)); holds=holder(held_by) end
      assert(holds and not M.take_part(player,held_by,holds),"strict: a part holding others stays")
      assert(M.take_part(player,tr,high) and tr.gone[high],"a top part comes off")
      local got=0
      for i=2,inv:get_size("main") do got=got+inv:get_stack("main",i):get_count() end
      assert(got>0,"it went into the inventory")
      -- A game brick on the cat's top keeps the part under it (strict).
      local cdef=M.def_of(cat)
      assert(M.unify(player,cat))
      -- A part whose going takes away a support cell with air above it: a brick there.
      local top,brick
      for i in ipairs(cdef.parts) do
        local g=table.copy(cat.gone); g[i]=true
        local after=M.support_cells(cat,g)
        for k in pairs(cat.support) do
          local x,y,z=k:match("(-?%d+),(-?%d+),(-?%d+)")
          local above={x=tonumber(x),y=tonumber(y)+1,z=tonumber(z)}
          if not after[k] and C.get_node(above).name=="air" then top,brick=i,above; break end
        end
        if top then break end
      end
      assert(top,"a part with a support cell of its own")
      local stack=ItemStack("brickcraft:coral 5")
      stack:get_definition().on_place(stack,player,{type="node",under=brick,above=brick})
      assert(C.get_node(brick).name:match("^brickcraft:coral"),"a game brick goes on the model: "..C.get_node(brick).name)
      assert(not M.take_part(player,cat,top),"strict: the part under a game brick stays")
      C.remove_node(brick)
      log("parts come off into the inventory (3003 -> a game 2 x 2 brick), strict keeps parts that hold others or a brick")

      -- Break apart (all parts into the inventory) and rebuild in game bricks.
      for i=1,inv:get_size("main") do inv:set_stack("main",i,"") end
      M.break_all(player,tr)
      assert(not M.instance(tr.id),"the train is all taken apart")
      local items,real=0,nil
      for i=1,inv:get_size("main") do
        local s=inv:get_stack("main",i); items=items+s:get_count()
        if s:get_name()=="brickcraft:real_part" then real=s end
      end
      assert(items>0 and real,"its parts are in the inventory, some as LEGO parts")
      local car=insts.car
      assert(M.unify(player,car))
      local placed,left=M.convert(player,car)
      assert(placed and placed>20 and not M.instance(car.id),"the car is rebuilt in "..tostring(placed).." game bricks ("..tostring(left).." left out)")
      log("break apart: "..items.." pieces into the inventory; the car rebuilt in "..placed.." game bricks")

      -- A LEGO part goes down again as its own one-part model.
      local before=#M.instances()
      local cell=at(22,0,-14)
      local after=real:get_definition().on_place(ItemStack(real),player,{type="node",under=vector.offset(cell,0,-1,0),above=cell})
      assert(#M.instances()==before+1 and after:get_count()==real:get_count()-1,"a LEGO part goes down again")
      local one=M.instances()[#M.instances()]
      assert(one.part and one.modified and M.def_of(one).single,"as a one-part model")
      assert(M.take_part(player,one,1) and not M.instance(one.id),"and comes back up")
      log("a LEGO part from the inventory goes down and comes back up")

      -- Sent from BrickWright while the game runs (test_models.py sends the chick now):
      -- picked up from the world's inbox, in the catalog, in the gallery's front row.
      log("SEND")
      local sent
      for _=1,200 do
        for _,m in ipairs(M.catalog) do if m.record=="20261103-113209-e66a90db" then sent=m end end
        if sent then break end
        sleep(.1)
      end
      assert(sent,"the sent model was picked up from the inbox")
      sleep(3)
      local in_gallery
      for _,inst in ipairs(M.instances()) do if inst.slug==sent.slug then in_gallery=inst end end
      assert(in_gallery,"the sent model stands in the gallery")
      player:set_pos(at(in_gallery.x-w.x,1.5,in_gallery.z-w.z-6))
      sleep(2)
      local n=0; for _ in pairs(M.spawned(in_gallery.id) or {}) do n=n+1 end
      assert(n==#sent.parts,"its "..#sent.parts.." parts are there: "..n)
      log("sent from BrickWright: "..sent.title.." ("..sent.slug..", "..n.." parts) without a restart")

      player:set_pos(at(0,3,-14)); player:set_look_horizontal(0); player:set_look_vertical(.12)
      log("READY")
      sleep(4)
      log("PASS")
    end)
    local ok,err=coroutine.resume(co); if not ok then error(err) end
  end)
end)
