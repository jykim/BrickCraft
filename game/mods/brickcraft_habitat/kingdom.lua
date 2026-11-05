-- Bunnyland + cooperative tower defense. State belongs to this kingdom's world;
-- temporary actors are recreated from the saved roster only while players are here.
return function(H)
local C=core
local K={actors={},runtime={},gathering={}}
H.kingdom=K
local PREFIX="brickcraft_habitat:"
local function at(w,x,y,z) return {x=w.x+x,y=y,z=w.z+z} end
local function iskingdom(w) local v=H.variant_of(w); return v and v.kingdom end
function K.state(w)
  local st=H.state(w)
  if not st.kingdom then
    st.kingdom={food=24,water=20,wood=40,stone=30,hp=100,guards=3,workers=2,
      towers={},walls={},wave=0,kills=0,nights=0,status="playing"}
    H.save(w)
  end
  return st.kingdom
end
local function count(w,role,weapon)
  local n=0
  for e in pairs(K.actors) do if e._world==w.id and (not role or e._role==role) and (not weapon or e._weapon==weapon) then n=n+1 end end
  return n
end
K.count=count
function K.line(w)
  local s=K.state(w)
  return "CASTLE "..s.hp.."/100 | Food "..s.food.."  Water "..s.water.."  Wood "..s.wood.."  Stone "..s.stone..
    "\nWave "..s.wave.." | Blue guards "..s.guards.." | Towers "..#s.towers.." | Nights "..s.nights.."/3 | "..
    (s.status=="won" and "KINGDOM SAVED!" or s.status=="lost" and "Castle fallen - /kingdom restart" or "/kingdom: build, recruit, orders")
end
local function node(id,label,texture,box)
  C.register_node(PREFIX..id,{description=label,tiles={texture},drawtype=box and "nodebox" or "normal",
    node_box=box and {type="fixed",fixed=box} or nil,paramtype="light",
    groups={habitat_kingdom=1},diggable=false,drop="",is_ground_content=false})
end
node("castle_stone","Bunny Castle","brickcraft_cream.png")
node("castle_blue","Blue kingdom banner","brickcraft_sky.png")
node("kingdom_wall","Kingdom wall","brickcraft_navy.png")
node("kingdom_rock","River rock","brickcraft_habitat_patch_empty.png")
node("shop","Bunny shop - right click","brickcraft_gold.png",{{-.5,-.5,-.5,.5,.15,.5},{-.5,.85,-.5,.5,1,.5},
  {-.45,.15,-.45,-.35,.85,-.35},{.35,.15,-.45,.45,.85,-.35}})
C.override_item(PREFIX.."shop",{on_rightclick=function(_,_,p) K.panel(p) end})
node("kingdom_tower","Berry arrow tower","brickcraft_navy.png",{{-.48,-.5,-.48,.48,.5,.48}})
C.override_item(PREFIX.."kingdom_tower",{on_rightclick=function(_,_,p) K.panel(p) end})
node("river","River and waterfall","brickcraft_habitat_water.png")
C.override_item(PREFIX.."river",{walkable=false,drawtype="glasslike",use_texture_alpha="blend",
  sunlight_propagates=true,liquid_move_physics=true,post_effect_color={a=70,r=40,g=120,b=200}})
H.register_source("berries",{kind="food",label="Berry patch",units=8,regrow=12,height=.5,
  tiles={"brickcraft_habitat_berries.png"},inventory_image="brickcraft_habitat_berries.png"})
local function landscape_node(name)
  return H.LANDSCAPE[name] or name=="brickcraft:baseplate" or name:find("^brickcraft_habitat:meadow")
end
function K.setup(w)
  H.state(w).cycle_start=H.clock.elapsed
  -- New variant setup never overwrites player construction.
  local function put(x,y,z,id)
    local q=at(w,x,y,z)
    if landscape_node(C.get_node(q).name) then
      C.set_node(q,{name=PREFIX..id})
      local def=C.registered_nodes[PREFIX..id]
      if def.on_construct then def.on_construct(q) end
    end
  end
  -- Keep and four crenellated corner towers, with a wide open front gate.
  for x=-8,8 do for z=5,21 do
    put(x,-1,z,"castle_stone")
    if x==-8 or x==8 or z==5 or z==21 then
      if not (z==5 and math.abs(x)<3) then
        for y=0,3 do put(x,y,z,"castle_stone") end
        if (x+z)%2==0 then put(x,4,z,"castle_blue") end
      end
    end
  end end
  for _,x in ipairs({-8,8}) do for _,z in ipairs({5,21}) do
    for dx=-1,1 do for dz=-1,1 do for y=0,5 do
      if math.abs(dx)==1 or math.abs(dz)==1 then put(x+dx,y,z+dz,"castle_stone") end
    end; put(x+dx,6,z+dz,"castle_blue") end end
  end end
  put(0,0,20,"shop")
  put(-15,0,2,"shop")
  -- Farmland, berry patches, and an accessible drinking pool by the river.
  for x=-19,-11,2 do for z=8,16,2 do put(x,0,z,"carrot_patch") end end
  for _,p in ipairs({{-15,-6},{-11,-8},{-18,-9},{12,-8},{16,-5}}) do put(p[1],0,p[2],"berries") end
  for z=-40,40 do for x=25,28 do put(x,-1,z,"river") end end
  -- A raised source spills down the north hill into the river. Rocks frame it.
  for y=0,8 do for x=25,27 do put(x,y,30,"river") end end
  for z=30,40 do for x=25,27 do put(x,8,z,"river") end end
  for _,p in ipairs({{23,28},{29,28},{22,32},{30,33},{-29,29},{-32,26},{32,-24}}) do
    local g=H.ground(w.x+p[1],w.z+p[2],30) or 0
    for y=g,g+2 do put(p[1],y,p[2],"kingdom_rock") end
  end
  K.state(w)
end
-- Crown the existing Bunnyland sculpture, retaining its original silhouette.
local bunny=H.variants.bunny
local statue=table.copy(bunny.statue)
statue.build=function(put,S)
  bunny.statue.build(put,S)
  S.box(put,-3,18,-4,3,18,1,"gold")
  for _,x in ipairs({-3,0,3}) do S.box(put,x,19,-4,x,20,-4,"gold") end
end
H.register_variant("kingdom",{label="Bunny Kingdom",kingdom=true,defense=true,plural="bunnies",creature="bunny",
  count=8,max=20,statue=statue,setup=K.setup,sources={{"water_trough",-12,11},{"water_trough",12,11}},
  kit={carrot_patch=4,water_trough=2,berries=3},predators={},skins=bunny.skins,
  cycle={day=150,night=60,lock_players=false,predator_multiplier=0,disaster="none"},
  disasters={"snow","asteroids","tsunami"},match_names={"bunnykingdom","bunnykingdomsurvival"},
  meadow={ponds={{18,-8,2}},patches=8,patch="berries",pond="pond"},
  welcome="You lead the blue bunnies! Gather, build towers and walls, and protect Bunny Castle through three nights.",
  tip="/kingdom opens your kingdom. Red armies raid by day; zombies attack at night. Blue guards and towers defend the castle."})

-- The flood's actual rising-water simulation also supplies the tsunami event.
local tsunami=table.copy(H.disasters.flood)
tsunami.label="Tsunami"; tsunami.delay=8; tsunami.duration=30; tsunami.peak=14
tsunami.warning="A river surge is coming! Raise food, build sealed shelters, and lead your bunnies uphill."
H.register_disaster("tsunami",tsunami)
H.register_disaster("snow",{label="Snowstorm",delay=8,duration=25,creatures_seek="shelter",
  warning="Snow slows the armies. Stock food and build roofs for your bunnies!",
  step=function(ctx,dt)
    ctx.data.wait=(ctx.data.wait or 0)-dt
    if ctx.data.wait>0 then return end
    ctx.data.wait=1
    local w=ctx.world
    C.add_particlespawner({amount=180,time=1,minpos=at(w,-38,15,-38),maxpos=at(w,38,20,38),
      minvel={x=-1,y=-3,z=-1},maxvel={x=1,y=-1,z=1},minexptime=3,maxexptime=5,
      minsize=2,maxsize=4,texture="brickcraft_cream.png",collisiondetection=true})
  end})
-- A wave operates on a bounded roster, with no saved map entities or offline attacks.
H.predators.kingdom_enemy={label="Enemy bunny",flies=false}
local function find_world(id)
  for _,w in ipairs(brickcraft.worlds()) do if w.id==id then return w end end
end
local function nearest_enemy(self,p)
  local target,dist
  for e in pairs(K.actors) do
    if e._world==self._world and ((self._role=="enemy")~=(e._role=="enemy")) and
      (e._role=="enemy" or e._role=="guard") then
      local q=e.object:get_pos()
      if q then local d=vector.distance(p,q); if d<16 and (not dist or d<dist) then target,dist=e,d end end
    end
  end
  return target,dist
end
local function damage(self,n)
  if self._gone or self._role=="king" or self._role=="worker" then return false end
  local w=find_world(self._world)
  if not w then return false end
  local s=K.state(w)
  if s.status~="playing" then return false end
  self._hp=self._hp-n
  if self._hp<=0 then
    self._gone=true
    if self._role=="enemy" then s.kills=s.kills+1; s.food=math.min(999,s.food+2)
    else
      s.guards=math.max(0,s.guards-1)
      if self._weapon=="sling" then s.slingers=math.max(0,(s.slingers or 0)-1) end
      if self._weapon=="acorn" then s.bombers=math.max(0,(s.bombers or 0)-1) end
    end
    H.poof(self.object:get_pos()); self.object:remove(); H.save(w)
  else self.object:set_properties({nametag=self._label.." "..self._hp.." HP"}) end
  return true
end
C.register_entity(PREFIX.."kingdom_bunny",{
  initial_properties={visual="mesh",mesh="brickcraft_habitat_bunny_person.obj",
    textures={"brickcraft_habitat_skin_gray.png"},visual_size={x=10,y=10},physical=true,
    collide_with_objects=false,static_save=false,stepheight=.3,collisionbox={-.28,0,-.28,.28,1.7,.28}},
  on_activate=function(self,data)
    local a=C.deserialize(data)
    if type(a)~="table" or not find_world(a.world) then self.object:remove(); return end
    self._world,self._role,self._zombie=a.world,a.role,a.zombie
    self._weapon=a.weapon or "spear"
    self._kind="kingdom_enemy"
    self._hp=a.role=="enemy" and (a.zombie and 8 or 6) or 12
    self._label=a.role=="enemy" and (a.zombie and "Zombie Bunny" or "Red Army Bunny") or
      a.role=="guard" and "Blue Bunny Guard" or a.role=="king" and "Bunny King" or "Bunny Worker"
    if a.role=="guard" or a.role=="enemy" then
      self._label=self._label.." / "..(self._weapon=="sling" and "Berry Slinger" or self._weapon=="acorn" and "Acorn Bomber" or "Carrot Lancer")
    end
    self.object:set_properties({nametag=self._label,textures={"brickcraft_habitat_kingdom_"..
      (a.role=="enemy" and (a.zombie and "zombie" or "red") or a.role=="king" and "king" or "blue")..".png"},
      nametag_color=a.role=="enemy" and "#ff8877" or "#a5dfff"})
    self.object:set_armor_groups({immortal=1}); self.object:set_acceleration({x=0,y=-19.62,z=0})
    self._think,self._attack=0,0
    K.actors[self]=true
    if a.role=="enemy" then H.hunters[self]=true end
  end,
  on_deactivate=function(self) K.actors[self]=nil; H.hunters[self]=nil end,
  on_rightclick=function(self,p) if self._role~="enemy" then K.panel(p) end end,
  on_punch=function(self,p)
    if self._role=="enemy" and p and p:is_player() then
      local w=H.world_at(p:get_pos())
      if w and w.id==self._world then damage(self,p:get_wielded_item():get_name()=="brickcraft:sword" and 2 or 1) end
    end
    return true
  end,
  _hit=function(self,attacker,m)
    if self._role~="enemy" then return false end
    return damage(self,m and m.dmg or 1)
  end,
  _brickcraft_collect=function(self,p) self:on_punch(p) end,
  on_step=function(self,dt,moveresult)
    local w=find_world(self._world)
    if not w or not iskingdom(w) or #H.players_in(w)==0 then self.object:remove(); return end
    local s=K.state(w)
    if s.status~="playing" then H.steer(self,nil,0); return end
    H.stuck_jump(self,moveresult,4.5)
    self._think=self._think-dt; self._attack=self._attack-dt
    if self._think>0 then return end
    self._think=.25
    local p=self.object:get_pos()
    local home=at(w,0,0,9)
    if p.y< -4 or H.flat(p,home)>80 then self.object:set_pos(home); return end
    if self._role=="king" then H.steer(self,nil,0); return end
    if self._role=="worker" then
      -- Workers really visit a renewable food or water source, then carry it home.
      if self._cargo then
        if H.flat(p,home)<2 then
          s[self._cargo]=math.min(999,s[self._cargo]+2); self._cargo=nil; self._destination=nil; H.save(w)
        end
        K.move(self,home,2,moveresult); return
      end
      if not self._destination then
        local group=math.random(2)==1 and "group:habitat_food" or "group:habitat_water"
        local sources=C.find_nodes_in_area(at(w,-22,-1,-20),at(w,22,2,22),{group})
        if #sources>0 then self._destination=sources[math.random(#sources)] end
      end
      local q=self._destination
      if q and H.flat(p,q)<1.5 then
        local water=C.get_item_group(C.get_node(q).name,"habitat_water")>0
        if H.consume(q) then self._cargo=water and "water" or "food" else self._destination=nil end
      end
      K.move(self,q,2,moveresult); return
    end
    local target,dist=nearest_enemy(self,p)
    local q=target and target.object:get_pos()
    local reach=self._weapon=="spear" and 2.8 or self._weapon=="sling" and 11 or 8
    if target and dist<reach and self._attack<=0 and C.line_of_sight(vector.offset(p,0,1,0),vector.offset(q,0,1,0)) then
      self._attack=self._weapon=="acorn" and 2.5 or 1.2
      damage(target,self._weapon=="acorn" and 3 or 2)
      if self._weapon~="spear" then K.shot(vector.offset(p,0,1,0),vector.offset(q,0,1,0),self._weapon) end
      if self._weapon=="acorn" then
        for e in pairs(K.actors) do
          local ep=e.object:get_pos()
          if e~=target and e._world==self._world and e._role==target._role and ep and vector.distance(ep,q)<2.5 and
            C.line_of_sight(vector.offset(q,0,1,0),vector.offset(ep,0,1,0)) then damage(e,2) end
        end
      end
    end
    local speed=self._role=="enemy" and (self._zombie and 1.65 or 2.1) or 2.5
    local ctx=H.active[w.id]
    if ctx and ctx.started and ctx.def.id=="snow" then speed=speed*.65 end
    if self._role=="enemy" then
      if self._attack<=0 then
        for _,collision in ipairs(moveresult and moveresult.collisions or {}) do
          local cell=collision.node_pos
          local name=cell and C.get_node(cell).name
          if name==PREFIX.."kingdom_wall" or name==PREFIX.."kingdom_tower" then
            local meta=C.get_meta(cell)
            local hp=meta:get_int("kingdom_hp")
            hp=(hp>0 and hp or 18)-2
            self._attack=1.2
            if hp<=0 then C.remove_node(cell) else meta:set_int("kingdom_hp",hp) end
            break
          end
        end
      end
      if not q then
        -- Attack the gate/keep, so players can intercept before the army reaches it.
        q=home
        if H.flat(p,home)<reach and self._attack<=0 and C.line_of_sight(vector.offset(p,0,1,0),vector.offset(home,0,1,0)) then
          self._attack=self._weapon=="acorn" and 2.5 or 1.5
          if self._weapon~="spear" then K.shot(vector.offset(p,0,1,0),vector.offset(home,0,1,0),self._weapon) end
          K.damage_castle(w,self._weapon=="acorn" and 4 or self._zombie and 3 or 2)
        end
      end
    else
      local order=s.order or "defend"
      local leader=H.players_in(w)[1]
      if order=="follow" and leader then q=q or leader:get_pos()
      elseif order=="hold" and H.flat(p,home)>8 then q=home
      else q=q or at(w,(self._slot or 0)%3*2-2,0,2) end
    end
    if target and self._weapon~="spear" and dist<reach*.8 then H.steer(self,nil,0)
    else K.move(self,q,speed,moveresult) end
  end,
})
-- Replan around walls, rather than walking straight into a player's tower corridor.
function K.move(self,target,speed,moveresult)
  if not target then H.steer(self,nil,0); return end
  local p=self.object:get_pos()
  if H.blocked(moveresult) or self._path then
    if not self._path_at or H.now()-self._path_at>2 then
      self._path_at=H.now()
      local goal=vector.round(target)
      local ground=H.ground(goal.x,goal.z,30)
      if ground then goal.y=ground end
      self._path=C.find_path(vector.round(p),goal,40,1,3,"A*_noprefetch")
      self._path_index=2
    end
    local nextpos=self._path and self._path[self._path_index]
    if nextpos and H.flat(p,nextpos)<.6 then self._path_index=self._path_index+1; nextpos=self._path[self._path_index] end
    if nextpos then target=nextpos else self._path=nil end
  end
  H.steer(self,target,speed)
end
function K.shot(from,to,weapon)
  local dist=vector.distance(from,to)
  C.add_particle({pos=from,velocity=vector.multiply(vector.direction(from,to),20),expirationtime=dist/20,
    size=weapon=="acorn" and 5 or 3,texture="brickcraft_habitat_weapon_"..(weapon=="acorn" and "acorn_launcher" or "berry_sling")..".png"})
end
local function tower_origin(q,target)
  local dir=vector.normalize({x=target.x-q.x,y=0,z=target.z-q.z})
  return vector.offset(q,dir.x*.65,.6,dir.z*.65)
end
local weapon_specs={
  carrot_lance={label="Carrot Lance",damage=3,range=5,cooldown=.7,about="Long reach thrust"},
  radish_hammer={label="Radish Hammer",damage=5,range=2.8,cooldown=1.2,splash=1.8,about="Heavy close range sweep"},
  berry_sling={label="Berry Slingshot",damage=2,range=24,cooldown=.5,ranged=true,about="Fast berry shots"},
  acorn_launcher={label="Acorn Launcher",damage=3,range=18,cooldown=1.8,ranged=true,splash=3,about="Acorns burst against groups"},
  cabbage_shield={label="Cabbage Shield",damage=1,range=3,cooldown=.8,about="Bash; hold near castle to block 2 damage from each attack"},
}
K.weapons=weapon_specs
local attacks={}
function K.attack(p,id)
  local spec=weapon_specs[id]
  local w=H.world_at(p:get_pos())
  if not spec or not iskingdom(w) or K.state(w).status~="playing" then return false end
  local key=p:get_player_name()
  if (attacks[key] or 0)>H.now() then return false end
  attacks[key]=H.now()+spec.cooldown
  local from=vector.offset(p:get_pos(),0,p:get_properties().eye_height or 1.625,0)
  local finish=vector.add(from,vector.multiply(p:get_look_dir(),spec.range))
  local target
  for hit in C.raycast(from,finish,true,false) do
    if hit.type=="node" then break end
    if hit.ref~=p then
      local ent=hit.ref:get_luaentity()
      if ent and K.actors[ent] and ent._world==w.id and ent._role=="enemy" then target=ent; break end
    end
  end
  if spec.ranged then K.shot(from,target and vector.offset(target.object:get_pos(),0,1,0) or finish,id=="acorn_launcher" and "acorn" or "sling") end
  if not target then return true end
  local impact=target.object:get_pos()
  damage(target,spec.damage)
  if spec.splash then
    H.poof(impact)
    for e in pairs(K.actors) do
      local pos=e.object:get_pos()
      if e~=target and e._role=="enemy" and e._world==w.id and pos and vector.distance(pos,impact)<spec.splash and
        C.line_of_sight(vector.offset(impact,0,1,0),vector.offset(pos,0,1,0)) then damage(e,spec.damage) end
    end
  end
  return true
end
for id,spec in pairs(weapon_specs) do
  C.register_tool(PREFIX..id,{description=spec.label.."\n"..spec.about.."\nBunny Kingdom / left click",
    inventory_image="brickcraft_habitat_weapon_"..id..".png",range=spec.range,
    on_use=function(stack,p) K.attack(p,id); return stack end})
end
C.register_on_leaveplayer(function(p) attacks[p:get_player_name()]=nil end)
function K.spawn(w,role,pos,zombie,weapon)
  return C.add_entity(pos,PREFIX.."kingdom_bunny",C.serialize({world=w.id,role=role,zombie=zombie,weapon=weapon}))
end
function K.damage_castle(w,n,unblockable)
  local s=K.state(w)
  if s.status~="playing" then return end
  for _,p in ipairs(H.players_in(w)) do
    if not unblockable and p:get_wielded_item():get_name()==PREFIX.."cabbage_shield" and H.flat(p:get_pos(),at(w,0,0,9))<8 then
      n=math.max(0,n-2); break
    end
  end
  s.hp=math.max(0,s.hp-n)
  if s.hp==0 then s.status="lost"; H.tell(w,"Bunny Castle has fallen! /kingdom restart to rally again.","#ff8877") end
  H.save(w)
end
function K.wave(w,night)
  local s=K.state(w)
  if s.status~="playing" then return 0 end
  local room=24-count(w,"enemy")
  local n=math.min(room,4+math.min(8,s.wave))
  if n<=0 then return 0 end
  s.wave=s.wave+1
  local made=0
  -- A front approach encourages tower corridors and a defended gate. Alternate flanks.
  local side=s.wave%2==0 and 1 or -1
  for i=1,n do
    local x,z=side*(12+i%4),-25-math.floor(i/4)
    local g=H.ground(w.x+x,w.z+z,30)
    local weapons={"spear","sling","spear","acorn"}
    if g and K.spawn(w,"enemy",at(w,x,g+.1,z),night,weapons[(i-1)%4+1]) then made=made+1 end
  end
  H.tell(w,"Wave "..s.wave..": "..(night and "Zombie bunnies rise!" or "The red bunny army strikes!"),night and "#b9e584" or "#ff8877")
  H.save(w); return made
end
local costs={guard={food=8,water=4},slinger={food=10,water=5},bomber={food=12,water=6},worker={food=10},tower={wood=16,stone=12},wall={wood=8,stone=4},repair={wood=8,stone=6},
  supplies={food=8,water=4}}
K.costs=costs
local function spend(s,cost)
  for k,n in pairs(cost) do if s[k]<n then return false,"Need "..n.." "..k.."." end end
  for k,n in pairs(cost) do s[k]=s[k]-n end
  return true
end
function K.gather(p,pos)
  local w=H.world_at(p:get_pos())
  if not iskingdom(w) or brickcraft.world_at(pos)~=w or vector.distance(p:get_pos(),pos)>7 then return false,"Move within 7 blocks of the source." end
  local s=K.state(w)
  if s.status~="playing" then return false,"Start a new round first." end
  local name=C.get_node(pos).name
  local resource
  if C.get_item_group(name,"habitat_food")>0 then resource="food"
  elseif C.get_item_group(name,"habitat_water")>0 or name==PREFIX.."river" then resource="water"
  elseif name=="brickcraft:trunk" then resource="wood"
  elseif name==PREFIX.."kingdom_rock" then resource="stone" end
  if not resource then return false,"Gather berries, carrots, water, tree trunks or rocks." end
  local key=C.pos_to_string(pos)
  K.gathering[w.id]=K.gathering[w.id] or {}
  local cooldown=K.gathering[w.id]
  if (cooldown[key] or 0)>H.now() then return false,"This source is recovering." end
  if resource=="food" and not H.consume(pos) then return false,"The patch is regrowing." end
  cooldown[key]=H.now()+2
  s[resource]=math.min(999,s[resource]+4); H.save(w)
  return true,"Gathered 4 "..resource.." for your kingdom."
end
C.register_tool(PREFIX.."gather",{description="Kingdom gathering basket\nLeft click berries, carrots, water, trunks or rocks",
  inventory_image="brickcraft_habitat_carrot.png",range=7,
  on_use=function(stack,p,pointed)
    local ok,msg
    if pointed.type=="node" then ok,msg=K.gather(p,pointed.under) else msg="Aim at a source to gather." end
    C.chat_send_player(p:get_player_name(),msg); return stack
  end})
function K.action(p,action)
  local w=H.world_at(p:get_pos())
  if not iskingdom(w) then return false,"Visit Bunny Kingdom first: /kingdom enter." end
  local s=K.state(w)
  if action=="restart" then
    if s.status=="playing" then return false,"The kingdom is still standing." end
    for e in pairs(K.actors) do if e._world==w.id then e.object:remove() end end
    H.stop_disaster(w,true)
    -- Tower/wall nodes and player builds remain as earned defenses for the next round.
    local towers,walls=s.towers,s.walls
    H.state(w).kingdom=nil; s=K.state(w); s.towers,s.walls=towers,walls
    H.state(w).cycle_start=H.clock.elapsed; H.state(w).night_event=nil
    K.runtime[w.id]=nil; H.save(w); return true,"Your blue bunnies rally for a fresh day!"
  end
  if s.status~="playing" then return false,"Round finished. /kingdom restart to play again." end
  if action=="follow" or action=="defend" or action=="hold" then s.order=action; H.save(w); return true,"Blue army: "..action.."!" end
  local cost=costs[action]
  if not cost then return false,"Unknown kingdom action." end
  if (action=="guard" or action=="slinger" or action=="bomber") and s.guards>=12 then return false,"Maximum 12 blue guards." end
  if action=="worker" and s.workers>=6 then return false,"Maximum 6 workers." end
  if action=="tower" and #s.towers>=16 then return false,"Maximum 16 towers." end
  if action=="wall" and #s.walls>=40 then return false,"Maximum 40 wall sections." end
  if action=="repair" and s.hp>=100 then return false,"Castle already at full strength." end
  local positions={}
  if action=="tower" or action=="wall" then
    local d=p:get_look_dir(); local q=vector.round(vector.offset(p:get_pos(),d.x*3,0,d.z*3))
    local y=H.ground(q.x,q.z,30)
    if not y or brickcraft.world_at(q)~=w or math.abs(q.x-w.x)>22 or math.abs(q.z-w.z)>22 then
      return false,"Build on open ground within 22 blocks of the castle."
    end
    q.y=y
    local height=action=="tower" and 4 or 3
    for dy=0,height-1 do
      local cell=vector.offset(q,0,dy,0)
      if C.get_node(cell).name~="air" then return false,"Choose a clear spot." end
      for _,player in ipairs(H.players_in(w)) do
        if H.flat(cell,player:get_pos())<.8 and math.abs(cell.y-player:get_pos().y)<2 then return false,"Someone is standing there." end
      end
      positions[#positions+1]=cell
    end
  end
  local ok,msg=spend(s,cost); if not ok then return false,msg end
  if action=="guard" then s.guards=s.guards+1
  elseif action=="slinger" then s.guards=s.guards+1; s.slingers=(s.slingers or 0)+1
  elseif action=="bomber" then s.guards=s.guards+1; s.bombers=(s.bombers or 0)+1
  elseif action=="worker" then s.workers=s.workers+1
  elseif action=="repair" then s.hp=math.min(100,s.hp+30)
  elseif action=="supplies" then s.wood=math.min(999,s.wood+16); s.stone=math.min(999,s.stone+12)
  else
    for _,q in ipairs(positions) do C.set_node(q,{name=PREFIX..(action=="tower" and "kingdom_tower" or "kingdom_wall")}) end
    local list=action=="tower" and s.towers or s.walls
    list[#list+1]=positions[#positions]
  end
  H.save(w); return true,action=="supplies" and "Shop: received 16 wood and 12 stone." or "Kingdom: "..action.." ready!"
end
function K.panel(p,message)
  local w=H.world_at(p:get_pos())
  if not iskingdom(w) then return end
  local E=C.formspec_escape
  local fs="formspec_version[6]size[12,12]bgcolor[#172d40;true]"..
    "label[.6,.6;BUNNY KINGDOM / BUILD & DEFEND]"..
    "textarea[.6,1.1;10.8,1.6;;;"..E(K.line(w)).."]"..
    "textarea[.6,2.7;10.8,1.65;;;"..E("You lead the blue bunnies. Survive three nights with your castle standing.\nDay: red army. Night: zombies. Workers bring food and water home.\nUse the gathering basket on berries, crops, water, trunks and rocks.\nTowers fire at enemies within 13 blocks; walls shape the attackers' path.").."]"
  for i,b in ipairs({{"guard","Blue guard: 8 food + 4 water"},{"worker","Worker: 10 food"},
    {"tower","Tower: 16 wood + 12 stone"},{"wall","Wall: 8 wood + 4 stone"},
    {"repair","Repair +30: 8 wood + 6 stone"},{"supplies","16 wood + 12 stone: 8 food + 4 water"},
    {"slinger","Berry slinger: 10 food + 5 water"},{"bomber","Acorn bomber: 12 food + 6 water"},
    {"defend","Army: defend castle"},{"follow","Army: follow leader"},{"hold","Army: hold near castle"}}) do
    local col=(i-1)%2; local row=math.floor((i-1)/2)
    fs=fs.."button["..(.6+col*5.5)..","..(4.5+row*.8)..";5.3,.7;"..b[1]..";"..E(b[2]).."]"
  end
  fs=fs.."textarea[.6,9.6;10.8,1;;;"..E(message or "I: equip Carrot Lance, Radish Hammer, Berry Slingshot, Acorn Launcher or Cabbage Shield.\nTower / wall: face an empty spot 3 blocks ahead. Normal bricks work too.").."]"..
    "button[.6,11;3.4,.8;restart;Restart finished round]button_exit[8,11;3.4,.8;go;Lead your bunnies!]"
  C.show_formspec(p:get_player_name(),"brickcraft_habitat:kingdom",fs)
end
C.register_on_player_receive_fields(function(p,form,fields)
  if form~="brickcraft_habitat:kingdom" then return end
  if fields.quit or fields.go then return true end
  local msg
  for _,id in ipairs({"guard","slinger","bomber","worker","tower","wall","repair","supplies","defend","follow","hold","restart"}) do
    if fields[id] then local _; _,msg=K.action(p,id); break end
  end
  K.panel(p,msg); return true
end)
local entering=false
local function create_kingdom(owner,ready)
  if entering then return false,"Bunny Kingdom is being built. Try /kingdom enter shortly." end
  entering=true
  local w=brickcraft.make_world("Bunny Kingdom",owner,function(made)
    made.habitat="kingdom"; brickcraft.save_worlds()
    H.state(made).kingdom_preparing=true
    -- Only the brand-new world's workshop demo bricks are removed.
    H.clear_bricks(made,function()
      H.state(made).kingdom_preparing=nil
      H.setup(made,function()
        entering=false
        if ready then ready(made) end
      end)
    end)
  end)
  if not w then entering=false; return false,"No room for another world." end
  return true,"Building Bunny Kingdom..."
end
function K.enter(p)
  local function join(w)
    if not p:get_pos() then return end
    if brickcraft.war and brickcraft.war.on(p) then brickcraft.war.stop(p) end
    p:set_pos(at(w,0,1,-9)); H.set_skin(p,"gray")
    brickcraft.storage:set_string("world_"..(brickcraft.playing_as(p) or p:get_player_name()),tostring(w.id))
    H.defense_kit(p)
    if brickcraft.count_of(p,PREFIX.."gather")==0 then brickcraft.give(p,PREFIX.."gather") end
    K.panel(p)
  end
  for _,w in ipairs(brickcraft.worlds()) do if iskingdom(w) and w.built then join(w); return true end end
  return create_kingdom(brickcraft.playing_as(p) or p:get_player_name(),join)
end
C.after(3,function()
  if C.get_modpath("brickcraft_test") then return end
  for _,w in ipairs(brickcraft.worlds()) do
    if iskingdom(w) or w.name:lower():gsub("%s","")=="bunnykingdom" then return end
  end
  create_kingdom("everyone")
end)
C.register_chatcommand("kingdom",{params="[enter|restart|guard|slinger|bomber|worker|tower|wall|repair|supplies|defend|follow|hold]",
  description="Bunnyland tower defense: lead your blue bunny kingdom",
  func=function(name,param)
    local p=C.get_player_by_name(name); if not p then return false end
    local w=H.world_at(p:get_pos())
    if param=="enter" or (param=="" and not iskingdom(w)) then return K.enter(p) end
    if param=="" then K.panel(p); return true end
    local ok,msg=K.action(p,param); K.panel(p,msg); return ok,msg
  end})
brickcraft.help[#brickcraft.help+1]={"/kingdom enter","Bunny Kingdom: Bunnyland + tower defense. Gather, build and survive 3 nights."}
local original_welcome=H.welcome
function H.welcome(p)
  if iskingdom(H.world_at(p:get_pos())) then K.panel(p) else original_welcome(p) end
end
local original_cycle_line=H.cycle_line
function H.cycle_line(w)
  if not iskingdom(w) then return original_cycle_line(w) end
  local phase=H.cycle_status(w)
  return (phase.night and "NIGHT: zombie bunny attack" or "DAY: red army raids").." | "..phase.remaining.."s | Move, build and fight"
end
function K.step(w,dt)
  local s=K.state(w)
  local phase=H.cycle_status(w)
  if s.last_night==nil then s.last_night=phase.night end
  local rt=K.runtime[w.id]
  if not rt then
    rt={raid=25,night=s.last_night,cycle=phase.cycle,supply=0,tower=0,disaster=100}
    K.runtime[w.id]=rt
  end
  rt.raid=rt.raid or 25; rt.supply=(rt.supply or 0)+dt; rt.tower=(rt.tower or 0)+dt; rt.disaster=(rt.disaster or 100)-dt
  if s.status~="playing" then return end
  -- Restore exactly the persistent roster, even after a server restart.
  for _,spec in ipairs({{"king",1,"spear"},{"guard",s.guards-(s.slingers or 0)-(s.bombers or 0),"spear"},
    {"guard",s.slingers or 0,"sling"},{"guard",s.bombers or 0,"acorn"},{"worker",s.workers,"spear"}}) do
    for i=count(w,spec[1],spec[3])+1,spec[2] do
      local obj=K.spawn(w,spec[1],at(w,spec[1]=="king" and 0 or i*1.3-4,.1,spec[1]=="king" and 17 or 1),false,spec[3])
      if obj then obj:get_luaentity()._slot=i end
    end
  end
  if phase.night~=rt.night then
    if phase.night then K.wave(w,true)
    else
      s.nights=s.nights+1
      if s.nights>=3 then s.status="won"; H.tell(w,"Victory! Your blue bunnies saved Bunny Kingdom through three nights!","#ffe27a") end
    end
    rt.night=phase.night; rt.raid=phase.night and 20 or 30
    s.last_night=phase.night; H.save(w)
  end
  rt.raid=rt.raid-dt
  if rt.raid<=0 then K.wave(w,phase.night); rt.raid=phase.night and 24 or 40 end
  if rt.supply>=20 then
    rt.supply=0
    -- Army upkeep makes gathering relevant; an empty store weakens castle readiness.
    if s.food>=2 and s.water>=2 then s.food=s.food-2; s.water=s.water-2
    else K.damage_castle(w,2,true); H.tell(w,"Low supplies! Gather food and water to keep the castle ready.") end
    H.save(w)
  end
  if rt.tower>=1 then
    rt.tower=0
    for _,q in ipairs(s.towers) do
      if C.get_node(q).name==PREFIX.."kingdom_tower" then
        local best,dist
        for e in pairs(K.actors) do if e._world==w.id and e._role=="enemy" then
          local pos=e.object:get_pos()
          if pos then
            local d=vector.distance(q,pos)
            if d<13 and (not dist or d<dist) and C.line_of_sight(tower_origin(q,pos),vector.offset(pos,0,1,0)) then best,dist=e,d end
          end
        end end
        if best then
          local endpos=vector.offset(best.object:get_pos(),0,1,0)
          local origin=tower_origin(q,endpos)
          local dir=vector.direction(origin,endpos)
          C.add_particle({pos=origin,velocity=vector.multiply(dir,18),expirationtime=dist/18,
            size=2,texture="brickcraft_gold.png"})
          damage(best,2)
        end
      end
    end
  end
  if rt.disaster<=0 and not H.active[w.id] then
    rt.disaster=140
    local ids={"snow","asteroids","tsunami"}
    H.start_disaster(w,ids[(s.wave%3)+1])
  end
end
local timer=0
C.register_globalstep(function(dt)
  timer=timer+dt; if timer<.5 then return end
  local elapsed=timer; timer=0
  local seen={}
  for _,p in ipairs(C.get_connected_players()) do
    local w=H.world_at(p:get_pos())
    if iskingdom(w) and H.state(w).built then
      if brickcraft.count_of(p,PREFIX.."gather")==0 then brickcraft.give(p,PREFIX.."gather") end
      for id in pairs(weapon_specs) do
        if brickcraft.count_of(p,PREFIX..id)==0 then brickcraft.give(p,PREFIX..id) end
      end
      if not seen[w.id] then seen[w.id]=true; K.step(w,elapsed) end
    end
  end
  for id in pairs(K.runtime) do if not seen[id] then K.runtime[id]=nil end end
end)
end
