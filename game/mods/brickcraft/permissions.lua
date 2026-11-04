-- Account names are security principals. Selectable family profiles are display/inventory
-- identities, never an authorization credential. Legacy/server worlds remain shared.
local C=core
return function(env)
  local M={delegates={}}
  local workshop=C.deserialize(brickcraft.storage:get_string("workshop_access")) or {}
  for _,k in ipairs({"write_owner","writers","public_write"}) do env.workshop[k]=workshop[k] end
  C.register_privilege("world_admin",{description="Assign world owners and manage world write access",give_to_singleplayer=true})
  function M.principal(player)
    if type(player)=="string" then
      local resolve=M.delegates[player]
      return resolve and resolve() or player
    end
    if not player then return "" end
    if player._brickcraft_principal then return player._brickcraft_principal() or "" end
    return player:get_player_name()
  end
  function M.admin(name) return C.check_player_privs(name,{world_admin=true}) end
  function M.can_write(player,w)
    local name=M.principal(player)
    if name=="" then return false end
    return M.admin(name) or w.public_write==true or
      (not w.write_owner and w.public_write~=false) or w.write_owner==name or (w.writers or {})[name]==true
  end
  function M.check(player,pos)
    if not pos then return false end
    local name=M.principal(player)
    if M.can_write(player,brickcraft.world_at(pos)) and not M.previous_protected(pos,name) then return true end
    if name~="" then C.chat_send_player(name,"This world is read-only for you. Ask its owner for write access.") end
    return false
  end
  M.previous_protected=C.is_protected
  C.is_protected=function(pos,name)
    local principal=M.principal(name)
    return not M.can_write(principal,brickcraft.world_at(pos)) or M.previous_protected(pos,principal)
  end
  function M.describe(w)
    local writers={}
    for name,allowed in pairs(w.writers or {}) do if allowed then writers[#writers+1]=name end end
    table.sort(writers)
    return {owner=w.write_owner,writers=writers,public_write=w.public_write==true or
      (not w.write_owner and w.public_write~=false),legacy_owner=w.owner}
  end
  function M.update(actor,w,action,user)
    local name=M.principal(actor)
    if not M.admin(name) and w.write_owner~=name then return nil,"Only the owner or a world admin can change access." end
    if action=="grant" or action=="revoke" or action=="owner" then
      if type(user)~="string" or #user<1 or #user>40 or not user:match("^[%w_-]+$") then return nil,"Use an account name (letters, numbers, _ or -)." end
      if action=="owner" then
        w.write_owner=user; w.public_write=false; w.writers={} -- transfer revokes existing grants
      else
        w.writers=w.writers or {}; w.writers[user]=action=="grant" or nil
      end
    elseif action=="public" then w.public_write=true
    elseif action=="private" then
      if not w.write_owner then return nil,"Assign an owner first." end
      w.public_write=false
    else return nil,"Unknown access action." end
    env.save()
    -- Persist the writer map rather than the public array representation.
    brickcraft.storage:set_string("workshop_access",C.serialize({write_owner=env.workshop.write_owner,
      writers=env.workshop.writers,public_write=env.workshop.public_write}))
    C.log("action","[world access] "..name.." "..action.." world="..w.id.." user="..(user or ""))
    return M.describe(w)
  end
  C.register_chatcommand("worldaccess",{params="[grant|revoke|owner <account>|public|private]",
    description="Read or manage write access to your current world (account names, not family profiles)",
    func=function(name,param)
      local p=C.get_player_by_name(name)
      if not p then return false,"Join the game first." end
      local w=brickcraft.world_at(p:get_pos())
      if param=="" then return true,C.write_json(M.describe(w)) end
      local action,user=param:match("^(%S+)%s*(.-)$")
      local result,err=M.update(p,w,action,user)
      return result~=nil,err or C.write_json(result)
    end})
  -- Apply the same gate to feature-mod input callbacks, whose custom placement and
  -- entity handlers do not necessarily call Luanti's default protection functions.
  C.register_on_mods_loaded(function()
    for name,def in pairs(C.registered_items) do
      if name:match("^brickcraft:") or name:match("^brickcraft_") or name:match("^mesecons") then
        local overrides={}
        for _,event in ipairs({"on_place","on_use","on_secondary_use","on_dig","on_rightclick"}) do
          local original=def[event]
          if original then
            if event=="on_dig" or event=="on_rightclick" then
              overrides[event]=function(pos,node,p,...)
                if p and p:is_player() and not M.check(p,pos) then return end
                return original(pos,node,p,...)
              end
            else
              overrides[event]=function(stack,p,pointed,...)
                if p and p:is_player() then
                  local at=p:get_pos()
                  if pointed and pointed.type=="node" then
                    if not M.check(p,pointed.under) or not M.check(p,pointed.above) then return stack end
                  elseif pointed and pointed.type=="object" then at=pointed.ref:get_pos() end
                  if at and not M.check(p,at) then return stack end
                end
                return original(stack,p,pointed,...)
              end
            end
          end
        end
        if next(overrides) then C.override_item(name,overrides) end
      end
    end
    for name,def in pairs(C.registered_entities) do
      if name:match("^brickcraft:") or name:match("^brickcraft_") then
        for _,event in ipairs({"on_punch","on_rightclick","_brickcraft_collect"}) do
          local original=def[event]
          if original then def[event]=function(self,p,...)
            if p and p:is_player() and not M.check(p,self.object:get_pos()) then return event=="on_punch" or nil end
            return original(self,p,...)
          end end
        end
      end
    end
    for _,command in ipairs({"habitat","clearbricks","disaster","predator","colony","kingdom",
      "resetcastle","battle","armysize","orders","td","kart","model"}) do
      local def=C.registered_chatcommands[command]
      if def then
        local original=def.func
        def.func=function(name,param)
          local p=C.get_player_by_name(name)
          -- Entering a world and reading a panel do not change its access rights.
          local navigation=(command=="kingdom" and (param=="enter" or param=="")) or
            (command=="habitat" and param=="") or (command=="model" and param=="")
          if not navigation and p and not M.check(p,p:get_pos()) then return false,"World write permission required." end
          return original(name,param)
        end
      end
    end
    for i,original in ipairs(C.registered_on_player_receive_fields) do
      C.registered_on_player_receive_fields[i]=function(p,form,fields)
        if (form:match("^brickcraft_models:") or form:match("^brickcraft_habitat:") or form=="brickcraft:td") and
          not M.check(p,p:get_pos()) then return true end
        return original(p,form,fields)
      end
    end
  end)
  return M
end
