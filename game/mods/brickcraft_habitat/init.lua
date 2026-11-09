-- Habitats: a world full of small animals for players to keep safe from predators and
-- disasters by building fences and bunkers and keeping food and water secure.
--
-- Everything is a registry, so a new habitat (penguins, deer...) is only definitions:
--   H.register_creature(id,def)  the animals to protect (an entity each)
--   H.register_predator(id,def)  what hunts them (walks, or flies like the eagle)
--   H.register_source(id,def)    food and water nodes players place and protect
--   H.register_skin(id,def)      looks players can wear (/skin)
--   H.register_disaster(id,def)  flood, earthquake, asteroids... started with /disaster
--   H.register_variant(id,def)   a habitat: its creature, statue, sources, predators,
--                                skins, and which world names turn into it
-- Bunnyland (variants/bunny.lua) is the first variant. A world is a habitat when its
-- record has habitat=<variant id>: set by a variant's match_names, or /habitat set <id>.
local C=core
local H={variants={},variant_list={},creatures={},predators={},predator_list={},sources={},skins={},skin_list={},
  disasters={},disaster_list={},active={},live={},hunters={}}
local storage=brickcraft.storage
local MP=C.get_modpath("brickcraft_habitat")
local EDGE=46      -- a world's square reaches ±EDGE from its center (core landscape)
local LEASH=38     -- creatures stay this close to their world's center
local testing=brickcraft.testing
local habitat_test=C.settings:get_bool("brickcraft_habitat_test",false)
local function now() return C.get_us_time()/1e6 end
local function flat(a,b) return math.sqrt((a.x-b.x)^2+(a.z-b.z)^2) end
local function face(obj,d) obj:set_yaw(math.atan2(-d.x,d.z)) end
local function rnd(a,b) return a+math.random()*(b-a) end
H.now,H.flat,H.face,H.EDGE,H.LEASH=now,flat,face,EDGE,LEASH

------------------------------------------------------------------------------------------
-- Worlds and their habitat state
------------------------------------------------------------------------------------------
local states={}
-- Saved per world: born, lost, wild (false: no predators come by themselves),
-- built (statue and starter sources made), spawned (first creatures out).
function H.state(w)
  if not states[w.id] then
    states[w.id]=C.deserialize(storage:get_string("habitat_"..w.id)) or {born=0,lost=0}
  end
  return states[w.id]
end
function H.save(w) storage:set_string("habitat_"..w.id,C.serialize(H.state(w))) end
function H.variant_of(w) return w and w.habitat and H.variants[w.habitat] end
-- The habitat world holding pos, and its variant; nil outside habitats.
function H.world_at(pos)
  local w=brickcraft.world_at(pos)
  local v=H.variant_of(w)
  if v then return w,v end
end
local function players_in(w)
  local out={}
  for _,p in ipairs(C.get_connected_players()) do
    if brickcraft.world_at(p:get_pos())==w then out[#out+1]=p end
  end
  return out
end
H.players_in=players_in
function H.tell(w,msg,color)
  for _,p in ipairs(players_in(w)) do C.chat_send_player(p:get_player_name(),C.colorize(color or "#ffd27a",msg)) end
end
-- The first free cell above walkable ground at x, z (searching down from top); nil when
-- the column isn't loaded.
local function solid(name)
  local d=C.registered_nodes[name]
  return d and d.walkable
end
function H.ground(x,z,top)
  for y=math.floor(top or 34),-2,-1 do
    local n=C.get_node({x=x,y=y,z=z}).name
    if n=="ignore" then return nil end
    if solid(n) then return y+1 end
  end
end
-- Check from the creature's feet up, including low ceilings in its rounded cell.
-- Tall player-built roofs count too, well above the eagle's flight altitude.
function H.sheltered(pos)
  local x,y,z=math.floor(pos.x+.5),math.floor(pos.y),math.floor(pos.z+.5)
  if H.hidden(pos) then return true end
  for dy=1,128 do if solid(C.get_node({x=x,y=y+dy,z=z}).name) then return true end end
  return false
end
-- Inside a hideout (a hutch): no predator reaches it, nothing from the sky hits it.
function H.hidden(pos)
  return C.get_item_group(C.get_node({x=math.floor(pos.x+.5),y=math.floor(pos.y+.5),z=math.floor(pos.z+.5)}).name,"habitat_hideout")>0
end
-- Things the landscape is made of: statues and craters may replace these, never bricks.
local LANDSCAPE={air=true,["brickcraft:grass"]=true,["brickcraft:dirt"]=true,["brickcraft:trunk"]=true,["brickcraft:leaves"]=true}
H.LANDSCAPE=LANDSCAPE

------------------------------------------------------------------------------------------
-- Statues: giant brick sculptures made of statue bricks the separator can't take.
------------------------------------------------------------------------------------------
local LABEL={}
for _,c in ipairs(brickcraft.colors) do
  LABEL[c]=c:sub(1,1):upper()..c:sub(2)
  C.register_node("brickcraft_habitat:statue_"..c,{description=LABEL[c].." statue brick",
    tiles={"brickcraft_"..c..".png"},groups={habitat_statue=1,not_in_creative_inventory=1},drop=""})
end
-- Sculpting helpers for a variant's statue(put): put(x,y,z,color) fills one cell relative
-- to the statue's base (y=0 is the ground), later puts winning.
H.sculpt={
  ellipsoid=function(put,cx,cy,cz,rx,ry,rz,color)
    for x=math.floor(cx-rx),math.ceil(cx+rx) do for y=math.floor(cy-ry),math.ceil(cy+ry) do for z=math.floor(cz-rz),math.ceil(cz+rz) do
      if ((x-cx)/rx)^2+((y-cy)/ry)^2+((z-cz)/rz)^2<=1 then put(x,y,z,color) end
    end end end
  end,
  box=function(put,x0,y0,z0,x1,y1,z1,color)
    for x=x0,x1 do for y=y0,y1 do for z=z0,z1 do put(x,y,z,color) end end end
  end,
}
local function build_statue(w,v,done)
  local s=v.statue
  if not s then if done then done() end return end
  local cx,cz,R,top=w.x+(s.x or 0),w.z+(s.z or 37),s.radius or 7,s.height or 30
  local minp,maxp={x=cx-R,y=-2,z=cz-R},{x=cx+R,y=top,z=cz+R}
  C.emerge_area(minp,maxp,function(_,_,remaining)
    if remaining>0 then return end
    local vm=C.get_voxel_manip()
    local emin,emax=vm:read_from_map(minp,maxp)
    local area=VoxelArea:new({MinEdge=emin,MaxEdge=emax})
    local data=vm:get_data()
    local air,grass=C.get_content_id("air"),C.get_content_id("brickcraft:grass")
    local land={}
    for name in pairs(LANDSCAPE) do land[C.get_content_id(name)]=true end
    -- Level the spot: the hill and its trees go, the ground stays at the baseplate's height.
    for z=minp.z,maxp.z do for x=minp.x,maxp.x do for y=-1,top do
      local i=area:index(x,y,z)
      if land[data[i]] then data[i]=y==-1 and grass or air end
    end end end
    local ids={}
    s.build(function(x,y,z,color)
      if math.abs(x)>R or math.abs(z)>R or y<0 or y>top then return end
      ids[color]=ids[color] or C.get_content_id("brickcraft_habitat:statue_"..color)
      local i=area:index(cx+x,y,cz+z)
      if data[i]==air or C.get_name_from_content_id(data[i]):find("^brickcraft_habitat:statue_") then data[i]=ids[color] end
    end,H.sculpt)
    vm:set_data(data); vm:write_to_map(true)
    C.log("action","BrickCraft habitat: "..v.label.." statue built in "..w.name)
    if done then done() end
  end)
end

------------------------------------------------------------------------------------------
-- Food and water sources
------------------------------------------------------------------------------------------
-- def: kind ("food"/"water"), label, tiles, empty_tiles (when eaten up), inventory_image,
-- units (servings; nil = never runs out), regrow (seconds per serving), height (0..1).
function H.register_source(id,def)
  def.id,def.name=id,"brickcraft_habitat:"..id
  H.sources[id]=def
  local h=(def.height or .3)-.5
  local box={type="fixed",fixed={-.5,-.5,-.5,.5,h,.5}}
  local function refill_timer(pos) if def.units then C.get_node_timer(pos):start(def.regrow or 30) end end
  local base={description=def.label..(def.units and "\n"..def.units.." servings, regrows" or "\nNever runs out")..
      "\nRight click with the separator: pick up",
    drawtype="nodebox",node_box=box,selection_box=box,collision_box=box,paramtype="light",
    use_texture_alpha=def.alpha and "clip" or nil,
    inventory_image=def.inventory_image,wield_image=def.inventory_image,range=7,stack_max=99,
    sunlight_propagates=true,drop=def.name,brickcraft_shape="habitat",
    after_place_node=function(pos,placer) if H.claim then H.claim(pos,placer) end end,
    brickcraft_turn=function(pos,node,player)
      if not brickcraft.room_for(player,def.name) then return end
      C.remove_node(pos); brickcraft.give(player,def.name)
    end,
    on_construct=function(pos)
      if def.units then C.get_meta(pos):set_int("units",def.units) end
      H.describe_source(pos)
    end,
    on_timer=function(pos)
      local meta=C.get_meta(pos)
      local n=math.min(def.units,meta:get_int("units")+1)
      meta:set_int("units",n)
      if C.get_node(pos).name~=def.name then C.swap_node(pos,{name=def.name}) end
      H.describe_source(pos)
      return n<def.units
    end,
  }
  local full=table.copy(base)
  full.tiles=def.tiles
  full.groups={habitat_source=1,["habitat_"..def.kind]=1}
  C.register_node(def.name,full)
  if def.units then
    local empty=table.copy(base)
    empty.tiles=def.empty_tiles or def.tiles
    empty.groups={habitat_source=1,not_in_creative_inventory=1}
    empty.description=def.label.." (eaten up, regrowing)"
    C.register_node(def.name.."_empty",empty)
  end
  def.refill_timer=refill_timer
end
local function source_def(name) return H.sources[(name:match("^brickcraft_habitat:(.-)_empty$") or name:match("^brickcraft_habitat:(.+)$") or "")] end
function H.describe_source(pos)
  local def=source_def(C.get_node(pos).name)
  if not def then return end
  local meta=C.get_meta(pos)
  meta:set_string("infotext",def.units and def.label..": "..meta:get_int("units").."/"..def.units or def.label)
end
-- One serving from the source at pos; false when there's none left.
function H.consume(pos)
  local node=C.get_node(pos)
  local def=source_def(node.name)
  if not def or node.name~=def.name then return false end
  if not def.units then return true end
  local meta=C.get_meta(pos)
  local n=meta:get_int("units")-1
  meta:set_int("units",math.max(0,n))
  if n<=0 then C.swap_node(pos,{name=def.name.."_empty"}) end
  local timer=C.get_node_timer(pos)
  if not timer:is_started() then timer:start(def.regrow or 30) end
  H.describe_source(pos)
  return n>=0
end
-- Spoils a source (a flood, an asteroid): eaten up, regrowing from nothing.
function H.spoil(pos)
  local def=source_def(C.get_node(pos).name)
  if not def or not def.units then return end
  C.get_meta(pos):set_int("units",0)
  C.swap_node(pos,{name=def.name.."_empty"})
  C.get_node_timer(pos):start(def.regrow or 30)
  H.describe_source(pos)
end

------------------------------------------------------------------------------------------
-- Creatures
------------------------------------------------------------------------------------------
local function poof(pos,tex)
  C.add_particlespawner({amount=14,time=.2,minpos=vector.offset(pos,-.3,0,-.3),maxpos=vector.offset(pos,.3,.6,.3),
    minvel={x=-1.5,y=.5,z=-1.5},maxvel={x=1.5,y=2.5,z=1.5},minexptime=.4,maxexptime=.9,minsize=1.5,maxsize=3,
    texture=tex or "brickcraft_smoke.png"})
end
H.poof=poof
local function stuck_jump(self,moveresult,v,leaps)
  if not moveresult or not moveresult.touching_ground then return end
  -- Only from standing: the step after a jump may still touch the ground, and jumps must
  -- not stack (a wall two bricks high stops anything with one jump).
  -- Pressed against a wall, the engine can say "on the ground" at the top of a jump, so
  -- the ground under the feet is checked too. A blocking node with another on top of it
  -- is a wall too high to try.
  local vel=self.object:get_velocity()
  if vel.y>.1 then return end
  local p=self.object:get_pos()
  if not solid(C.get_node({x=math.floor(p.x+.5),y=math.floor(p.y+.3),z=math.floor(p.z+.5)}).name) then return end
  local feet=math.floor(p.y+.5)
  local step
  for _,c in ipairs(moveresult.collisions or {}) do
    if c.type=="node" and (c.axis=="x" or c.axis=="z") then
      -- The column it ran into, at its own feet: one brick to hop up, or a wall.
      local q=c.node_pos
      if solid(C.get_node({x=q.x,y=feet+1,z=q.z}).name) then return end
      -- Fences are meant to hold: only a leaper (the lion) tries one, even from a trough.
      if not leaps and C.get_item_group(C.get_node(q).name,"habitat_fence")>0 then return end
      if solid(C.get_node({x=q.x,y=feet,z=q.z}).name) then step=true end
    end
  end
  if step then self.object:set_velocity({x=vel.x,y=v,z=vel.z}); return true end
end
H.stuck_jump=stuck_jump
-- Wedged: something solid (a fence piece put down on top of it, a brick) where it stands,
-- and it hasn't moved for 2 s though it's trying to. It hops to the nearest free spot,
-- the one scoring best by score(spot) (a predator: away from its prey).
local function blocked_at(p)
  for _,dy in ipairs({0,1}) do
    local n=C.get_node({x=math.floor(p.x+.5),y=math.floor(p.y+.5)+dy,z=math.floor(p.z+.5)}).name
    if solid(n) then return true end
  end
  -- Or a fence piece's collision reaching into the cell beside it.
  for _,o in ipairs({{1,0},{-1,0},{0,1},{0,-1}}) do
    local q={x=math.floor(p.x+.5+o[1]*.35),y=math.floor(p.y+.5),z=math.floor(p.z+.5+o[2]*.35)}
    if C.get_item_group(C.get_node(q).name,"habitat_fence")>0 and (q.x~=math.floor(p.x+.5) or q.z~=math.floor(p.z+.5)) then
      local nd=C.get_node(q)
      if math.abs(p.x-q.x)<.45 or math.abs(p.z-q.z)<.45 then return true end
    end
  end
  return false
end
function H.unstick(self,score)
  local p=self.object:get_pos()
  local moved=self._was and vector.distance(p,self._was) or 1
  if moved>.2 or not self._target then self._was,self._still_since=p,now(); return false end
  if now()-(self._still_since or now())<2 or not blocked_at(p) then return false end
  local c={x=math.floor(p.x+.5),y=math.floor(p.y+.5),z=math.floor(p.z+.5)}
  local best,bs
  for r=1,2 do for dx=-r,r do for dz=-r,r do
    if math.max(math.abs(dx),math.abs(dz))==r then
      for _,dy in ipairs({0,1,-1}) do
        local q={x=c.x+dx,y=c.y+dy,z=c.z+dz}
        local function free(y) local n=C.get_node({x=q.x,y=y,z=q.z}).name; return not solid(n) and C.get_item_group(n,"habitat_fence")==0 end
        if free(q.y) and free(q.y+1) and solid(C.get_node({x=q.x,y=q.y-1,z=q.z}).name) then
          local s=(score and score(q) or 0)-r*.1
          if not bs or s>bs then best,bs=q,s end
        end
      end
    end
  end end if best then break end end
  self._was,self._still_since=nil,now()
  if not best then return false end
  self.object:set_pos({x=best.x,y=best.y-.45,z=best.z}); self.object:set_velocity({x=0,y=0,z=0})
  return true
end
-- Ran into something sideways this step.
function H.blocked(moveresult)
  for _,c in ipairs(moveresult and moveresult.collisions or {}) do
    if c.type=="node" and (c.axis=="x" or c.axis=="z") then return true end
  end
  return false
end
-- Walks toward target (a position) at speed; with a nil target it stands still.
-- A creature crowded by others (self._room, from H.make_room) leans away from them on the
-- way, and steps aside instead of standing still.
local function steer(self,target,speed)
  local p=self.object:get_pos()
  local vel=self.object:get_velocity()
  local room=self._room
  local d=target and {x=target.x-p.x,y=0,z=target.z-p.z}
  local l=d and math.sqrt(d.x^2+d.z^2) or 0
  if l<.3 then
    if room then self.object:set_velocity({x=room.x*.8,y=vel.y,z=room.z*.8}); face(self.object,room)
    else self.object:set_velocity({x=0,y=vel.y,z=0}) end
    return
  end
  local dx,dz=d.x/l,d.z/l
  if room then
    -- Still on its way (at least .4 of the speed, slowing behind one it's queued after).
    dx,dz=dx+room.x*.6,dz+room.z*.6
    local m=math.sqrt(dx*dx+dz*dz)
    if m>1 then dx,dz=dx/m,dz/m end
  end
  self.object:set_velocity({x=dx*speed,y=vel.y,z=dz*speed})
  face(self.object,d)
end
H.steer=steer
-- Of a few spots around p within r, the nearest one where ok(spot) holds.
local function find_spot(p,r,ok,tries)
  local best,bd
  for _=1,tries or 18 do
    local x,z=math.floor(p.x+rnd(-r,r)+.5),math.floor(p.z+rnd(-r,r)+.5)
    local g=H.ground(x,z,p.y+10)
    if g then
      local s={x=x,y=g,z=z}
      local d=flat(p,s)
      if (not bd or d<bd) and ok(s) then best,bd=s,d end
    end
  end
  return best
end
H.find_spot=find_spot
local function nearest_source(p,group,r)
  local list=C.find_nodes_in_area({x=p.x-r,y=p.y-4,z=p.z-r},{x=p.x+r,y=p.y+4,z=p.z+r},{"group:"..group})
  local best,bd
  for _,q in ipairs(list) do
    local d=flat(p,q)+math.abs(q.y-p.y)
    if not bd or d<bd then best,bd=q,d end
  end
  return best
end

-- Live creatures in w: all of them, owner's colony only (owner), or wild ones (false).
function H.creature_count(w,owner)
  local n=0
  for ent in pairs(H.live) do
    local p=ent.object:get_pos()
    if p and not ent._dead and brickcraft.world_at(p)==w and (owner==nil or (owner==false and not ent._owner) or ent._owner==owner) then n=n+1 end
  end
  return n
end
-- A creature is gone: counted lost, and everyone in its world hears how.
function H.lose(ent,how)
  if ent._dead then return end
  ent._dead=true
  local p=ent.object:get_pos()
  local w=p and brickcraft.world_at(p)
  if p then poof(p) end
  H.live[ent]=nil
  ent.object:remove()
  if w and H.variant_of(w) then
    local st=H.state(w); st.lost=(st.lost or 0)+1; H.save(w)
    if ent._owner and H.colony_lost then H.colony_lost(w,ent,how); return end
    local def=H.creatures[ent._kind]
    H.tell(w,"Oh no! A "..(def and def.label or "creature")..(how and " "..how or " was lost")..". "..
      H.creature_count(w).." left.","#ff9a8a")
  end
end
function H.hurt(ent,n,how)
  if not ent or ent._dead then return end
  ent._hp=(ent._hp or 1)-n
  ent._hurt=now()
  ent.object:set_texture_mod("^[colorize:#ff3030:110")
  C.after(.25,function() if ent.object:get_pos() then ent.object:set_texture_mod("") end end)
  if ent._hp<=0 then H.lose(ent,how) end
end

-- def: label, mesh, textures (one picked per creature), size, speed, run (fleeing speed),
-- jump, hp, hunger / thirst (seconds from full to empty), hop (bounce while moving).
function H.register_creature(id,def)
  def.id=id; def.name="brickcraft_habitat:"..id
  H.creatures[id]=def
  local k=def.size or 1
  local cb={-.22*k,0,-.22*k,.22*k,.6*k,.22*k}
  C.register_entity(def.name,{
    initial_properties={visual="mesh",mesh=def.mesh,textures={def.textures[1]},visual_size={x=10*k,y=10*k},
      physical=true,collide_with_objects=false,pointable=true,static_save=true,stepheight=.3,
      collisionbox=cb,selectionbox=cb,makes_footstep_sound=false},
    _kind=id,
    get_staticdata=function(self)
      return C.serialize({hp=self._hp,food=self._food,water=self._water,tex=self._tex,baby=self._baby,owner=self._owner,born=self._born})
    end,
    on_activate=function(self,staticdata)
      local d=C.deserialize(staticdata or "") or {}
      self._hp=d.hp or def.hp or 10
      self._food,self._water=d.food or 100,d.water or 100
      self._tex=d.tex or def.textures[math.random(#def.textures)]
      self._baby,self._owner=d.baby,d.owner
      if d.baby then self._born=now()-math.min(120,d.born and 60 or 0) end
      self._think,self._mood,self._sick=0,"wander",0
      self.object:set_armor_groups({immortal=1})
      self.object:set_acceleration({x=0,y=-2*9.81,z=0})
      self.object:set_yaw(rnd(0,6.28))
      self:_dress()
      H.live[self]=true
    end,
    on_deactivate=function(self) H.live[self]=nil end,
    _dress=function(self)
      local s=self._baby and .6 or 1
      local parent=self._carry_scale or {x=1,y=1,z=1}
      self.object:set_properties({textures={self._tex},visual_size={x=10*k*s/parent.x,y=10*k*s/parent.y,z=10*k*s/(parent.z or parent.x)},
        collisionbox={cb[1]*s,0,cb[3]*s,cb[4]*s,cb[5]*s,cb[6]*s},selectionbox={cb[1]*s,0,cb[3]*s,cb[4]*s,cb[5]*s,cb[6]*s}})
      -- A colony's creatures carry their owner's name, in the owner's color.
      local st=self._owner and brickcraft.styles[self._owner]
      if self._owner then
        self.object:set_properties({nametag=st and st.label or self._owner,nametag_color=st and st.tag or "#ffffff",nametag_bgcolor="#00000000"})
      end
    end,
    -- Patting one shows how it's doing.
    on_punch=function() return true end,
    on_rightclick=function(self,clicker)
      if not self._owner and H.domestication_panel then
        H.domestication_panel(self,clicker)
        return
      end
      -- Your own: it follows you (again: it stays). Anyone's: how it's doing.
      if self._owner and H.owner_of and H.owner_of(clicker)==self._owner then
        local name=clicker:get_player_name()
        if self._follow==name then self._follow=nil
          C.chat_send_player(name,C.colorize("#ffd27a","It stays here. (/colony stay: all of them, and this becomes their home)"))
        else self._follow,self._follow_until=name,now()+120
          C.chat_send_player(name,C.colorize("#ffd27a","It follows you for 2 minutes. Right click it again to let it stay."))
        end
      end
      local need=self._food<40 and "hungry" or self._water<40 and "thirsty" or "happy"
      local whose=self._owner and ((brickcraft.styles[self._owner] or {}).label or self._owner).."'s " or ""
      C.chat_send_player(clicker:get_player_name(),C.colorize("#ffd27a",whose..def.label..": "..need..
        " (food "..math.floor(self._food).."%, water "..math.floor(self._water).."%, hearts "..math.max(0,self._hp).."/"..(def.hp or 10)..")"))
    end,
    on_step=function(self,dtime,moveresult) H.creature_step(self,def,dtime,moveresult) end,
  })
end
function H.spawn_creature(id,pos,opts)
  local obj=C.add_entity(pos,"brickcraft_habitat:"..id)
  local ent=obj and obj:get_luaentity()
  if ent and opts then
    ent._owner=opts.owner
    if opts.baby then ent._baby=true; ent._born=now() end
    ent:_dress()
  end
  return ent
end

-- The nearest predator hunting near p within r.
local function nearest_hunter(p,r)
  local best,bd
  for ent in pairs(H.hunters) do
    local q=ent.object:get_pos()
    if q then
      local d=vector.distance(p,q)
      if d<r and (not bd or d<bd) then best,bd=ent,d end
    end
  end
  return best,bd
end
-- Creatures don't collide with objects (so players and predators can reach them), which
-- lets them walk into and stand inside one another. When others crowd one, the way out:
-- a flat unit vector away from them, or nil when it has room. A hideout (hutch) is made to
-- be shared, so in one, or with others in one, they stay together.
local function crowd_radius(ent)
  local d=H.creatures[ent._kind]
  return .22*(d and d.size or 1)*(ent._baby and .6 or 1)
end
function H.make_room(self,p)
  if H.hidden(p) then return nil end
  local r=crowd_radius(self)
  local px,pz,n=0,0,0
  for _,obj in ipairs(C.get_objects_inside_radius(p,1.5)) do
    local ent=obj:get_luaentity()
    if ent and ent~=self and H.live[ent] and not ent._dead and not ent._carried then
      local q=obj:get_pos()
      local apart=(r+crowd_radius(ent))*1.3
      if q and math.abs(q.y-p.y)<apart+.4 and not H.hidden(q) then
        local dx,dz=p.x-q.x,p.z-q.z
        local d=math.sqrt(dx*dx+dz*dz)
        if d<apart then
          -- Right on top of each other: any way will do (the other picks its own).
          if d<.01 then local a=rnd(0,6.28); dx,dz,d=math.cos(a),math.sin(a),1 end
          local push=(apart-d)/apart
          px,pz,n=px+dx/d*push,pz+dz/d*push,n+1
        end
      end
    end
  end
  if n==0 then return nil end
  local l=math.sqrt(px*px+pz*pz)
  if l<.001 then local a=rnd(0,6.28); return {x=math.cos(a),y=0,z=math.sin(a)} end
  return {x=px/l,y=0,z=pz/l}
end
function H.creature_step(self,def,dtime,moveresult)
  if self._dead or self._carried then return end
  local p=self.object:get_pos()
  -- Needs run down; empty, they hurt.
  self._food=math.max(0,self._food-dtime*100/(def.hunger or 360))
  self._water=math.max(0,self._water-dtime*100/(def.thirst or 240))
  if self._food<=0 or self._water<=0 then
    self._sick=self._sick+dtime
    if self._sick>8 then self._sick=0; H.hurt(self,1,self._food<=0 and "starved" or "had nothing to drink") end
    if self._dead then return end
  end
  if self._baby and now()-(self._born or 0)>120 then self._baby=nil; self:_dress() end
  local speed=def.speed or 2
  if self._target and moveresult and moveresult.touching_ground then
    if stuck_jump(self,moveresult,def.jump or 5.5) then
    else
      local vel=self.object:get_velocity()
      if def.hop and vel.y<=.1 and math.abs(vel.x)+math.abs(vel.z)>.5 then self.object:set_velocity({x=vel.x,y=def.hop,z=vel.z}) end
    end
  end
  self._think=self._think-dtime
  if self._think>0 then return end
  self._think=.3
  -- Standing in another one: whatever it does next, it makes room (see steer).
  self._room=H.make_room(self,p)
  local home=H.home_of and H.home_of(self)
  if H.unstick(self,function(s) return home and -H.flat(s,home) or 0 end) then return end
  local w,v=H.world_at(p)
  local danger=w and H.active[w.id]
  -- Drowning in a flood.
  local feet={x=math.floor(p.x+.5),y=math.floor(p.y+.8),z=math.floor(p.z+.5)}
  local wet=C.get_node(feet).name=="brickcraft_habitat:flood" or
    (H.hidden(feet) and C.get_node(vector.offset(feet,0,1,0)).name=="brickcraft_habitat:flood")
  -- Shallow water (feet) wears a creature down slowly; over its head, fast.
  if wet then
    local deep=C.get_node(vector.offset(feet,0,1,0)).name=="brickcraft_habitat:flood"
    -- By chance each moment, the same on average: some are luckier than others.
    if math.random()<.3/(deep and (def.deep or 3) or (def.shallow or 8)) then H.hurt(self,1,"was swept away by the flood") end
    if self._dead then return end
  end
  -- Fed and watered, it heals.
  if self._food>50 and self._water>50 and self._hp<(def.hp or 10) then
    self._heal=(self._heal or 0)+.3
    if self._heal>=(def.heal or 15) then self._heal=0; self._hp=self._hp+1 end
  end
  -- A player walking right up to it shoos it out of the way.
  for _,pl in ipairs(C.get_connected_players()) do
    local pp=pl:get_pos()
    if flat(p,pp)<.9 and math.abs(pp.y-p.y)<1.5 and self._follow~=pl:get_player_name() then
      local away={x=p.x-pp.x,y=0,z=p.z-pp.z}
      if vector.length(away)<.05 then away={x=rnd(-1,1),y=0,z=rnd(-1,1)} end
      self._target=vector.add(p,vector.normalize(away)); steer(self,self._target,3)
      return
    end
  end
  -- 1. Run from a predator close by, toward shelter if there's some near.
  local hunter,hd=nearest_hunter(p,H.alert_of and H.alert_of(self,p) or def.alert or 9)
  if hunter then
    local hp=hunter.object:get_pos()
    if not self._hide or now()>self._hide_until then
      self._hide=H.hideout_near and H.hideout_near(self,p) or find_spot(p,10,function(s) return H.sheltered(s) end,14)
      self._hide_until=now()+4
    end
    local away=vector.normalize({x=p.x-hp.x,y=0,z=p.z-hp.z})
    local target=self._hide and flat(self._hide,hp)>hd*.6 and self._hide or vector.add(p,vector.multiply(away,6))
    if self._hide and flat(p,self._hide)<.6 then target=nil end
    self._target=target; self._mood="flee"
    steer(self,target,def.run or speed*2)
    return
  end
  -- Following its owner (herding: right click, /colony call).
  if self._follow or self._follow_obj then
    local pp
    if self._follow_obj then pp=self._follow_obj:get_pos()
    else local pl=C.get_player_by_name(self._follow); pp=pl and pl:get_pos() end
    if not pp or now()>(self._follow_until or 0) or vector.distance(p,pp)>40 then self._follow,self._follow_obj=nil,nil
    else
      local d=flat(p,pp)
      self._target=d>1.8 and pp or nil
      steer(self,self._target,d>5 and (def.run or speed*2) or speed*1.4)
      return
    end
  end
  -- 2. A disaster: high ground from a flood, cover from the sky.
  if danger and danger.started then
    local want=danger.def.creatures_seek -- "high", "shelter" or nil
    if want or danger.def.panic then
      local ok=want=="high" and function(s) return s.y>=(danger.def.safe_y or 2) end or
        want=="shelter" and function(s) return H.sheltered(s) end
      local here={x=math.floor(p.x+.5),y=math.floor(p.y+.5),z=math.floor(p.z+.5)}
      if ok and ok(here) then self._target=nil; steer(self,nil); return end
      if ok and (not self._safe or now()>(self._safe_until or 0)) then
        self._safe=want=="shelter" and H.hideout_near and H.hideout_near(self,p) or find_spot(p,14,ok,20); self._safe_until=now()+3
      elseif not ok and now()>(self._safe_until or 0) then
        self._safe=nil; self._safe_until=now()+1.5
      end
      self._target=self._safe or (danger.def.panic and vector.add(p,{x=rnd(-4,4),y=0,z=rnd(-4,4)}))
      steer(self,self._target,def.run or speed*2)
      return
    end
  end
  -- 3. Eat and drink.
  for _,need in ipairs({{"_water","habitat_water"},{"_food","habitat_food"}}) do
    if self[need[1]]<55 then
      if not self._goal or self._goal_kind~=need[2] or now()>(self._goal_until or 0) then
        self._goal=nearest_source(p,need[2],24); self._goal_kind=need[2]; self._goal_until=now()+5
      end
      if self._goal then
        if flat(p,self._goal)<1.3 and math.abs(self._goal.y-p.y)<1.6 then
          if H.consume(self._goal) then self[need[1]]=100; self._hp=math.min(def.hp or 10,self._hp+1) end
          self._goal=nil; self._target=nil; steer(self,nil)
        else
          self._target=self._goal; steer(self,self._goal,speed)
        end
        return
      end
    end
  end
  -- 4. Wander, staying home.
  local home=H.home_of and H.home_of(self)
  local c=home or (w and {x=w.x,y=p.y,z=w.z})
  if c and flat(p,c)>(home and 12 or LEASH) then self._wander={x=c.x,y=p.y,z=c.z}; self._wander_until=now()+6 end
  if not self._wander or now()>(self._wander_until or 0) or flat(p,self._wander)<.6 then
    if math.random()<.4 then self._wander=nil
    else self._wander={x=p.x+rnd(-6,6),y=p.y,z=p.z+rnd(-6,6)} end
    self._wander_until=now()+rnd(2,5)
  end
  self._target=self._wander; self._mood="wander"
  steer(self,self._wander,speed*.6)
end

------------------------------------------------------------------------------------------
-- Predators
------------------------------------------------------------------------------------------
-- def: label, mesh, texture, size, hp, speed, damage (hearts per bite), bite (seconds
-- between bites), jump, flies (circles high and dives on creatures not under a roof),
-- appetite (creatures it catches before it goes), stay (seconds before it gives up),
-- from (where it comes from, said in chat).
function H.register_predator(id,def)
  def.id=id; def.name="brickcraft_habitat:"..id
  H.predators[id]=def; H.predator_list[#H.predator_list+1]=id
  local k=def.size or 1
  local cb=def.box or {-.3*k,0,-.3*k,.3*k,.9*k,.3*k}
  C.register_entity(def.name,{
    initial_properties={visual="mesh",mesh=def.mesh,textures={def.texture},visual_size={x=10*k,y=10*k},
      physical=not def.flies,collide_with_objects=false,pointable=true,static_save=false,stepheight=.3,
      collisionbox=cb,selectionbox=cb,nametag_color="#ffb0a0",nametag_bgcolor="#14293699"},
    _kind=id,
    on_activate=function(self)
      self._hp,self._caught,self._born,self._think,self._next_bite=def.hp or 6,0,now(),0,0
      self.object:set_armor_groups({immortal=1})
      if not def.flies then self.object:set_acceleration({x=0,y=-2*9.81,z=0}) end
      self:_tag()
      H.hunters[self]=true
    end,
    on_deactivate=function(self) H.hunters[self]=nil end,
    _tag=function(self) self.object:set_properties({nametag=def.label.."  "..math.max(0,self._hp).."/"..(def.hp or 6)}) end,
    -- A punch from a hand or a piece; the separator and war weapons come through _hit.
    on_punch=function(self,puncher,_,_,dir)
      if puncher and puncher:is_player() then self:_hit(puncher,{dmg=puncher:get_wielded_item():get_name()=="brickcraft:sword" and 3 or 1},nil,dir) end
      return true
    end,
    _brickcraft_collect=function(self,player) self:_hit(player,{dmg=1}) end,
    _hit=function(self,attacker,m,v,dir)
      if self._gone then return false end
      if self._carrying then -- it lets go: the creature drops, saved
        local c=self._carrying
        self._carrying=nil
        if c.object:get_pos() and not c._dead then
          c.object:set_detach(); c._carried=nil; c._carry_scale=nil
          c:_dress()
          c.object:set_velocity({x=0,y=0,z=0})
          local w=brickcraft.world_at(c.object:get_pos())
          H.tell(w,"The "..def.label:lower().." dropped the "..((H.creatures[c._kind] or {}).label or "animal"):lower().."!","#9be59b")
        end
      end
      local n=m and m.dmg or 1
      if n<=0 then n=1 end
      self._hp=self._hp-n
      local p=self.object:get_pos()
      local from=attacker and attacker:get_pos()
      local away=dir or (from and vector.subtract(p,from)) or {x=0,y=0,z=1}
      away={x=away.x,y=0,z=away.z}
      if vector.length(away)>0 then away=vector.normalize(away) end
      self.object:add_velocity(v or {x=away.x*6,y=def.flies and 2 or 4,z=away.z*6})
      self.object:set_texture_mod("^[colorize:#ffffff:140")
      C.after(.2,function() if self.object:get_pos() then self.object:set_texture_mod("") end end)
      self._scared=now()+1.2
      if self._hp<=0 then
        local w=brickcraft.world_at(p)
        poof(p); self._gone=true; H.hunters[self]=nil; self.object:remove()
        H.tell(w,"You chased the "..def.label:lower().." away!","#9be59b")
      else self:_tag() end
      return true
    end,
    on_step=function(self,dtime,moveresult)
      if def.flies then H.flyer_step(self,def,dtime) else H.walker_step(self,def,dtime,moveresult) end
    end,
  })
end
local function nearest_prey(p,r,ok)
  local best,bd
  for ent in pairs(H.live) do
    local q=ent.object:get_pos()
    if q and not ent._dead and not H.hidden(q) then
      local d=vector.distance(p,q)
      if d<r and (not bd or d<bd) and (not ok or ok(ent,q)) then best,bd=ent,d end
    end
  end
  return best,bd
end
-- Bite effects: a tuft of fur flies, the creature is knocked away squealing (it flashes).
function H.bite_fx(prey,dir)
  local q=prey.object:get_pos()
  if not q then return end
  C.add_particlespawner({amount=12,time=.15,minpos=vector.offset(q,-.15,.2,-.15),maxpos=vector.offset(q,.15,.5,.15),
    minvel={x=-1.5,y=1,z=-1.5},maxvel={x=1.5,y=3,z=1.5},minacc={x=0,y=-6,z=0},maxacc={x=0,y=-6,z=0},
    minexptime=.4,maxexptime=.9,minsize=1,maxsize=2,texture="brickcraft_habitat_fur.png"})
  if not prey._carried then prey.object:add_velocity({x=(dir.x or 0)*3,y=3,z=(dir.z or 0)*3}) end
end
-- Leans the body (pitch) for a moment: a head-down lunge, a crouch-and-leap.
local function pose(self,pitch,secs)
  local r=self.object:get_rotation()
  self.object:set_rotation({x=pitch,y=r.y,z=0})
  C.after(secs,function() if self.object:get_pos() then local r2=self.object:get_rotation(); self.object:set_rotation({x=0,y=r2.y,z=0}) end end)
end
-- Full, tired or chased off: it heads out of the world and is gone.
local function leaving(self,def)
  return self._caught>=(def.appetite or 2) or now()-self._born>(def.stay or 150)
end
local function leave(self,p,w,speed)
  self._leaving=self._leaving or now()
  if now()-self._leaving>20 then poof(p); self._gone=true; H.hunters[self]=nil; self.object:remove(); return end
  local out={x=p.x-(w and w.x or p.x),y=0,z=p.z-(w and w.z or p.z)}
  if vector.length(out)<.1 then out={x=1,y=0,z=0} end
  out=vector.normalize(out)
  if w and flat(p,w)>EDGE+2 then self._gone=true; H.hunters[self]=nil; self.object:remove(); return end
  return vector.add(p,vector.multiply(out,8))
end
function H.walker_step(self,def,dtime,moveresult)
  if self._gone then return end
  if self._target then
    stuck_jump(self,moveresult,def.jump or 6.6,def.leaps)
    if H.blocked(moveresult) then
      self._blocked=(self._blocked or 0)+dtime
      self._pressed=(self._pressed or 0)+dtime -- time spent against something...
    else self._pressed=math.max(0,(self._pressed or 0)-dtime*.5) end -- ...lately
  end
  self._think=self._think-dtime
  if self._think>0 then return end
  self._think=.25
  local p=self.object:get_pos()
  local w=brickcraft.world_at(p)
  if (self._scared or 0)>now() then return end
  -- Wedged in something: out, on the side away from the prey it was after.
  local pa=self._prey_at
  if H.unstick(self,function(s) return pa and H.flat(s,pa) or 0 end) then self._detour,self._blocked=nil,0; return end
  local speed=def.speed or 3
  if leaving(self,def) then
    self._target=leave(self,p,w,speed)
    if self._target then steer(self,self._target,speed) end
    return
  end
  -- Blocked for a while (a fence): try going around for a bit.
  if (self._blocked or 0)>2.5 then
    self._blocked=0
    local side=math.random()<.5 and -1 or 1
    local yaw=self.object:get_yaw()+side*math.pi/2
    self._detour={x=p.x-math.sin(yaw)*5,y=p.y,z=p.z+math.cos(yaw)*5}; self._detour_until=now()+2
  end
  if self._detour and now()<self._detour_until then self._target=self._detour; steer(self,self._detour,speed); return end
  local prey,d=nearest_prey(p,def.sight or 40)
  if not prey then
    self._target=w and {x=w.x,y=p.y,z=w.z}; steer(self,self._target,speed*.6); return
  end
  local q=prey.object:get_pos()
  self._target=q
  self._prey_at=q
  -- Stuck (a fence, a cliff) with no way closer for 15 s: it gives up and goes.
  if not self._best or d<self._best-1 then self._best,self._best_at=d,now() end
  if now()-self._best_at>15 or (self._pressed or 0)>10 then
    self._caught=def.appetite or 2
    H.tell(w,"The "..def.label:lower().." couldn't get to the "..(H.variant_of(w) and H.variant_of(w).plural or "animals").." and gave up.","#9be59b")
    return
  end
  local dir={x=q.x-p.x,y=0,z=q.z-p.z}
  dir=vector.length(dir)>0 and vector.normalize(dir) or {x=0,y=0,z=1}
  local on_ground=math.abs(self.object:get_velocity().y)<.2
  -- In the middle of a pounce: let it fly.
  if self._leaping and now()<self._leaping then return end
  -- A pouncer (the lion) crouches and leaps from a few blocks out.
  if def.pounce and d<def.pounce and d>(def.reach or 1.3)+.3 and on_ground and now()>=(self._next_pounce or 0) then
    self._next_pounce,self._leaping=now()+3.5,now()+.7
    face(self.object,dir)
    self.object:set_velocity({x=dir.x*def.pounce*2.2,y=4.5,z=dir.z*def.pounce*2.2})
    pose(self,-.3,.5)
    return
  end
  if d<(def.reach or 1.3) and math.abs(q.y-p.y)<1.2 then
    face(self.object,dir)
    if now()>=self._next_bite then
      -- The bite: a lunge, head down.
      self._next_bite=now()+(def.bite or 1.2)
      self.object:set_velocity({x=dir.x*5,y=self.object:get_velocity().y,z=dir.z*5})
      pose(self,.35,.25)
      H.bite_fx(prey,dir)
      H.hurt(prey,def.damage or 4,"was caught by a "..def.label:lower())
      if prey._dead then self._caught=self._caught+1 end
    else steer(self,nil) end
    return
  end
  steer(self,q,speed)
end
function H.flyer_step(self,def,dtime)
  if self._gone then return end
  self._think=self._think-dtime
  if self._think>0 then return end
  self._think=.2
  local p=self.object:get_pos()
  local w=brickcraft.world_at(p)
  local alt=def.altitude or 14
  local function fly(to,speed)
    local d=vector.subtract(to,p)
    local l=vector.length(d)
    if l<.2 then self.object:set_velocity({x=0,y=0,z=0}); return end
    self.object:set_velocity(vector.multiply(d,speed/l))
    face(self.object,d)
  end
  -- Carrying one off: up and away; then it's gone.
  if self._carrying then
    local c=self._carrying
    if c._dead or not c.object:get_pos() then self._carrying=nil
    elseif now()>=self._carry_until then
      self._carrying=nil; self._caught=self._caught+1
      H.lose(c,"was carried off by an "..def.label:lower())
    else
      local out={x=p.x-(w and w.x or p.x),y=0,z=p.z-(w and w.z or p.z)}
      out=vector.length(out)>.1 and vector.normalize(out) or {x=1,y=0,z=0}
      fly(vector.add(p,{x=out.x*4,y=3,z=out.z*4}),5)
      return
    end
  end
  if (self._scared or 0)>now() then self._prey=nil; fly(vector.offset(p,0,6,0),6); return end
  if leaving(self,def) then
    local out=leave(self,p,w)
    if out then fly(vector.offset(out,0,4,0),def.speed or 7) end
    return
  end
  -- Prey must be in the open: a roof (or a tree) hides it from the sky.
  local open=function(ent,q) return not ent._carried and not H.sheltered(q)
    and C.line_of_sight(p,vector.offset(q,0,.2,0)) end
  if self._prey and (self._prey._dead or not self._prey.object:get_pos() or not open(self._prey,self._prey.object:get_pos())) then
    self._prey=nil
  end
  if not self._prey then self._prey=nearest_prey(p,def.sight or 45,open) end
  local prey=self._prey
  if not prey then
    -- Circle over the world's middle, waiting.
    local t=now()*.3
    local c=w and {x=w.x,z=w.z} or p
    fly({x=c.x+math.cos(t)*16,y=(H.ground(math.floor(c.x),math.floor(c.z),40) or 0)+alt,z=c.z+math.sin(t)*16},def.speed or 7)
    return
  end
  local q=prey.object:get_pos()
  local d=flat(p,q)
  if d>4 then fly({x=q.x,y=q.y+alt*.7,z=q.z},def.speed or 7)  -- get above it
  elseif vector.distance(p,q)>(def.reach or 1) then fly(vector.offset(q,0,.2,0),def.dive or 10) -- dive
  else
    -- It grabs the creature and carries it off; a hit before it's gone makes it let go.
    if not self._carrying then
      self._carrying=prey; prey._carried=true; self._prey=nil
      prey.object:set_velocity({x=0,y=0,z=0})
      -- Attachments inherit the parent's mesh scale (10 for these models).
      -- Compensate both the creature's size and its offset beneath the talons.
      local scale=self.object:get_properties().visual_size
      prey._carry_scale=scale
      prey:_dress()
      prey.object:set_attach(self.object,"",{x=0,y=-3.5/scale.y,z=-1/(scale.z or scale.x)},{x=0,y=0,z=0})
      H.bite_fx(prey,{x=0,y=1,z=0})
      self._carry_until=now()+(def.carry or 4)
    end
  end
end
-- How many come together: bigger colonies draw bigger packs (variant pack_per: one more
-- for every that many creatures in the biggest colony here).
function H.pack_size(w)
  local v=H.variant_of(w)
  if not (v and v.pack_per) then return 1 end
  local most=0
  for owner in pairs(H.state(w).colonies or {}) do most=math.max(most,H.creature_count(w,owner)) end
  return 1+math.floor(most/v.pack_per)
end
-- Where predators come in: the edge of the world, toward a side (opts.angle), a pack of
-- opts.n (default pack_size). Returns the first.
function H.spawn_predator(w,id,opts)
  local def=H.predators[id]
  if not def then return end
  opts=opts or {}
  local a=opts.angle or rnd(0,2*math.pi)
  local n=opts.n or H.pack_size(w)*(H.night_multiplier and H.night_multiplier(w) or 1)
  if n<=0 then return nil end
  local first
  -- Walkers come in on the flat grass ring around the baseplate (up in the hills, trees
  -- and steep steps can strand them); fliers from further out. Always on real ground:
  -- not a treetop, the statue or someone's roof.
  local r=def.flies and 36 or 26.5
  local GROUND={["brickcraft:grass"]=true,["brickcraft:dirt"]=true,["brickcraft:baseplate"]=true}
  for i=1,n do
    local b=a+(i-1)*.12
    local x,z,g
    for try=0,24 do
      local c=b+(try%2==0 and 1 or -1)*math.ceil(try/2)*.13
      x,z=math.floor(w.x+math.cos(c)*r+.5),math.floor(w.z+math.sin(c)*r+.5)
      g=H.ground(x,z,40)
      if g and GROUND[C.get_node({x=x,y=g-1,z=z}).name] then break end
      g=nil
    end
    if not g then x,z=w.x,w.z+26; g=H.ground(x,z,40) or 1 end
    local obj=C.add_entity({x=x,y=g+(def.flies and (def.altitude or 14) or .1),z=z},def.name)
    first=first or (obj and obj:get_luaentity())
  end
  local dir=math.abs(math.cos(a))>math.abs(math.sin(a)) and (math.cos(a)>0 and "east" or "west") or (math.sin(a)>0 and "north" or "south")
  local what=n>1 and n.." "..def.label:lower()..(def.label:sub(-1)=="f" and "" or "s").." are coming" or (def.warning or "A "..def.label:lower().." is coming")
  if n>1 and id=="wolf" then what=n.." wolves are coming" end
  H.tell(w,what.." from the "..dir.."!"..(def.tip and " "..def.tip or ""),"#ffb0a0")
  return first
end

------------------------------------------------------------------------------------------
-- Disasters
------------------------------------------------------------------------------------------
-- def: label, warning (said with the countdown), delay (seconds of warning), duration,
-- start(ctx), step(ctx,dtime), stop(ctx), creatures_seek ("high" or "shelter"), safe_y,
-- panic (creatures run about). ctx = {world, def, t, data={}}.
function H.register_disaster(id,def)
  def.id=id; H.disasters[id]=def; H.disaster_list[#H.disaster_list+1]=id
end
function H.start_disaster(w,id)
  local def=H.disasters[id]
  if not def then return false,"No such disaster." end
  if H.active[w.id] then return false,"A "..H.active[w.id].def.label:lower().." is already happening." end
  local ctx={world=w,def=def,t=0,data={},delay=def.delay or 8}
  H.active[w.id]=ctx
  H.tell(w,"!! "..def.label.." in "..ctx.delay.." seconds! "..(def.warning or ""),"#ff7a5a")
  return true
end
function H.stop_disaster(w,quiet)
  local ctx=H.active[w.id]
  if not ctx then return false end
  H.active[w.id]=nil
  if ctx.started and ctx.def.stop then ctx.def.stop(ctx) end
  if not quiet then
    H.tell(w,"The "..ctx.def.label:lower().." is over. "..H.creature_count(w).." "..
      (H.variant_of(w) and H.variant_of(w).plural or "creatures").." made it.","#9be59b")
  end
  return true
end
local function disaster_step(dtime)
  for _,ctx in pairs(H.active) do
    ctx.t=ctx.t+dtime
    if not ctx.started then
      if ctx.t>=ctx.delay then
        ctx.started=true; ctx.t=0
        if ctx.def.start then ctx.def.start(ctx) end
      end
    else
      if ctx.def.step then ctx.def.step(ctx,dtime) end
      if ctx.t>=(ctx.def.duration or 20) then H.stop_disaster(ctx.world) end
    end
  end
end

------------------------------------------------------------------------------------------
-- Skins
------------------------------------------------------------------------------------------
-- def: label, mesh, texture. Worn until /skin off; war mode's looks come first.
function H.register_skin(id,def)
  def.id=id; H.skins[id]=def; H.skin_list[#H.skin_list+1]=id
end
local function skin_of(p) return H.skins[p:get_meta():get_string("brickcraft_habitat_skin")] end
local function wear(p)
  local s=skin_of(p)
  if not s or (brickcraft.war and brickcraft.war.on and brickcraft.war.on(p)) then return end
  local props=p:get_properties()
  if props.mesh~=s.mesh or (props.textures or {})[1]~=s.texture then
    p:set_properties({visual="mesh",mesh=s.mesh,textures={s.texture}})
  end
end
function H.set_skin(p,id)
  if id and not H.skins[id] then return false end
  p:get_meta():set_string("brickcraft_habitat_skin",id or "")
  if id then wear(p)
  else
    local st=brickcraft.get_style(p)
    p:set_properties({visual="mesh",mesh=st.mesh,textures={st.tex}})
  end
  return true
end

------------------------------------------------------------------------------------------
-- Variants and setting up a habitat world
------------------------------------------------------------------------------------------
-- def: label (the habitat), creature (id), plural ("bunnies"), count (to start with),
-- max (most at once; well-fed ones have babies up to this), statue={x,z,radius,height,
-- build=function(put,sculpt)}, sources={{id,dx,dz},...} placed at the start,
-- kit={[source id]=n} (what /habitat kit gives), predators={ids}, disasters={ids}
-- (nil: all), skins={ids}, match_names={"bunnyland",...} (world names that become this
-- habitat), wave={min,max} (seconds between predators coming by themselves).
function H.register_variant(id,def)
  def.id=id; H.variants[id]=def; H.variant_list[#H.variant_list+1]=id
end
local function place_sources(w,v)
  for _,s in ipairs(v.sources or {}) do
    local x,z=w.x+s[2],w.z+s[3]
    local g=H.ground(x,z,30)
    if g and C.get_node({x=x,y=g,z=z}).name=="air" then C.set_node({x=x,y=g,z=z},{name="brickcraft_habitat:"..s[1]}) end
  end
end
-- Builds the statue and starter sources once; the creatures come when someone's there.
function H.setup(w,done)
  local v=H.variant_of(w)
  if not v then return end
  local st=H.state(w)
  if st.kingdom_preparing then return end
  if st.built then if done then done() end return end
  build_statue(w,v,function()
    local radius=v.kingdom and 46 or 30
    C.emerge_area({x=w.x-radius,y=-2,z=w.z-radius},{x=w.x+radius,y=40,z=w.z+radius},function(_,_,r)
      if r>0 then return end
      place_sources(w,v)
      if v.setup then v.setup(w) end
      st.built=true; H.save(w)
      if done then done() end
    end)
  end)
end
function H.populate(w,n)
  local v=H.variant_of(w)
  if not v then return 0 end
  local s=v.statue or {}
  local made=0
  for i=1,n or v.count or 8 do
    local a=i/(n or v.count or 8)*2*math.pi
    local x,z=math.floor(w.x+(s.x or 0)+math.cos(a)*4+.5),math.floor(w.z+(s.z or 37)-(s.radius or 7)-3+math.sin(a)*2+.5)
    local g=H.ground(x,z,30)
    if g and H.spawn_creature(v.creature,{x=x,y=g+.1,z=z}) then made=made+1 end
  end
  local st=H.state(w); st.spawned=true; st.born=(st.born or 0)+made; H.save(w)
  return made
end
function H.make_habitat(w,id)
  w.habitat=id; brickcraft.save_worlds()
  H.setup(w)
end
function H.give_kit(p,v)
  local got={}
  for sid,n in pairs(v.kit or {}) do
    local left=brickcraft.give(p,"brickcraft_habitat:"..sid.." "..n)
    got[#got+1]=(n-left:get_count()).." "..H.sources[sid].label
  end
  table.sort(got)
  return table.concat(got,", ")
end

------------------------------------------------------------------------------------------
-- HUD, the world's heartbeat, and commands
------------------------------------------------------------------------------------------
local hud={}
local next_wave,next_birth={},{}
-- The next predator comes on the new pace's schedule.
function H.reset_wave(w) next_wave[w.id]=nil end
-- Food and water sources ready in a world (counted at most every 3 s).
local supplies={}
function H.supplies(w,fresh)
  local s=supplies[w.id]
  if s and not fresh and now()-s.t<3 then return s.food,s.water end
  local food,water=0,0
  for _,q in ipairs(C.find_nodes_in_area({x=w.x-EDGE,y=-2,z=w.z-EDGE},{x=w.x+EDGE,y=24,z=w.z+EDGE},{"group:habitat_source"})) do
    local name=C.get_node(q).name
    if C.get_item_group(name,"habitat_food")>0 then food=food+1 elseif C.get_item_group(name,"habitat_water")>0 then water=water+1 end
  end
  supplies[w.id]={t=now(),food=food,water=water}
  return food,water
end
local function hud_text(w,v,p)
  if v.kingdom and H.kingdom then return H.kingdom.line(w).."\n"..H.cycle_line(w) end
  local st=H.state(w)
  local n=H.creature_count(w)
  local food,water=H.supplies(w)
  local line=v.label..":  "..n.." "..v.plural.."  (lost "..(st.lost or 0)..")   food "..food.."   water "..water
  local cl=p and H.colony_line and H.colony_line(p,w,v)
  if cl then line=line.."\n"..cl end
  if H.score_line and v.colony then line=line.."\n"..H.score_line(w,v) end
  if H.cycle_line and v.cycle then line=line.."\n"..H.cycle_line(w) end
  local ctx=H.active[w.id]
  if ctx then
    line=line.."\n"..(ctx.started and "!! "..ctx.def.label.."! "..math.max(0,math.ceil((ctx.def.duration or 20)-ctx.t)).." s" or
      "!! "..ctx.def.label.." in "..math.max(0,math.ceil(ctx.delay-ctx.t)).." s: "..(ctx.def.warning or ""))
  end
  return line
end
local function update_hud(p,text)
  local name=p:get_player_name()
  if not text then
    if hud[name] then p:hud_remove(hud[name].id); hud[name]=nil end
    return
  end
  if not hud[name] then
    hud[name]={id=p:hud_add({type="text",position={x=.5,y=0},offset={x=0,y=58},alignment={x=0,y=1},
      text=text,number=0xFFE6A8,size={x=1,y=0},z_index=10}),text=text}
  elseif hud[name].text~=text then
    p:hud_change(hud[name].id,"text",text); hud[name].text=text
  end
end
C.register_on_leaveplayer(function(p) hud[p:get_player_name()]=nil end)
local tick,bind_wait=0,5
C.register_globalstep(function(dtime)
  if H.cycle_step then H.cycle_step(dtime) end
  disaster_step(dtime)
  tick=tick+dtime
  if tick<1 then return end
  tick=0
  bind_wait=bind_wait-1
  if bind_wait<=0 then bind_wait=5; H.bind_names() end
  local seen={}
  for _,p in ipairs(C.get_connected_players()) do
    wear(p)
    local w,v=H.world_at(p:get_pos())
    update_hud(p,w and hud_text(w,v,p))
    if not testing and not habitat_test and H.welcome_check then H.welcome_check(p,w) end
    if w then
      if v.defense and H.defense_kit then H.defense_kit(p) end
      seen[w.id]={w=w,v=v}
    end
  end
  for id,e in pairs(seen) do
    local w,v,st=e.w,e.v,H.state(e.w)
    if not st.built then H.setup(w)
    elseif v.meadow and not st.meadow and not st.meadow_laying then
      st.meadow_laying=true
      H.lay_meadow(w,v,function() st.meadow=true; st.meadow_laying=nil; H.save(w) end)
    elseif not st.spawned then H.populate(w)
    else
      -- Well-fed creatures have babies, up to the variant's most.
      local fed={}
      for ent in pairs(H.live) do
        local q=ent.object:get_pos()
        if q and not ent._owner and not ent._baby and ent._food>70 and ent._water>70 and brickcraft.world_at(q)==w then fed[#fed+1]=ent end
      end
      next_birth[id]=next_birth[id] or now()+90
      if H.colony_tick then H.colony_tick(w,v) end
      if #fed>=2 and now()>next_birth[id] and H.creature_count(w,false)<(v.max or 16) then
        next_birth[id]=now()+rnd(80,140)
        local q=fed[math.random(#fed)].object:get_pos()
        if H.spawn_creature(v.creature,vector.offset(q,.3,.2,0),{baby=true}) then
          st.born=(st.born or 0)+1; H.save(w)
          H.tell(w,"A baby "..H.creatures[v.creature].label:lower().." was born!","#ffd6e8")
        end
      end
      -- Predators come by themselves now and then (not while testing).
      if st.wild~=false and not testing and not habitat_test and v.predators and #v.predators>0 then
        local wave=v.wave or {120,220}
        local k=H.pace_of and H.pace_of(st).mult or 1
        next_wave[id]=next_wave[id] or now()+wave[1]*k
        if now()>next_wave[id] then
          next_wave[id]=now()+rnd(wave[1],wave[2])*k
          H.spawn_predator(w,v.predators[math.random(#v.predators)])
        end
      end
    end
  end
end)

-- The habitat panel (/habitat): everything a player can do here, as buttons.
local function panel(p)
  local w,v=H.world_at(p:get_pos())
  local name=p:get_player_name()
  if not w then
    local fs="formspec_version[6]size[10,4.6]bgcolor[#142936;true]label[.6,.6;HABITATS]"..
      "textarea[.6,1;8.8,1.6;;;"..C.formspec_escape("This world isn't a habitat. Make it one (its animals, a giant statue, food and water):").."]"
    for i,id in ipairs(H.variant_list) do
      fs=fs.."button["..(.6+(i-1)*3.1)..",2.8;3,.7;make_"..id..";"..C.formspec_escape(H.variants[id].label).."]"
    end
    C.show_formspec(name,"brickcraft_habitat:panel",fs.."button_exit[.6,3.7;3,.6;close;Close]")
    return
  end
  local st=H.state(w)
  local fs="formspec_version[6]size[11,10.5]bgcolor[#142936;true]"..
    "label[.6,.6;"..C.formspec_escape(v.label:upper().." / KEEP THE "..v.plural:upper().." SAFE").."]"..
    "textarea[.6,1;9.8,1.5;;;"..C.formspec_escape(hud_text(w,v,p).."\n"..(v.tip or "")).."]"..
    "label[.6,2.9;Predators]"
  local function row(y,prefix,ids,labels)
    local out=""
    for i,id in ipairs(ids) do
      out=out.."button["..(.6+(i-1)*2.5)..","..y..";2.4,.7;"..prefix..id..";"..C.formspec_escape(labels(id)).."]"
    end
    return out
  end
  fs=fs..row(3.2,"pred_",v.predators or {},function(id) return H.predators[id].label end)..
    "label[.6,4.3;Disasters]"..row(4.6,"dis_",v.disasters or H.disaster_list,function(id) return H.disasters[id].label end)..
    "button[8.1,4.6;2.3,.7;dis_stop;Stop]"..
    "label[.6,5.7;Wear a skin]"..row(6.0,"skin_",v.skins or H.skin_list,function(id) return H.skins[id].label end)..
    "button[.6,7.3;3.2,.7;kit;Get food and water]"..
    "button[3.9,7.3;3.2,.7;wild;"..(st.wild==false and "Predators: off" or "Predators: on").."]"..
    "button[7.2,7.3;1.55,.7;skin_off;Own look]button[8.85,7.3;1.55,.7;rules;Rules]"..
    "button[.6,8.3;3.2,.7;reset;New "..C.formspec_escape(v.plural).."]"..
    "style[colony;bgcolor=#f5872c]button[3.9,8.3;3.2,.7;colony;My colony]"..
    "button_exit[7.2,8.3;3.2,.7;close;Back to building]"
  if v.cycle then fs=fs.."button[.6,9.3;6.5,.7;cycle_settings;Day / night settings]" end
  if v.id=="bunny" and H.word_story then
    fs=fs.."style[story;bgcolor=#f5872c]button[7.2,9.3;3.2,.7;story;이야기책]"
  end
  C.show_formspec(name,"brickcraft_habitat:panel",fs)
end
H.panel=panel
local function act(p,field)
  local name=p:get_player_name()
  local w,v=H.world_at(p:get_pos())
  local id=field:match("^make_(.+)$")
  if id and H.variants[id] then
    local here=brickcraft.world_at(p:get_pos())
    if here.id==0 then return "The Workshop can't be a habitat; make your own world first (/world)." end
    H.make_habitat(here,id)
    return here.name.." is now "..H.variants[id].label.."! The statue is going up; the "..H.variants[id].plural.." come next."
  end
  if not w then return end
  id=field:match("^pred_(.+)$")
  if id and H.predators[id] then H.spawn_predator(w,id); return end
  id=field:match("^dis_(.+)$")
  if id=="stop" then return H.stop_disaster(w) and nil or "No disaster is happening." end
  if id and H.disasters[id] then local ok,why=H.start_disaster(w,id); return not ok and why or nil end
  id=field:match("^skin_(.+)$")
  if id=="off" then H.set_skin(p,nil); return "Your own look is back." end
  if id and H.skins[id] then H.set_skin(p,id); return "You're "..H.skins[id].label.."!" end
  if field=="kit" then return "You got "..H.give_kit(p,v).."." end
  if field=="colony" then H.colony_panel(p); return nil,true end
  if field=="cycle_settings" and v.cycle then H.cycle_panel(p); return nil,true end
  if field=="story" and v.id=="bunny" and H.word_story then H.word_story.open(p); return nil,true end
  if field=="rules" or field=="help" then H.welcome(p); return nil,true end
  if field=="wild" then
    local st=H.state(w); st.wild=st.wild==false; H.save(w)
    return st.wild and "Predators will come by themselves." or "Predators only come when you call them."
  end
  if field=="reset" then
    for ent in pairs(H.live) do
      local q=ent.object:get_pos()
      if q and not ent._owner and brickcraft.world_at(q)==w then H.live[ent]=nil; ent.object:remove() end
    end
    local st=H.state(w); st.lost=0; st.born=0; H.save(w)
    return H.populate(w).." new "..v.plural.." hopped out."
  end
end
C.register_on_player_receive_fields(function(p,formname,fields)
  if formname~="brickcraft_habitat:panel" then return end
  for field in pairs(fields) do
    if field~="quit" and field~="close" then
      local msg,shown=act(p,field)
      if msg then C.chat_send_player(p:get_player_name(),msg) end
      if not shown and not field:find("^make_") then panel(p) end
      break
    end
  end
  return true
end)

local function need_habitat(name)
  local p=C.get_player_by_name(name)
  if not p then return end
  local w,v=H.world_at(p:get_pos())
  if not w then C.chat_send_player(name,"This world isn't a habitat. /habitat makes it one."); return end
  return p,w,v
end
C.register_chatcommand("habitat",{params="[set <"..table.concat(H.variant_list,"|").."> | kit | wild on|off | cycle | reset]",
  description="Habitat panel: predators, disasters, skins, food and water (Bunnyland)",
  func=function(name,param)
    local p=C.get_player_by_name(name)
    if not p then return end
    local cmd,arg=param:match("^(%S*)%s*(.-)%s*$")
    if cmd=="" then panel(p); return true end
    if cmd=="cycle" then
      local _,w,v=need_habitat(name)
      if not w then return true end
      if not v.cycle then return false,"This habitat has no day/night cycle." end
      H.cycle_panel(p); return true
    end
    if cmd=="set" then return true,act(p,"make_"..arg) or "No such habitat: "..arg end
    if cmd=="wild" then
      local _,w=need_habitat(name); if not w then return true end
      local st=H.state(w); st.wild=arg~="off"; H.save(w)
      return true,st.wild and "Predators will come by themselves." or "Predators only come when you call them."
    end
    return true,act(p,cmd) or ""
  end})
C.register_chatcommand("clearbricks",{description="Habitat: take away every brick in this habitat world (its owner only; not given back)",
  func=function(name)
    local p,w=need_habitat(name); if not w then return true end
    local who=brickcraft.playing_as(p) or name
    if w.owner~=who and not C.check_player_privs(name,{server=true}) then
      return true,"Only "..((brickcraft.styles[w.owner] or {}).label or w.owner).." can clear the bricks of "..w.name.."."
    end
    H.clear_bricks(w,function(n) C.chat_send_player(name,"Took away "..n.." bricks from "..w.name..".") end)
    return true,"Clearing every brick in "..w.name.."..."
  end})
C.register_chatcommand("disaster",{params="<flood|earthquake|asteroids|...|stop>",
  description="Habitat: start a disaster in this world (or stop it)",
  func=function(name,param)
    local _,w=need_habitat(name); if not w then return true end
    if param=="stop" then return true,H.stop_disaster(w) and "Stopped." or "No disaster is happening." end
    if not H.disasters[param] then return true,"Disasters: "..table.concat(H.disaster_list,", ")..", stop" end
    local ok,why=H.start_disaster(w,param)
    return true,ok and "" or why
  end})
C.register_chatcommand("predator",{params="<wolf|lion|eagle|...>",description="Habitat: call a predator into this world",
  func=function(name,param)
    local _,w=need_habitat(name); if not w then return true end
    if not H.predators[param] then return true,"Predators: "..table.concat(H.predator_list,", ") end
    H.spawn_predator(w,param); return true
  end})
C.register_chatcommand("skin",{params="[<skin>|off]",description="Wear a skin (bunny looks), or your own look again",
  func=function(name,param)
    local p=C.get_player_by_name(name); if not p then return end
    if param=="off" then H.set_skin(p,nil); return true,"Your own look is back." end
    if not H.skins[param] then return true,"Skins: "..table.concat(H.skin_list,", ")..", off" end
    H.set_skin(p,param); return true,"You're "..H.skins[param].label.."!"
  end})

dofile(MP.."/predators.lua")(H)
dofile(MP.."/disasters.lua")(H)
dofile(MP.."/colony.lua")(H)
dofile(MP.."/daynight.lua")(H)
dofile(MP.."/cats.lua")(H)
dofile(MP.."/welcome.lua")(H)
dofile(MP.."/meadow.lua")(H)
dofile(MP.."/ai.lua")(H)
for _,f in ipairs({"bunny"}) do dofile(MP.."/variants/"..f..".lua")(H) end
dofile(MP.."/word_story.lua")(H)
dofile(MP.."/kingdom.lua")(H)

for _,row in ipairs({
  {"/habitat","Habitat panel (in Bunnyland): predators, disasters, skins, food and water"},
  {"/habitat help","Bunnyland's rules and settings (predators on/off, Calm / Normal / Wild)"},
  {"/colony, /colony start","Your own bunny colony: start with 5, grow it with hutches, food, water; buy with clovers"},
  {"Right click your bunny, /colony call","It (or all of yours near) follows you; /colony stay: they stop, and that's their home"},
  {"/disaster flood|earthquake|asteroids","Start a disaster in this habitat (/disaster stop ends it)"},
  {"/predator wolf|lion|eagle","Call a predator; punch it (or use war weapons) to chase it away"},
  {"/skin snow|cocoa|gray|rose|off","Wear a bunny look"},
  {"Keep bunnies safe","2-high fences stop wolves and lions; roofs hide from eagles and asteroids; high ground beats floods"},
}) do brickcraft.help[#brickcraft.help+1]=row end

-- Worlds named like a variant (bunnyland) become that habitat: checked at the start and
-- every few seconds, so a world made later with that name becomes one too.
function H.bind_names()
  if testing and not habitat_test then return end
  for _,w in ipairs(brickcraft.worlds()) do
    if w.built and not w.habitat and w.id~=0 then
      local lname=w.name:lower():gsub("%s","")
      for _,id in ipairs(H.variant_list) do
        for _,m in ipairs(H.variants[id].match_names or {}) do
          if lname==m then
            H.make_habitat(w,id)
            C.log("action","BrickCraft habitat: "..w.name.." is "..H.variants[id].label)
          end
        end
      end
    end
  end
end
C.after(0,H.bind_names)
-- Flood water left by a shutdown mid-flood drains when its block loads.
C.register_lbm({name="brickcraft_habitat:drain",label="Drain flood water left over",nodenames={"brickcraft_habitat:flood"},
  run_at_every_load=true,action=function(pos)
    local w=brickcraft.world_at(pos)
    local ctx=w and H.active[w.id]
    if not (ctx and (ctx.def.id=="flood" or ctx.def.id=="tsunami")) then C.remove_node(pos) end
  end})

brickcraft.habitat=H
