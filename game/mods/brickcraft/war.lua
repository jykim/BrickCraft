-- War mode: a game of cannons, swords, kicks and shoves for players who turn it on (/war,
-- or I > War mode), against each other and against Brick Knight targets. Nobody can be hit
-- unless they are in war too, and builds are never damaged. Hearts are this mode's own (the
-- engine's damage stays off): out of hearts is a knockout, back to your start spot with
-- full hearts and a few seconds' shield.
-- War swaps the hotbar for the war kit. The bricks wait in the war_stash list (saved with
-- the player, and what save_bricks saves meanwhile) and come back exactly when war ends;
-- cannons and knights put up in war go away with it.
local C=core
local MAX_HP=10 -- in half hearts: 5 hearts
local SHIELD=3 -- seconds nobody can hit you after a knockout or joining
local KIT={"brickcraft:sword","brickcraft:cannon","brickcraft:boot","brickcraft:knight"}
local KIT_ITEM={}
for _,item in ipairs(KIT) do KIT_ITEM[item]=true end
-- Damage in half hearts; how hard it throws you (along the hit, and up), in nodes/s.
local MOVES={
  sword={dmg=2,push=7,up=4,cool=.4},
  kick={dmg=1,push=12,up=7,cool=.6},
  push={dmg=0,push=10,up=3.5,cool=.5},
  cannon={dmg=3,push=12,up=7},
}
local CANNONS,KNIGHTS=3,4 -- each player's most at once
local BALL_SPEED,BALL_GRAVITY,BLAST=18,9.81,1.6

local war={} -- name -> {hp, kos, shield (time), last={move->time}, hud={}}
local things={} -- cannons and knights up now (luaentities)
local function now() return C.get_us_time()/1e6 end
local function label(p)
  local st=brickcraft.styles[brickcraft.playing_as(p) or ""]
  return st and st.label or p:get_player_name()
end
local function tell_war(msg)
  for name in pairs(war) do C.chat_send_player(name,C.colorize("#ff9a76",msg)) end
end

local function update_hud(player)
  local s=war[player:get_player_name()]
  if not s then return end
  local text="WAR   1 Sword   2 Cannon   3 Boot (right click: shove)   4 Knight      Knockouts: "..s.kos.."      /war: back to building"
  if s.hud.hearts then
    player:hud_change(s.hud.hearts,"number",s.hp)
    player:hud_change(s.hud.text,"text",text)
    return
  end
  s.hud.hearts=player:hud_add({type="statbar",position={x=.5,y=1},offset={x=-60,y=-150},
    text="heart.png",text2="heart_gone.png",number=s.hp,item=MAX_HP,direction=0,size={x=24,y=24}})
  s.hud.text=player:hud_add({type="text",position={x=.5,y=1},offset={x=0,y=-166},
    text=text,number=0xff9a76,alignment={x=0,y=0},scale={x=100,y=20}})
end

-- A red flash on whoever was hit.
local function flash(obj,tex)
  obj:set_properties({textures={tex.."^[colorize:#ff3020:110"}})
  C.after(.2,function() if obj:get_pos() then obj:set_properties({textures={tex}}) end end)
end

local function knockout(player,by)
  local name=player:get_player_name()
  local s=war[name]
  s.hp,s.shield=MAX_HP,now()+SHIELD
  player:set_pos(brickcraft.home_pos(player))
  if by and by~=player and war[by:get_player_name()] then
    local b=war[by:get_player_name()]
    b.kos=b.kos+1; update_hud(by)
    tell_war(label(by).." knocked out "..label(player).."!")
  else
    tell_war(label(player).." got knocked out!")
  end
  update_hud(player)
end

-- target takes a move from attacker (a player, or nil for a stray cannonball); dir is the
-- way it flies (attacker to target when nil). Returns true when it landed.
local function hit(target,attacker,move,dir)
  local m=MOVES[move]
  local tp=target:get_pos()
  if not tp then return false end
  if not dir and attacker then dir=vector.subtract(tp,attacker:get_pos()) end
  dir=dir and {x=dir.x,y=0,z=dir.z} or {x=0,y=0,z=0}
  dir=vector.length(dir)>0 and vector.normalize(dir) or dir
  local v={x=dir.x*m.push,y=m.up,z=dir.z*m.push}
  if target:is_player() then
    local s=war[target:get_player_name()]
    if not s then
      if attacker and attacker:is_player() then
        C.chat_send_player(attacker:get_player_name(),label(target).." isn't playing war. /war asks them in.")
      end
      return false
    end
    if s.shield>now() then return false end
    target:add_velocity(v)
    if m.dmg>0 then
      flash(target,brickcraft.get_style(target).tex)
      s.hp=s.hp-m.dmg
      if s.hp<=0 then knockout(target,attacker) else update_hud(target) end
    end
    return true
  end
  local ent=target:get_luaentity()
  if ent and ent.name=="brickcraft:knight" then return ent:_hit(attacker,m,v) end
  return false
end

-- Sword strikes, boot kicks and shoves; each has its own cooldown.
local function move_by(player,target,move)
  local s=war[player:get_player_name()]
  if not s then return false end
  local t=now()
  if (s.last[move] or 0)+MOVES[move].cool>t then return false end
  s.last[move]=t
  return hit(target,player,move)
end
local function keep(stack) return stack end
C.register_tool("brickcraft:sword",{
  description="Brick Sword (war)\nLeft click: strike (1 heart)\nRight click a player: shove",
  inventory_image="brickcraft_sword.png",wield_image="brickcraft_sword.png",wield_scale={x=1.5,y=1.5,z=1},range=3.5,
  groups={not_in_creative_inventory=1},
  on_use=function(stack,user,pointed)
    if pointed.type=="object" then move_by(user,pointed.ref,"sword") end
    return stack
  end,
  on_drop=keep,
})
C.register_tool("brickcraft:boot",{
  description="Kicking Boot (war)\nLeft click: kick (half a heart, sends them flying)\nRight click a player: shove",
  inventory_image="brickcraft_boot.png",wield_image="brickcraft_boot.png",range=2.8,
  groups={not_in_creative_inventory=1},
  on_use=function(stack,user,pointed)
    if pointed.type=="object" then move_by(user,pointed.ref,"kick") end
    return stack
  end,
  on_drop=keep,
})
-- Right clicking someone holding anything from the kit shoves them.
C.register_on_rightclickplayer(function(target,clicker)
  if KIT_ITEM[clicker:get_wielded_item():get_name()] then move_by(clicker,target,"push") end
end)

local function count_owned(kind,name)
  local n=0
  for ent in pairs(things) do if ent.name==kind and ent._owner==name then n=n+1 end end
  return n
end
-- Cannons and knights stand on the face you right click, facing the way you look.
local function put_up(kind,most,stack,placer,pointed)
  if pointed.type~="node" or not placer:is_player() then return stack end
  local name=placer:get_player_name()
  if not war[name] then return stack end
  if count_owned(kind,name)>=most then
    C.chat_send_player(name,"You have "..most.." up already. Left click one holding this to take it back.")
    return stack
  end
  local def=C.registered_nodes[C.get_node(pointed.under).name]
  local pos=(def and def.buildable_to) and pointed.under or pointed.above
  local obj=C.add_entity({x=pos.x,y=pos.y-.5,z=pos.z},kind)
  if obj then
    obj:set_yaw(placer:get_look_horizontal())
    local ent=obj:get_luaentity()
    ent._owner,ent._home=name,obj:get_pos()
  end
  return stack
end
-- Left click your own cannon or knight holding its item to take it back.
local function take_back(kind)
  return function(stack,user,pointed)
    local ent=pointed.type=="object" and pointed.ref:get_luaentity()
    if ent and ent.name==kind and ent._owner==user:get_player_name() then ent.object:remove() end
    return stack
  end
end

-- Cannonballs: no engine physics; each step checks the stretch it flew for something in
-- the way. They burst on anything solid or anyone, hitting everyone within BLAST.
local function burst(pos,shooter,ball_dir,direct)
  C.add_particlespawner({amount=18,time=.1,minpos=vector.offset(pos,-.2,-.2,-.2),maxpos=vector.offset(pos,.2,.2,.2),
    minvel={x=-2,y=0,z=-2},maxvel={x=2,y=2.5,z=2},minexptime=.4,maxexptime=.9,minsize=3,maxsize=6,
    texture="brickcraft_smoke.png"})
  local shooter_obj=shooter and C.get_player_by_name(shooter)
  local landed=false
  for _,obj in ipairs(C.get_objects_inside_radius(pos,BLAST)) do
    if obj~=shooter_obj then
      local ent=obj:get_luaentity()
      if obj:is_player() or (ent and ent.name=="brickcraft:knight") then
        local dir=obj==direct and ball_dir or vector.subtract(obj:get_pos(),pos)
        if hit(obj,shooter_obj,"cannon",dir) then landed=true end
      end
    end
  end
  return landed
end
C.register_entity("brickcraft:cannonball",{
  initial_properties={visual="sprite",textures={"brickcraft_cannonball.png"},visual_size={x=.35,y=.35},
    physical=false,pointable=false,static_save=false},
  on_step=function(self,dtime)
    local pos=self.object:get_pos()
    self._age=(self._age or 0)+dtime
    local prev=self._prev or pos
    self._prev=pos
    if self._age>6 or pos.y< -10 then self.object:remove(); return end
    local vel=self.object:get_velocity()
    for pt in C.raycast(prev,pos,true,false) do
      local stop
      if pt.type=="object" then
        local ref,ent=pt.ref,pt.ref:get_luaentity()
        local shooter=ref:is_player() and ref:get_player_name()==self._shooter
        if not shooter and (ref:is_player() or (ent and ent.name=="brickcraft:knight")) then stop=ref:get_pos() end
      elseif pt.type=="node" then
        local def=C.registered_nodes[C.get_node(pt.under).name]
        if def and def.walkable~=false then stop=pt.intersection_point end
      end
      if stop then
        burst(pt.intersection_point or stop,self._shooter,vel,pt.ref)
        self.object:remove()
        return
      end
    end
  end,
})
-- Fires a cannonball from pos with velocity vel; shooter (a player name) is never hit by it.
local function fire(pos,vel,shooter)
  local obj=C.add_entity(pos,"brickcraft:cannonball")
  if not obj then return end
  obj:set_velocity(vel); obj:set_acceleration({x=0,y=-BALL_GRAVITY,z=0})
  obj:get_luaentity()._shooter=shooter
  C.add_particlespawner({amount=10,time=.1,minpos=pos,maxpos=pos,minvel={x=-1,y=.5,z=-1},maxvel={x=1,y=1.5,z=1},
    minexptime=.5,maxexptime=1,minsize=4,maxsize=7,texture="brickcraft_smoke.png"})
  return obj
end

-- A cannon on wheels. Right click it in war: it turns the way you look and fires where you
-- aim (up to steep lobs; never down into the ground).
C.register_entity("brickcraft:cannon",{
  initial_properties={visual="mesh",mesh="brickcraft_cannon.obj",
    textures={"brickcraft_brown.png","brickcraft_cannon_metal.png"},visual_size={x=10,y=10},
    backface_culling=false,physical=false,pointable=true,static_save=false,
    collisionbox={-.35,0,-.4,.35,.55,.55},selectionbox={-.35,0,-.4,.35,.55,.55,rotate=true}},
  on_activate=function(self)
    self.object:set_armor_groups({immortal=1})
    things[self]=true
  end,
  on_deactivate=function(self) things[self]=nil end,
  on_punch=function() return true end,
  on_rightclick=function(self,clicker)
    local name=clicker:get_player_name()
    if not war[name] then C.chat_send_player(name,"Cannons are for war mode: type /war to play."); return end
    local t=now()
    if (self._fired or 0)+1.2>t then return end
    self._fired=t
    local yaw=clicker:get_look_horizontal()
    self.object:set_yaw(yaw)
    local h={x=-math.sin(yaw),y=0,z=math.cos(yaw)}
    local e=math.max(-.05,math.min(1.1,math.asin(clicker:get_look_dir().y)))
    local muzzle=vector.add(self.object:get_pos(),{x=h.x*.6,y=.38,z=h.z*.6})
    fire(muzzle,{x=h.x*math.cos(e)*BALL_SPEED,y=math.sin(e)*BALL_SPEED,z=h.z*math.cos(e)*BALL_SPEED},name)
  end,
})
C.register_tool("brickcraft:cannon",{
  description="Cannon (war)\nRight click the ground: set up a cannon (3 at most)\nRight click a cannon: aim and fire\nLeft click your cannon: take it back",
  inventory_image="brickcraft_cannon.png",wield_image="brickcraft_cannon.png",range=7,
  groups={not_in_creative_inventory=1},
  on_place=function(stack,placer,pointed) return put_up("brickcraft:cannon",CANNONS,stack,placer,pointed) end,
  on_use=take_back("brickcraft:cannon"),
  on_drop=keep,
})

-- Brick Knight: a target to practice on. Knocked out, it falls over and gets back up at
-- its spot with full hearts.
local KNIGHT_TEX="brickcraft_person_knight.png"
local function knight_tag(self)
  self.object:set_properties({nametag="Brick Knight  "..math.max(0,self._hp).."/"..MAX_HP})
end
C.register_entity("brickcraft:knight",{
  initial_properties={visual="mesh",mesh="brickcraft_person_short.obj",textures={KNIGHT_TEX},
    visual_size={x=10,y=10},physical=true,collide_with_objects=false,pointable=true,static_save=false,
    collisionbox={-.3,0,-.3,.3,1.75,.3},selectionbox={-.3,0,-.3,.3,1.75,.3},stepheight=.6,
    nametag_color="#d8dde6",nametag_bgcolor="#14293699"},
  on_activate=function(self)
    self.object:set_armor_groups({immortal=1})
    self.object:set_acceleration({x=0,y=-2*9.81,z=0})
    self._hp=MAX_HP
    knight_tag(self)
    things[self]=true
  end,
  on_deactivate=function(self) things[self]=nil end,
  on_punch=function() return true end,
  on_rightclick=function(self,clicker)
    if KIT_ITEM[clicker:get_wielded_item():get_name()] then move_by(clicker,self.object,"push") end
  end,
  _hit=function(self,attacker,m,v)
    if self._down then return false end
    self.object:add_velocity(v)
    if m.dmg==0 then return true end
    flash(self.object,KNIGHT_TEX)
    self._hp=self._hp-m.dmg
    if self._hp<=0 then
      -- Falls on its back, away from the hit.
      self._down=now()+3
      self.object:set_rotation({x=-math.pi/2,y=self.object:get_yaw(),z=0})
      local by=attacker and attacker:is_player() and war[attacker:get_player_name()]
      if by then
        by.kos=by.kos+1; update_hud(attacker)
        C.chat_send_player(attacker:get_player_name(),"You knocked out the Brick Knight!")
      end
    end
    knight_tag(self)
    return true
  end,
  on_step=function(self,dtime,moveresult)
    local v=self.object:get_velocity()
    if moveresult and moveresult.touching_ground then
      local f=math.max(0,1-dtime*6)
      self.object:set_velocity({x=v.x*f,y=v.y,z=v.z*f})
    end
    local p=self.object:get_pos()
    if (self._down and now()>self._down) or p.y< -8 then
      self._down,self._hp=nil,MAX_HP
      self.object:set_rotation({x=0,y=self.object:get_yaw(),z=0})
      self.object:set_velocity({x=0,y=0,z=0})
      if self._home then self.object:set_pos(self._home) end
      knight_tag(self)
    end
  end,
})
C.register_tool("brickcraft:knight",{
  description="Brick Knight (war)\nRight click the ground: put up a target (4 at most)\nLeft click your knight: take it back",
  inventory_image="brickcraft_knight.png",wield_image="brickcraft_knight.png",range=7,
  groups={not_in_creative_inventory=1},
  on_place=function(stack,placer,pointed) return put_up("brickcraft:knight",KNIGHTS,stack,placer,pointed) end,
  on_use=take_back("brickcraft:knight"),
  on_drop=keep,
})

local function remove_things(name)
  for ent in pairs(things) do
    if ent._owner==name then things[ent]=nil; ent.object:remove() end
  end
end
-- Bricks back from the stash: whatever the kit slots hold goes.
local function unstash(player)
  local inv=player:get_inventory()
  if inv:get_size("war_stash")==0 then return end
  inv:set_list("main",inv:get_list("war_stash"))
  inv:set_size("war_stash",0)
end

local function start(player)
  local name=player:get_player_name()
  if war[name] then return false end
  local inv=player:get_inventory()
  inv:set_size("war_stash",inv:get_size("main"))
  inv:set_list("war_stash",inv:get_list("main"))
  inv:set_list("main",{})
  for i,item in ipairs(KIT) do inv:set_stack("main",i,item) end
  brickcraft.forget(name) -- an undo would put bricks in the kit, lost when war ends
  war[name]={hp=MAX_HP,kos=0,shield=now()+SHIELD,last={},hud={}}
  update_hud(player)
  brickcraft.refresh_inventory(player)
  tell_war(label(player).." is in the war! ("..(function()
    local n=0 for _ in pairs(war) do n=n+1 end return n end)().." playing)")
  return true
end
local function stop(player)
  local name=player:get_player_name()
  local s=war[name]
  if not s then unstash(player); return false end
  for _,id in pairs(s.hud) do player:hud_remove(id) end
  war[name]=nil
  remove_things(name)
  unstash(player)
  brickcraft.refresh_inventory(player)
  C.chat_send_player(name,"War's over for you: your bricks are back.")
  tell_war(label(player).." left the war.")
  return true
end

C.register_chatcommand("war",{description="Start or stop war mode: cannons, swords, kicks and shoves",
  func=function(name)
    local p=C.get_player_by_name(name)
    if not p then return false,"Player is not connected." end
    if war[name] then stop(p); return true end
    start(p)
    return true,"War mode! 1 Sword  2 Cannon  3 Boot  4 Brick Knight. Only players in war can be hit; builds are safe. /war again to stop."
  end})
C.register_on_player_receive_fields(function(player,formname,fields)
  if formname=="" and fields.war then
    if war[player:get_player_name()] then stop(player) else start(player) end
    return true
  end
end)
-- A connection that left (or a server stopped) mid-war gets its bricks back.
C.register_on_joinplayer(function(player) unstash(player) end)
C.register_on_leaveplayer(function(player)
  local name=player:get_player_name()
  if war[name] then stop(player) end
end)

-- War Lab (experimental): a world made once for everyone to try war mode in, listed in
-- "Which world?". Coral cover walls on the baseplate east of the start spots, and a row of
-- Brick Knights that stand up whenever someone is there (knights aren't saved). Test
-- worlds skip it (but the war check).
local LAB_WALLS={{x=9,z0=-9,z1=-5},{x=9,z0=-1,z1=3},{x=13,z0=-6,z1=0}}
local LAB_KNIGHTS={{x=17,z=-8},{x=17,z=-4},{x=17,z=0},{x=19,z=-6},{x=19,z=-2}}
local function lab() for _,w in ipairs(brickcraft.worlds()) do if w.lab then return w end end end
local function build_lab(w)
  for _,wall in ipairs(LAB_WALLS) do
    for z=wall.z0,wall.z1 do for y=0,1 do
      local pos={x=w.x+wall.x,y=y,z=w.z+z}
      if C.get_node(pos).name=="air" then C.set_node(pos,{name="brickcraft:coral"}) end
    end end
  end
  w.lab_built=true; brickcraft.save_worlds()
  C.log("action","BrickCraft War Lab built at "..w.x..","..w.z)
end
C.after(0,function()
  if brickcraft.testing and not C.settings:get_bool("brickcraft_war_test",false) then return end
  local w=lab()
  if w then
    if w.built and not w.lab_built then C.emerge_area({x=w.x,y=0,z=w.z},{x=w.x+20,y=2,z=w.z+20},function(_,_,r) if r==0 then build_lab(w) end end) end
    return
  end
  w=brickcraft.make_world("War Lab (experimental)","BrickCraft",build_lab)
  C.log("action","BrickCraft War Lab "..(w and "being made at "..w.x..","..w.z or "has no room"))
  if w then w.lab=true; brickcraft.save_worlds() end
end)
local lab_timer,welcomed=0,{}
C.register_globalstep(function(dt)
  lab_timer=lab_timer+dt
  if lab_timer<2 then return end
  lab_timer=0
  local w=lab()
  if not w or not w.lab_built then return end
  local here=false
  for _,p in ipairs(C.get_connected_players()) do
    local name=p:get_player_name()
    if brickcraft.world_at(p:get_pos())==w then
      here=true
      if not welcomed[name] and not war[name] then
        C.chat_send_player(name,C.colorize("#ff9a76","War Lab (experimental): type /war for cannons, swords and kicks. The Brick Knights are targets."))
      end
      welcomed[name]=true
    else welcomed[name]=nil end
  end
  if not here then return end
  local up=0
  for ent in pairs(things) do if ent._lab then up=up+1 end end
  if up>0 then return end
  for _,k in ipairs(LAB_KNIGHTS) do
    local obj=C.add_entity({x=w.x+k.x,y=-.5,z=w.z+k.z},"brickcraft:knight")
    if obj then
      obj:set_yaw(math.pi/2) -- facing west, toward the walls
      local ent=obj:get_luaentity()
      ent._lab,ent._home=true,obj:get_pos()
    end
  end
end)

brickcraft.war={lab=lab,start=start,stop=stop,hit=hit,fire=fire,max_hp=MAX_HP,
  on=function(player) return war[player:get_player_name()] end}
