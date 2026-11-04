-- Opt-in check (tools/test_models.py): models of real parts (brickcraft_models).
--   * The shared Model Gallery is a strict LEGO world in the world list with every sample
--     at minifig scale on its spot, each made of its parts while someone is near, with
--     support nodes to stand on.
--   * /model puts one down facing the player, at any size; the menu's size changes it.
--   * The first change asks, then resizes to minifig scale for good.
--   * Parts come off into the inventory: the game's pieces as game bricks, others as LEGO
--     part items with their own picture, standing upright; strict refuses a part that
--     carries a game brick, and what a part held up falls when it comes off (gravity).
--   * Stack its parts; F / right button opens the menu (not tested: needs a real click).
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
        assert(inst.scale==M.DEFAULT_SCALE and not inst.modified,m.slug.." at minifig scale, not changed")
      end
      -- Media on demand: the files come once the player is near, then the parts appear.
      assert(not C.get_dir_list(C.get_modpath("brickcraft_models").."/models",false) or
        #C.get_dir_list(C.get_modpath("brickcraft_models").."/models",false)==0,"no model files in the join-time media")
      local t0=C.get_us_time()
      local total,complete=0,false
      for _=1,300 do
        total,complete=0,true
        for _,m in ipairs(M.catalog) do
          local n=0; for _ in pairs(M.spawned(insts[m.slug].id) or {}) do n=n+1 end
          if n~=#m.parts then complete=false end
          total=total+n
        end
        if complete then break end
        sleep(.1)
      end
      assert(complete,"every part is there once the files came: "..total)
      assert(M.has_media(name,M.files_of(M.models.bonsai)),"the player has the bonsai's files")
      log(string.format("media on demand: the gallery's files came in %.1f s",(C.get_us_time()-t0)/1e6))
      -- Real proportions: the bonsai is 27 brick rows (16.3 cells of 16 mm) tall; a real 2 x 2
      -- brick is one cell across and 11.3 mm tall with its studs.
      local bonsai=M.models.bonsai
      assert(math.abs(bonsai.h-16.3)<.1,"the bonsai is 16.3 cells tall: "..bonsai.h)
      for _,p in ipairs(M.models.house.parts) do
        if p.part=="3003" then assert(math.abs(p.hx-.5)<.02 and math.abs(p.hy*2-.71)<.03,"a 3003 is one cell across, 11.3 mm tall") end
      end
      -- Support to stand on: the cat's middle column.
      local cat=insts.cat
      local n=0
      for _ in pairs(cat.support) do n=n+1 end
      assert(n>10 and C.get_node(at(-14,2,4)).name==M.SUPPORT,"support nodes fill the cat: "..n)
      log("Model Gallery: "..total.." real parts in "..#M.catalog.." models at minifig scale, support to stand on")

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
      -- The menu's size box: Enter (no button) and a decimal comma both work.
      local menu_fields=C.registered_on_player_receive_fields
      local function menu_send(fields)
        for _,f in ipairs(menu_fields) do if f(player,"brickcraft_models:menu",fields) then return end end
      end
      local _,one=next(M.spawned(tr.id))
      one:get_luaentity().on_rightclick(one:get_luaentity(),player) -- opens the menu (separator in hand)
      menu_send({size="0,5",key_enter_field="size",key_enter="true"})
      assert(tr.scale==.5,"Enter in the size box resizes: "..tostring(tr.scale))
      M.resize(player,tr,2)
      assert(not M.place(name,"train 9"),"a size out of range is refused")
      -- The first change asks first, then resizes to 1 and keeps it there.
      local done=false
      M.before_change(player,tr,function() done=true end)
      assert(not done and not tr.modified,"the first change waits for the warning")
      assert(M.unify(player,tr) and tr.scale==M.DEFAULT_SCALE and tr.modified,"yes: minifig scale for good")
      M.resize(player,tr,2)
      assert(tr.scale==M.DEFAULT_SCALE,"a changed model keeps minifig scale")
      M.before_change(player,tr,function() done=true end)
      assert(done,"later changes don't ask again")
      log("/model at size 0.5, resized, then minifig scale for good after the warning")

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
      assert(M.take_part(player,tr,high) and tr.gone[high],"a top part comes off")
      -- Gravity: the bonsai's baseplate holds the whole tree; taken off, the tree falls onto
      -- the world's baseplate, a model of its own.
      local bon=insts.bonsai
      assert(M.unify(player,bon))
      local holds=next(M.def_of(bon).ground)
      local bdef=M.def_of(bon)
      local g=table.copy(bon.gone); g[holds]=true
      local nfall=M.hanging(bdef,g)
      local high_before=-1e9
      for i,p in ipairs(bdef.parts) do if i~=holds then high_before=math.max(high_before,M.box_of(bon,p).top) end end
      assert(nfall>100 and M.take_part(player,bon,holds),"the baseplate comes off: "..nfall.." parts lose their hold")
      local fell
      for _,o in ipairs(M.instances()) do if o.custom and #o.custom.parts==nfall then fell=o end end
      assert(fell,"what it held is a model of its own")
      local low,high_after=1e9,-1e9
      for _,p in ipairs(M.def_of(fell).parts) do
        local b=M.box_of(fell,p); low=math.min(low,b.yb); high_after=math.max(high_after,b.top)
      end
      assert(math.abs(low+.5)<.05,"it landed on the baseplate: "..low)
      assert(high_after<high_before-.1,"it came down: "..high_before.." -> "..high_after)
      assert(not M.instance(bon.id) or #M.def_of(bon).parts>0,"the bonsai's own instance is gone or keeps the rest")
      log("gravity: the bonsai's baseplate off, "..nfall.." parts fell "..string.format("%.2f",high_before-high_after).." cells onto the world's baseplate")
      -- A LEGO part's item has its own picture.
      local lp
      for i=1,inv:get_size("main") do if inv:get_stack("main",i):get_name()=="brickcraft:real_part" then lp=inv:get_stack("main",i) end end
      assert(lp and lp:get_meta():get_string("inventory_image"):find("%.png%^%[multiply:#"),"a LEGO part shows its own picture")
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
      log("parts come off into the inventory (3003 -> a game 2 x 2 brick), strict keeps a part with a brick on it")

      -- Stack its parts: the mech into neat stacks, one kind and colour each, upright.
      local mech=insts.mech
      local mdef=M.def_of(mech)
      local stacks=M.organize(player,mech) -- no warning: the model goes away
      assert(stacks and not M.instance(mech.id),"the mech is sorted into stacks")
      local sdef=M.def_of(stacks)
      assert(#sdef.parts==#mdef.parts,"every part is in a stack: "..#sdef.parts)
      local kinds={}
      for _,q in ipairs(sdef.parts) do kinds[q.part..q.color]=true; assert(q.mesh==q.umesh,"stacked parts stand upright") end
      local nk=0; for _ in pairs(kinds) do nk=nk+1 end
      local lowest=1e9
      for i in pairs(sdef.ground) do lowest=math.min(lowest,M.box_of(stacks,sdef.parts[i]).yb) end
      assert(math.abs(lowest+.5)<.01,"the stacks stand on the baseplate")
      log("stack its parts: the mech's "..#sdef.parts.." parts in stacks of "..nk.." kinds")

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
      assert(placed and placed>10 and not M.instance(car.id),"the car is rebuilt in "..tostring(placed).." game bricks ("..tostring(left).." left out)")
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
      sleep(1)
      local in_gallery
      for _,inst in ipairs(M.instances()) do if inst.slug==sent.slug then in_gallery=inst end end
      assert(in_gallery,"the sent model stands in the gallery")
      player:set_pos(at(in_gallery.x-w.x,1.5,in_gallery.z-w.z-6))
      local n=0
      for _=1,150 do
        n=0; for _ in pairs(M.spawned(in_gallery.id) or {}) do n=n+1 end
        if n==#sent.parts then break end
        sleep(.1)
      end
      assert(n==#sent.parts,"its "..#sent.parts.." parts are there: "..n)
      log("sent from BrickWright: "..sent.title.." ("..sent.slug..", "..n.." parts) without a restart")

      -- What a player did: a size-0.1 bonsai, the menu's "Break it apart", the warning's
      -- "Resize and go on", with an inventory 26 of 32 slots full.
      do
        for i=1,inv:get_size("main") do inv:set_stack("main",i,"") end
        inv:set_stack("main",1,"brickcraft:separator")
        for i=2,26 do inv:set_stack("main",i,"brickcraft:"..brickcraft.colors[(i%8)+1].." "..i) end
        player:set_pos(at(-20,0.5,-24)); player:set_look_horizontal(0); player:set_look_vertical(0)
        sleep(.3)
        local ok,msg=M.place(name,"bonsai 0.1")
        assert(ok,tostring(msg))
        local small
        for _,o in ipairs(M.instances()) do if o.slug=="bonsai" and o.scale==.1 then small=o end end
        for _=1,100 do if M.spawned(small.id) and next(M.spawned(small.id)) then break end; sleep(.1) end
        local _,obj=next(M.spawned(small.id))
        local e=obj:get_luaentity()
        e.on_rightclick(e,player)
        local function send(form,fields)
          for _,f in ipairs(C.registered_on_player_receive_fields) do if f(player,form,fields) then return end end
        end
        local before=#M.instances()
        send("brickcraft_models:menu",{["break"]="Break it apart"})
        -- No warning, no resize: the model goes; what doesn't fit is sorted into stacks there.
        assert(not M.instance(small.id),"the small bonsai is broken apart at once")
        local filled=0
        for i=1,inv:get_size("main") do if not inv:get_stack("main",i):is_empty() then filled=filled+1 end end
        local rest=M.instances()[#M.instances()]
        assert(filled==inv:get_size("main") and rest.custom and rest.custom.title:find("Parts of"),
          "the inventory filled up and the rest are in stacks")
        local taken=455-#rest.custom.parts
        assert(taken>0 and #rest.custom.parts>0,"some parts went to the inventory: "..taken)
        log("break apart a size-0.1 bonsai with a near-full inventory: "..taken.." parts taken, "..#rest.custom.parts.." sorted into stacks")
      end

      player:set_pos(at(0,3,-14)); player:set_look_horizontal(0); player:set_look_vertical(.12)
      log("READY")
      sleep(4)
      log("PASS")
    end)
    local ok,err=coroutine.resume(co); if not ok then error(err) end
  end)
end)
