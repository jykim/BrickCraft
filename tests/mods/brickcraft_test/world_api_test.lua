local C=core
C.register_on_mods_loaded(function()
  local id=brickcraft.storage:get_int("api_test_world_id")
  if id==0 then return end
  C.after(1,function()
    local w
    for _,candidate in ipairs(brickcraft.worlds()) do if candidate.id==id then w=candidate end end
    assert(w and w.write_owner=="ApiOwner" and w.public_write==false,"owner and privacy persisted")
    assert(not brickcraft.permissions.can_write("Visitor",w),"revocation persisted")
    assert(brickcraft.permissions.can_write("ApiOwner",w),"owner access persisted")
    C.log("action","BRICKCRAFT API PERSISTENCE PASS")
    C.request_shutdown("API persistence checks passed",false,0)
  end)
end)
C.register_on_joinplayer(function(p)
  if p:get_player_name()=="Visitor" then
    C.after(1,function()
      brickcraft.give(p,"brickcraft:coral 20")
      C.safe_file_write(C.get_worldpath().."/api_visitor_ready","ready")
    end)
    return
  end
  C.after(2,function()
    local P=brickcraft.permissions
    assert(P.can_write("Visitor",brickcraft.world_at({x=0,y=0,z=0})),"legacy Workshop stays shared")
    brickcraft.make_world("API test",p:get_player_name(),function(w)
      local at={x=w.x+12,y=0,z=w.z}
      p:set_pos(vector.offset(at,0,1,4))
      local inv=p:get_inventory()
      inv:set_stack("main",1,"brickcraft:separator")
      brickcraft.give(p,"brickcraft:coral_2x4 20")
      brickcraft.give(p,"brickcraft:coral 20")
      assert(not P.can_write("Visitor",w),"private owner default")
      assert(P.can_write(p,w),"owner can write")
      P.delegates["Owner bot (AI)"]=function() return p:get_player_name() end
      assert(not C.is_protected(at,"Owner bot (AI)"),"AI inherits authenticated owner")
      P.delegates["Owner bot (AI)"]=function() return "" end
      assert(C.is_protected(at,"Owner bot (AI)"),"disconnected owner cannot delegate")
      assert(not P.can_write("dad",w),"selectable family profile does not confer ownership")
      assert(not P.update("Visitor",w,"grant","Visitor"),"visitor cannot grant itself access")
      assert(C.is_protected(at,"Visitor"),"engine protection applies")
      local visitor=setmetatable({get_player_name=function() return "Visitor" end},
        {__index=function(_,key) local v=p[key]; if type(v)=="function" then return function(_,...) return v(p,...) end end; return v end})
      local item=ItemStack("brickcraft:coral")
      local left=item:get_definition().on_place(item,visitor,{type="node",under=at,above=at})
      assert(left:get_count()==1 and C.get_node(at).name=="air","visitor click denied without inventory change")
      assert(P.update(p,w,"grant","Visitor")); assert(not C.is_protected(at,"Visitor"),"grant reaches engine protection")
      assert(P.update(p,w,"revoke","Visitor")); assert(C.is_protected(at,"Visitor"),"revoke reaches engine protection")
      C.safe_file_write(C.get_worldpath().."/api_ready.json",C.write_json({world_id=w.id,pos=at,owner=p:get_player_name()}))
      brickcraft.storage:set_int("api_test_world_id",w.id)
      C.log("action","BRICKCRAFT API READY")
    end,{write_owner=p:get_player_name()})
  end)
end)
