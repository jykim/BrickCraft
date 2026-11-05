-- Churu-stocked feeders attract one guardian each. Cats are temporary entities: the
-- feeder's saved timer and food recreate them after a restart, without duplicates.
return function(H)
local C=core
local FEEDER="brickcraft_habitat:cat_feeder"
local CHURU="brickcraft_habitat:churu"
local cats={}
H.cats=cats
function H.defense_kit(player)
  if not brickcraft.war then return end
  -- Entering Bunnyland from a battle restores the normal building inventory first.
  if brickcraft.war.on(player) then brickcraft.war.stop(player) end
  for _,item in ipairs({"brickcraft:sword","brickcraft:bow"}) do
    if brickcraft.count_of(player,item)==0 then brickcraft.give(player,item) end
  end
end
C.register_craftitem(CHURU,{description="Churu\nRight click a cat feeder to stock it (2 minutes per tube)",
  inventory_image="brickcraft_habitat_churu.png",stack_max=99})
local function key(pos) return C.pos_to_string(pos) end
local function describe(pos)
  local meta=C.get_meta(pos)
  local food=meta:get_int("churu")
  meta:set_string("infotext","Cat feeder: "..food.." churu tubes"..
    (cats[key(pos)] and " / guardian on duty" or " / add churu to lure a guardian"))
end
H.register_structure("cat_feeder",{label="Cat feeder",effect="guardian",walkable=false,
  about="Stock with churu (right click): lure a cat to guard nearby bunnies; 2 minutes per tube",
  node_box={{-.4,-.5,-.35,.4,-.4,.35},{-.4,-.4,-.35,-.3,-.2,.35},{.3,-.4,-.35,.4,-.2,.35},
    {-.3,-.4,-.35,.3,-.2,-.25},{-.3,-.4,.25,.3,-.2,.35}},
  tiles={"brickcraft_habitat_feeder.png"},inventory_image="brickcraft_habitat_feeder.png"})
local function dismiss(pos)
  local k=key(pos)
  local cat=cats[k]
  cats[k]=nil
  if cat then cat.object:remove() end
end
C.override_item(FEEDER,{
  on_construct=function(pos) describe(pos); C.get_node_timer(pos):start(5) end,
  on_rightclick=function(pos,node,player,stack)
    if stack:get_name()~=CHURU then
      C.chat_send_player(player:get_player_name(),"Hold Churu and right click to stock this feeder (up to 6 tubes). Buy more in /colony.")
      return stack
    end
    local meta=C.get_meta(pos)
    if meta:get_int("churu")<6 then
      meta:set_int("churu",meta:get_int("churu")+1)
      stack:take_item(); describe(pos); C.get_node_timer(pos):start(.1)
    end
    return stack
  end,
  on_destruct=function(pos) dismiss(pos) end,
  -- Picking it up returns stored tubes; an already served meal is spent.
  brickcraft_turn=function(pos,node,player)
    local n=C.get_meta(pos):get_int("churu")
    if not brickcraft.room_for(player,FEEDER) or
      (n>0 and not brickcraft.room_for(player,CHURU.." "..n)) then return end
    -- Add the feeder first, checking the second stack again before removing the node.
    local inv=player:get_inventory()
    local before=inv:get_list("main")
    local a=brickcraft.give(player,FEEDER)
    local b=n>0 and brickcraft.give(player,CHURU.." "..n) or ItemStack("")
    if not a:is_empty() or not b:is_empty() then inv:set_list("main",before); return end
    C.remove_node(pos)
  end,
  on_timer=function(pos)
    local w,v=H.world_at(pos)
    if not (v and v.defense) then dismiss(pos); return true end
    local meta=C.get_meta(pos)
    if meta:get_int("fed_until")<=C.get_gametime() then
      local n=meta:get_int("churu")
      if n==0 then dismiss(pos); describe(pos); return true end
      meta:set_int("churu",n-1); meta:set_int("fed_until",C.get_gametime()+120)
    end
    if not cats[key(pos)] then
      local total=0
      for _,cat in pairs(cats) do
        local q=cat.object:get_pos()
        if q and brickcraft.world_at(q)==w then total=total+1 end
      end
      if total<8 then
        for _,o in ipairs({{1,0},{-1,0},{0,1},{0,-1}}) do
          local x,z=pos.x+o[1],pos.z+o[2]
          local y=H.ground(x,z,pos.y+1)
          if y and math.abs(y-pos.y)<2 and C.get_node({x=x,y=y,z=z}).name=="air" then
            local obj=C.add_entity({x=x,y=y-.45,z=z},"brickcraft_habitat:guardian_cat",C.serialize(pos))
            if obj then break end
          end
        end
      end
    end
    describe(pos)
    C.get_node_timer(pos):start(5)
    return false
  end,
})
C.register_entity("brickcraft_habitat:guardian_cat",{
  initial_properties={visual="mesh",mesh="brickcraft_habitat_cat.obj",textures={"brickcraft_habitat_cat.png"},
    visual_size={x=10,y=10},physical=true,collide_with_objects=false,static_save=false,stepheight=.3,
    collisionbox={-.2,0,-.35,.2,.65,.35},nametag="Guardian Cat",nametag_color="#9be59b"},
  on_activate=function(self,data)
    self._feeder=C.deserialize(data)
    if type(self._feeder)~="table" or cats[key(self._feeder)] then self.object:remove(); return end
    cats[key(self._feeder)]=self
    self._next_hit=0; self._think=0
    self.object:set_armor_groups({immortal=1})
    self.object:set_acceleration({x=0,y=-19.62,z=0})
  end,
  on_deactivate=function(self)
    if self._feeder and cats[key(self._feeder)]==self then cats[key(self._feeder)]=nil end
  end,
  on_punch=function() return true end,
  on_step=function(self,dt,moveresult)
    local home=self._feeder
    if not home or C.get_node(home).name~=FEEDER or (C.get_meta(home):get_int("fed_until")<=C.get_gametime() and C.get_meta(home):get_int("churu")==0) then
      self.object:remove(); return
    end
    local p=self.object:get_pos()
    local w,v=H.world_at(home)
    if not (v and v.defense) then self.object:remove(); return end
    H.stuck_jump(self,moveresult,6)
    self._think=self._think-dt
    if self._think>0 then return end
    self._think=.25
    local target,dist
    for ent in pairs(H.hunters) do
      local q=ent.object:get_pos()
      if q and not ent._gone and brickcraft.world_at(q)==w and H.flat(home,q)<12 and math.abs(q.y-p.y)<6 then
        local d=vector.distance(p,q)
        if not dist or d<dist then target,dist=ent,d end
      end
    end
    if target and H.flat(p,home)<14 then
      local q=target.object:get_pos()
      -- A hiss reaches low-flying eagles too; walls still block a cat's defense.
      local flying=H.predators[target._kind].flies
      if dist<(flying and 6 or 2) and H.now()>=self._next_hit and
        C.line_of_sight(vector.offset(p,0,.5,0),vector.offset(q,0,.5,0)) then
        self._next_hit=H.now()+1
        target:_hit(self.object,{dmg=2})
      end
      H.steer(self,q,3.8)
    else
      if not self._patrol or H.flat(p,self._patrol)<.6 then
        local a=math.random()*math.pi*2
        self._patrol=vector.offset(home,math.cos(a)*3,0,math.sin(a)*3)
      end
      H.steer(self,H.flat(p,home)>5 and home or self._patrol,2)
    end
  end,
})
end
