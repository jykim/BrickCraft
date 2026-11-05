-- All commands execute on the server thread. The HTTP sidecar only authenticates and
-- transports JSON; it never reads the map database or edits world files.
local C=core
return function(env)
  local M,previews={},{}
  local receipts,sequence={},0
  local P=brickcraft.permissions
  local function fail(code,message) error({code=code,message=message},0) end
  local function integer(n) return type(n)=="number" and n==math.floor(n) and math.abs(n)<=30000 end
  local function pos(p)
    if type(p)~="table" or not integer(p.x) or not integer(p.y) or not integer(p.z) then fail("invalid_request","Positions must have integer x, y, z within +/-30000.") end
    return {x=p.x,y=p.y,z=p.z}
  end
  local function world(id)
    if not integer(id) then fail("invalid_request","world_id must be an integer.") end
    local w=env.world_by_id(id)
    if not w or not w.built then fail("not_found","World is not available.") end
    return w
  end
  local function inside(p,w)
    if math.abs(p.x-w.x)>=64 or math.abs(p.z-w.z)>=64 or brickcraft.world_at(p).id~=w.id then fail("out_of_bounds","Position is outside the requested world.") end
  end
  local function writable(actor,w)
    if not P.can_write(actor,w) then fail("forbidden","World write permission required.") end
  end
  local function player(actor)
    local p=C.get_player_by_name(actor)
    if not p then fail("player_offline","The authenticated account must be connected for inventory-backed edits.") end
    if not C.check_player_privs(actor,{interact=true}) then fail("forbidden","The account needs interact privilege.") end
    return p
  end
  local function node(p)
    local n=C.get_node_or_nil(p)
    if not n or n.name=="ignore" then fail("unloaded_region","Region is not loaded. Visit it in-game first.") end
    return n
  end
  local function descriptor(w,actor)
    return {id=w.id,name=w.name,center={x=w.x,y=0,z=w.z},strict=w.strict==true,
      access=P.describe(w),can_write=P.can_write(actor,w),bounds={min_x=w.x-63,max_x=w.x+63,min_z=w.z-63,max_z=w.z+63}}
  end
  local function token(actor)
    sequence=sequence+1
    return C.sha1(actor..":"..C.get_us_time()..":"..sequence)
  end
  local function normalize(args,w)
    local op=args.operation
    if type(op)~="table" then fail("invalid_request","operation is required.") end
    local p=pos(op.pos); inside(p,w)
    local kind=op.kind
    if kind~="place" and kind~="remove" and kind~="rotate" then fail("unsupported","Supported operations: place, remove, rotate.") end
    local current=node(p)
    if kind~="place" then p,current=env.primary_of(p,current); current=node(p); inside(p,w) end
    local shape,color,turn
    if kind=="place" then
      shape=brickcraft.shapes[op.shape]; color=op.color; turn=op.turn or 0
      if not shape or shape.train or shape.technic then fail("unsupported","Only ordinary brick shapes are supported.") end
      local found=false
      for _,c in ipairs(brickcraft.colors) do if color==c then found=true end end
      if not found or not integer(turn) or turn<0 or turn>3 then fail("invalid_request","Use a catalog color and turn 0..3.") end
    else
      local def=C.registered_nodes[current.name]
      shape=def and brickcraft.shapes[def.brickcraft_shape]
      if not shape or shape.train or shape.technic or def.brickcraft_scenery then fail("unsupported","Target must be an ordinary brick.") end
      color=brickcraft.piece_of(current.name).color
      turn=kind=="rotate" and (current.param2+1)%4 or current.param2
    end
    local op2={kind=kind,pos=p,shape=shape.id,color=color,turn=turn}
    -- Every touched cell is checked, including both ends of long bricks on rotate.
    local cells={p}
    if shape.long then
      if kind~="place" then cells[#cells+1]=env.tail_pos(p,current.param2) end
      if kind~="remove" then cells[#cells+1]=env.tail_pos(p,turn) end
    end
    local expected={}
    for _,cell in ipairs(cells) do
      inside(cell,w)
      if cell.y<0 or not P.check(args.actor,cell) then fail("forbidden","A touched cell is protected.") end
      expected[#expected+1]={pos=cell,node=node(cell)}
    end
    return op2,expected
  end
  local function validate(op,p)
    local at=op.pos
    local shape=brickcraft.shapes[op.shape]
    local wanted={name=brickcraft.piece_item(op.color,shape),param2=op.turn}
    local current=node(at)
    local def=C.registered_nodes[current.name]
    local function free(cell)
      local d=C.registered_nodes[node(cell).name]
      return d and d.buildable_to
    end
    if op.kind=="place" then
      if not def or not def.buildable_to or (shape.long and not free(env.tail_pos(at,op.turn))) then fail("occupied","The piece footprint is occupied.") end
      if brickcraft.count_of(p,wanted.name)<1 then fail("inventory","No such piece in the player's inventory.") end
    elseif op.kind=="remove" then
      if not brickcraft.room_for(p,def.drop or current.name) then fail("inventory","Inventory is full.") end
    elseif shape.long and not free(env.tail_pos(at,op.turn)) then fail("occupied","No room to rotate the piece.") end
    local check=op.kind=="place" and brickcraft.strict.can_place or op.kind=="remove" and brickcraft.strict.can_remove or brickcraft.strict.can_replace
    local ok,why=check(at,wanted)
    if not ok then fail("build_rule",why) end
  end
  local function proxy(p,op)
    return setmetatable({
      get_look_dir=function() return C.facedir_to_dir(op.turn) end,
      get_meta=function() return {get_int=function() return 0 end} end,
      get_wielded_item=function() return ItemStack("brickcraft:separator") end,
    },{__index=function(_,key)
      local value=p[key]
      if type(value)=="function" then return function(_,...) return value(p,...) end end
      return value
    end})
  end
  function M.dispatch(request)
    local ok,result=pcall(function()
      if type(request)~="table" or type(request.actor)~="string" or request.actor=="" or type(request.args)~="table" then fail("invalid_request","Authenticated actor and args required.") end
      local actor,args=request.actor,request.args
      local method=request.method
      if method=="worlds" then
        local out={descriptor(env.workshop,actor)}
        for _,w in ipairs(brickcraft.worlds()) do if w.built then out[#out+1]=descriptor(w,actor) end end
        return {worlds=out}
      end
      local w=world(args.world_id)
      if method=="access" then
        if not args.action then return P.describe(w) end
        local access,err=P.update(actor,w,args.action,args.user)
        if not access then fail("forbidden",err) end
        return access
      end
      if method=="region" then
        local lo,hi=pos(args.min),pos(args.max); inside(lo,w); inside(hi,w)
        local count=(hi.x-lo.x+1)*(hi.y-lo.y+1)*(hi.z-lo.z+1)
        if hi.x<lo.x or hi.y<lo.y or hi.z<lo.z or count>32768 then fail("invalid_request","Region must be ordered and contain at most 32768 cells.") end
        local pieces,terrain,seen,signature={},{},{},{}
        for z=lo.z,hi.z do for y=lo.y,hi.y do for x=lo.x,hi.x do
          local cell={x=x,y=y,z=z}; local n=node(cell)
          signature[#signature+1]=n.name..":"..n.param2
          local primary,n2=env.primary_of(cell,n)
          n2=node(primary)
          local def=C.registered_nodes[n2.name]
          if def and def.brickcraft_shape and not def.brickcraft_scenery then
            local key=C.pos_to_string(primary)
            if not seen[key] then
              seen[key]=true
              local footprint={primary}
              local piece=brickcraft.piece_of(n2.name)
              if def.brickcraft_long then footprint[#footprint+1]=env.tail_pos(primary,n2.param2) end
              pieces[#pieces+1]={pos=primary,node=n2.name,shape=def.brickcraft_shape,color=piece and piece.color or nil,turn=n2.param2,footprint=footprint}
            end
          elseif n.name~="air" then terrain[#terrain+1]={pos=cell,node=n.name,param2=n.param2} end
        end end end
        return {world_id=w.id,min=lo,max=hi,revision=C.sha1(C.write_json({lo,hi,signature})),pieces=pieces,terrain=terrain}
      end
      writable(actor,w)
      local p=player(actor)
      if method=="preview" then
        local total,owned=0,0
        for _,plan in pairs(previews) do
          total=total+1; if plan.actor==actor then owned=owned+1 end
        end
        if total>=256 or owned>=32 then fail("busy","Too many active previews. Wait for expiry or apply one.") end
        args.actor=actor
        local op,expected=normalize(args,w); validate(op,p)
        local id=token(actor)
        previews[id]={actor=actor,world_id=w.id,op=op,expected=expected,expires=C.get_us_time()+60000000}
        return {preview_id=id,operation=op,expires_in=60}
      elseif method=="apply" then
        local plan=previews[args.preview_id]
        if not plan or plan.actor~=actor or plan.world_id~=w.id or plan.expires<C.get_us_time() then fail("expired_preview","Preview is missing or expired.") end
        local op=plan.op
        for _,e in ipairs(plan.expected) do
          if not env.same_node(e.pos,e.node) then fail("conflict","A piece changed since preview. Preview again.") end
          if not P.check(p,e.pos) then fail("forbidden","Permission changed since preview.") end
        end
        validate(op,p)
        local hands=proxy(p,op)
        local before=env.history[actor]
        if op.kind=="place" then
          local item=brickcraft.piece_item(op.color,brickcraft.shapes[op.shape])
          local left=env.place(ItemStack(item),hands,{type="node",under=op.pos,above=op.pos})
          if not left:is_empty() then fail("build_rule","Placement was refused.") end
          assert(brickcraft.take(p,item),"validated inventory changed during placement")
        elseif op.kind=="remove" then env.collect(op.pos,node(op.pos),hands)
        else env.rotate(op.pos,node(op.pos),hands) end
        if env.history[actor]==before then fail("build_rule","Operation was refused.") end
        previews[args.preview_id]=nil
        local id=token(actor)
        receipts[id]={actor=actor,world_id=w.id,history=env.history[actor]}
        C.log("action","[world api] "..actor.." "..op.kind.." world="..w.id.." at="..C.pos_to_string(op.pos))
        return {operation_id=id,operation=op}
      elseif method=="undo" then
        local receipt=receipts[args.operation_id]
        if not receipt or receipt.actor~=actor or receipt.world_id~=w.id or receipt.history~=env.history[actor] then fail("conflict","Only your most recent unchanged build action can be undone.") end
        if not brickcraft.undo(p) then fail("build_rule","Undo refused: permissions, inventory, support, or occupied cells changed.") end
        receipts[args.operation_id]=nil
        return {undone=args.operation_id}
      end
      fail("unsupported","Unknown method.")
    end)
    if ok then return {ok=true,result=result} end
    if type(result)~="table" then C.log("error","[world api] "..tostring(result)); result={code="internal",message="Internal command error."} end
    return {ok=false,error=result}
  end
  -- Bound ephemeral previews/undo receipts, including stale history references.
  local elapsed=0
  C.register_globalstep(function(dt)
    elapsed=elapsed+dt; if elapsed<2 then return end; elapsed=0
    for id,p in pairs(previews) do if p.expires<C.get_us_time() then previews[id]=nil end end
    for id,r in pairs(receipts) do if env.history[r.actor]~=r.history then receipts[id]=nil end end
  end)
  if C.settings:get_bool("brickcraft_world_api",false) then
    local root=C.get_worldpath().."/world_api"
    C.mkdir(root.."/inbox"); C.mkdir(root.."/outbox")
    local tick=0
    C.register_globalstep(function(dt)
      tick=tick+dt; if tick<.1 then return end; tick=0
      local processed=0
      for _,file in ipairs(C.get_dir_list(root.."/inbox",false)) do
        if file:match("^[a-f0-9]+%.json$") and #file==37 then
          local input=io.open(root.."/inbox/"..file,"rb")
          if input then
            local data=input:read(65537); input:close()
            local response
            if #data>65536 then response={ok=false,error={code="invalid_request",message="Request too large."}}
            else response=M.dispatch(C.parse_json(data)) end
            if C.safe_file_write(root.."/outbox/"..file,C.write_json(response)) then os.remove(root.."/inbox/"..file) end
          end
          processed=processed+1; if processed>=8 then break end
        end
      end
    end)
  end
  return M
end
