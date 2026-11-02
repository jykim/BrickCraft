-- War mode: a game of cannons, swords, kicks and shoves for players who turn it on (/war,
-- or I > War mode), against each other and against the Red Army (/battle): Red Knights led
-- by a Red Commander, fought alongside your own blue Brick Knights. Nobody can be hit
-- unless they are in war too. Cannonballs break bricks (ball_on_node). Hearts are this mode's own (the
-- engine's damage stays off): out of hearts is a knockout, back to your start spot with
-- full hearts and a few seconds' shield.
-- War swaps the hotbar for the war kit. The bricks wait in the war_stash list (saved with
-- the player, and what save_bricks saves meanwhile) and come back exactly when war ends;
-- cannons and knights put up in war go away with it. Cannons fire cannonballs you carry
-- (ammo): piles of them turn up around players in war, and walking over one picks it up.
-- Sides: players and their blue knights are blue (though players can still fight each
-- other), the Red Army is red, practice knights (War Lab) and stray balls are on no side.
local C=core
local MAX_HP=10 -- in half hearts: 5 hearts
local SHIELD=3 -- seconds nobody can hit you after a knockout or joining
local LIVES=3 -- knockouts a player can take; the last one ends their war
local LOW=3 -- half hearts at or under which a player is hurt: slow and pale
local HEAL_AFTER=10 -- unhit this long, a half heart back every 3 seconds
local KIT={"brickcraft:sword","brickcraft:cannon","brickcraft:boot","brickcraft:knight","brickcraft:bow"}
local KIT_ITEM={}
for _,item in ipairs(KIT) do KIT_ITEM[item]=true end
-- Damage in half hearts; how hard it throws you (along the hit, and up), in nodes/s.
local MOVES={
  sword={dmg=2,push=7,up=4,cool=.4},
  kick={dmg=1,push=12,up=7,cool=.6},
  push={dmg=0,push=10,up=3.5,cool=.5},
  cannon={dmg=3,push=12,up=7},
  knight={dmg=1,push=6,up=3,cool=1.1}, -- a knight's sword, red or blue
  arrow={dmg=2,push=3,up=1.5,cool=.45},
}
local CANNONS,KNIGHTS=3,4 -- each player's most at once
local BALL_SPEED,BALL_GRAVITY,BLAST=18,9.81,1.6
local AMMO_START,AMMO_MAX,AMMO_PILE=6,30,3
-- The Siege Castle's balance (seconds between shots or steps; tools/sim_siege.py tries
-- others): red cannons, siege tower builders, castle archers, knights a side.
local TUNE={red_cannon_every=12,build_every=12,archer_every=2,siege_per_side=26}

local war={} -- name -> {hp, lives, kos, ammo, shield (time), hurt (time), look, last={move->time}, hud={}}
local things={} -- cannons and knights up now (luaentities)
local piles={} -- cannonball piles lying about (luaentities)
local function now() return C.get_us_time()/1e6 end
local function label(p)
  if not p:is_player() then local ent=p:get_luaentity(); return ent and ent._name or "Someone" end
  local st=brickcraft.styles[brickcraft.playing_as(p) or ""]
  return st and st.label or p:get_player_name()
end
-- Teams: everyone starts blue, all on one side against the Red Army; /team green puts a
-- player's knights and AI builder against the blue players and theirs (and theirs
-- against them). Players can hit players on any team, as before.
local TEAMS={blue={tag="#8fd0ff"},green={tag="#7be08a"}}
local function team_of(name) return war[name] and war[name].team or "blue" end
local function side_of(obj)
  if not obj then return nil end
  if obj:is_player() then return team_of(obj:get_player_name()) end
  local ent=obj:get_luaentity()
  return ent and ent._team
end
local function tell_war(msg)
  for name in pairs(war) do C.chat_send_player(name,C.colorize("#ff9a76",msg)) end
end

-- How hurt a player looks and moves: a bit slower under half hearts; at LOW and under,
-- slower still, lower jumps and a pale, bruised look. Out of war: themselves again.
local function body_tex(player)
  local s=war[player:get_player_name()]
  local tex=brickcraft.get_style(player).tex
  return s and s.hp<=LOW and tex.."^[colorize:#5a4a60:90" or tex
end
local function condition(player)
  local s=war[player:get_player_name()]
  -- The nametag in the team's color, so everyone sees who's on which side.
  player:set_nametag_attributes({color=s and TEAMS[s.team].tag or brickcraft.get_style(player).tag})
  local hp=s and s.hp or MAX_HP
  player:set_physics_override({speed=hp<=LOW and .6 or hp<=MAX_HP/2 and .85 or 1,jump=hp<=LOW and .85 or 1})
  local tex=body_tex(player)
  if not s or s.look~=tex then
    player:set_properties({textures={tex}})
    if s then s.look=tex end
  end
end
local function update_hud(player)
  local s=war[player:get_player_name()]
  if not s then return end
  condition(player)
  local text="WAR ("..s.team.." team)   1 Sword   2 Cannon (left click: fire)   3 Boot   4 Knight   5 Bow      Lives: "..s.lives.."      Cannonballs: "..s.ammo..
    "      Knockouts: "..s.kos.."      /battle: Red Army   /war: stop"
  if s.hud.hearts then
    player:hud_change(s.hud.hearts,"number",s.hp)
    player:hud_change(s.hud.ammo,"number",s.ammo*2)
    player:hud_change(s.hud.text,"text",text)
    return
  end
  -- Cannonballs as a row of balls above the text (a statbar counts halves: 2 per ball).
  s.hud.ammo=player:hud_add({type="statbar",position={x=.5,y=1},offset={x=-AMMO_MAX*8,y=-200},
    text="brickcraft_cannonball.png",text2="brickcraft_cannonball.png^[opacity:50",number=s.ammo*2,item=AMMO_MAX*2,
    direction=0,size={x=16,y=16}})
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

local stop -- (below) a player's war ends
local function knockout(player,by)
  local name=player:get_player_name()
  local s=war[name]
  s.hp,s.shield,s.lives=MAX_HP,now()+SHIELD,s.lives-1
  player:set_pos(brickcraft.home_pos(player))
  if by and by~=player and by:is_player() and war[by:get_player_name()] then
    local b=war[by:get_player_name()]
    b.kos=b.kos+1; update_hud(by)
    tell_war(label(by).." knocked out "..label(player).."!")
  elseif by and by:get_pos() and not by:is_player() then
    tell_war("The "..label(by).." knocked out "..label(player).."!")
  else
    tell_war(label(player).." got knocked out!")
  end
  if s.lives<=0 then
    tell_war(label(player).." is out of lives!")
    stop(player)
    return
  end
  C.chat_send_player(name,C.colorize("#ff9a76","Knocked out! "..s.lives.." "..(s.lives==1 and "life" or "lives").." left."))
  update_hud(player)
end

-- target takes a move from attacker (a player or knight, or nil for a stray cannonball);
-- dir is the way it flies (attacker to target when nil); side is the attacker's (a
-- cannonball's attacker may be gone). Nobody hurts their own side (a player's is their
-- team), but players can always fight players. Returns true when it landed.
local function hit(target,attacker,move,dir,side)
  local m=MOVES[move]
  local tp=target:get_pos()
  if not tp then return false end
  if attacker and not attacker:get_pos() then attacker=nil end
  side=side or side_of(attacker)
  if side and side==side_of(target) and not (target:is_player() and attacker and attacker:is_player()) then
    return false
  end
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
      s.hp,s.hurt=s.hp-m.dmg,now()
      if s.hp<=0 then knockout(target,attacker) else update_hud(target); flash(target,body_tex(target)) end
    end
    return true
  end
  local ent=target:get_luaentity()
  if ent and ent._hit then return ent:_hit(attacker,m,v) end
  return false
end
-- Players, knights and anything else that can take a hit (the siege's cannons).
local function is_target(obj)
  if obj:is_player() then return true end
  local ent=obj:get_luaentity()
  return ent and ent._hit~=nil
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
C.register_tool(":brickcraft:sword",{
  description="Brick Sword (war)\nLeft click: strike (1 heart)\nRight click a player: shove",
  inventory_image="brickcraft_sword.png",wield_image="brickcraft_sword.png",wield_scale={x=1.5,y=1.5,z=1},range=3.5,
  groups={not_in_creative_inventory=1},
  on_use=function(stack,user,pointed)
    if pointed.type=="object" then move_by(user,pointed.ref,"sword") end
    return stack
  end,
  on_drop=keep,
})
C.register_tool(":brickcraft:boot",{
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
-- Cannonballs break things within 1.5 of where they burst on a node, a crack first and
-- the next hit knocks it out: anyone's cannonballs break bricks players put up (a whole
-- piece at once; hills and trees stay), only the Red Army's crack the Siege Castle (its
-- gate only from right on it, within 1), and anyone else's knock siege towers apart (at once).
local stone="brickcraft_baseplate.png^[colorize:#a9adb5:210"
local CRACKS={["brickcraft:castle_wall"]="brickcraft:castle_wall_cracked",["brickcraft:castle_gate"]="brickcraft:castle_gate_cracked",
  ["brickcraft:castle_wall_cracked"]="air",["brickcraft:castle_gate_cracked"]="air"}
for _,n in ipairs({{"castle_wall","Castle Wall",stone},{"castle_wall_cracked","Cracked Castle Wall",stone.."^[colorize:#3c3634:120"},
  {"castle_gate","Castle Gate","brickcraft_brown.png^[colorize:#4a2c18:90"},{"castle_gate_cracked","Cracked Castle Gate","brickcraft_brown.png^[colorize:#24140a:150"},
  {"siege_tower","Siege Tower",{"brickcraft_trunk_top.png","brickcraft_trunk_top.png","brickcraft_trunk.png"}}}) do
  C.register_node(":brickcraft:"..n[1],{description=n[2],tiles=type(n[3])=="table" and n[3] or {n[3]},
    groups={not_in_creative_inventory=1},diggable=false,is_ground_content=false})
end
local cracked={} -- bricks cracked once (by position; forgotten on restart)
local function break_brick(pos,node)
  if C.get_item_group(node.name,"brick_tail")==1 then
    pos=vector.subtract(pos,C.facedir_to_dir(node.param2%4))
    node=C.get_node(pos)
  end
  if C.get_item_group(node.name,"brick")~=1 or C.get_item_group(node.name,"scenery")==1 then return end
  local key=C.pos_to_string(pos)
  if not cracked[key] then cracked[key]=true; return end
  cracked[key]=nil
  C.remove_node(pos) -- a long piece's tail goes with it
  C.add_particlespawner({amount=8,time=.1,minpos=vector.offset(pos,-.4,-.4,-.4),maxpos=vector.offset(pos,.4,.4,.4),
    minvel={x=-2,y=1,z=-2},maxvel={x=2,y=3,z=2},minacc={x=0,y=-9,z=0},maxacc={x=0,y=-9,z=0},
    minexptime=.5,maxexptime=1,minsize=2,maxsize=4,texture="brickcraft_"..(node.name:match("^brickcraft:(%a+)") or "cream")..".png"})
end
local function ball_on_node(pt,side)
  for x=math.floor(pt.x-1),math.ceil(pt.x+1) do for y=math.floor(pt.y-1),math.ceil(pt.y+1) do for z=math.floor(pt.z-1),math.ceil(pt.z+1) do
    local pos={x=x,y=y,z=z}
    if vector.distance(pos,pt)<=1.5 then
      local node=C.get_node(pos)
      local gate=node.name:find("^brickcraft:castle_gate")
      local to=side=="red" and (not gate or vector.distance(pos,pt)<=1) and CRACKS[node.name] or
        side~="red" and node.name=="brickcraft:siege_tower" and "air"
      if to then C.swap_node(pos,{name=to}) else break_brick(pos,node) end
    end
  end end end
end
local function burst(pos,shooter,ball_dir,direct,side,from)
  C.add_particlespawner({amount=18,time=.1,minpos=vector.offset(pos,-.2,-.2,-.2),maxpos=vector.offset(pos,.2,.2,.2),
    minvel={x=-2,y=0,z=-2},maxvel={x=2,y=2.5,z=2},minexptime=.4,maxexptime=.9,minsize=3,maxsize=6,
    texture="brickcraft_smoke.png"})
  local shooter_obj=shooter and C.get_player_by_name(shooter) or from
  local landed=false
  for _,obj in ipairs(C.get_objects_inside_radius(pos,BLAST)) do
    if obj~=shooter_obj and is_target(obj) then
      local dir=obj==direct and ball_dir or vector.subtract(obj:get_pos(),pos)
      if hit(obj,shooter_obj,"cannon",dir,side) then landed=true end
    end
  end
  return landed
end
C.register_entity(":brickcraft:cannonball",{
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
        local own=(ref:is_player() and ref:get_player_name()==self._shooter) or ref==self._from or
          (self._side and side_of(ref)==self._side and not ref:is_player())
        if not own and is_target(ref) then stop=ref:get_pos() end
      elseif pt.type=="node" then
        local def=C.registered_nodes[C.get_node(pt.under).name]
        if def and def.walkable~=false then stop=pt.intersection_point end
      end
      if stop then
        if pt.type=="node" then ball_on_node(pt.intersection_point,self._side) end
        burst(pt.intersection_point or stop,self._shooter,vel,pt.ref,self._side,self._from)
        self.object:remove()
        return
      end
    end
  end,
})
-- Fires a cannonball from pos with velocity vel. shooter (a player name) is never hit by
-- it; a knight firing passes itself as from and its side.
local function fire(pos,vel,shooter,from,side)
  local obj=C.add_entity(pos,"brickcraft:cannonball")
  if not obj then return end
  obj:set_velocity(vel); obj:set_acceleration({x=0,y=-BALL_GRAVITY,z=0})
  local ent=obj:get_luaentity()
  ent._shooter,ent._from,ent._side=shooter,from,side or (shooter and team_of(shooter))
  C.add_particlespawner({amount=10,time=.1,minpos=pos,maxpos=pos,minvel={x=-1,y=.5,z=-1},maxvel={x=1,y=1.5,z=1},
    minexptime=.5,maxexptime=1,minsize=4,maxsize=7,texture="brickcraft_smoke.png"})
  return obj
end

-- Cannonballs to carry: each shot uses one.
local function use_ammo(player)
  local name=player:get_player_name()
  local s=war[name]
  if s.ammo<=0 then
    C.chat_send_player(name,"Out of cannonballs! Walk over a pile of them to pick some up.")
    return false
  end
  s.ammo=s.ammo-1; update_hud(player)
  return true
end
-- Piles of cannonballs: walk over one to pick it up.
C.register_entity(":brickcraft:ammo",{
  initial_properties={visual="sprite",textures={"brickcraft_ammo.png"},visual_size={x=.7,y=.7},
    physical=false,pointable=false,static_save=false},
  on_activate=function(self) piles[self]=true end,
  on_deactivate=function(self) piles[self]=nil end,
  on_step=function(self,dtime)
    self._age=(self._age or 0)+dtime
    if self._age>120 then self.object:remove(); return end
    local p=self.object:get_pos()
    for _,pl in ipairs(C.get_connected_players()) do
      local s=war[pl:get_player_name()]
      local q=pl:get_pos()
      if s and s.ammo<AMMO_MAX and math.abs(q.x-p.x)<.9 and math.abs(q.z-p.z)<.9 and q.y>p.y-1.2 and q.y<p.y+.6 then
        s.ammo=math.min(AMMO_MAX,s.ammo+AMMO_PILE); update_hud(pl)
        C.chat_send_player(pl:get_player_name(),"+"..AMMO_PILE.." cannonballs ("..s.ammo..")")
        self.object:remove(); return
      end
    end
  end,
})
-- The cell on the ground near pos (the first walkable node with two free cells above).
local function ground_at(x,y,z)
  for gy=math.floor(y+.5)+5,math.floor(y+.5)-6,-1 do
    local function solid(yy)
      local def=C.registered_nodes[C.get_node({x=x,y=yy,z=z}).name]
      return not def or def.walkable~=false
    end
    if solid(gy) and not solid(gy+1) and not solid(gy+2) then return {x=x,y=gy+1,z=z} end
  end
end
local function drop_ammo(pos)
  return C.add_entity({x=pos.x,y=math.floor(pos.y+.5)-.15,z=pos.z},"brickcraft:ammo")
end
-- Fires from the player's hands the way they look, in an arc a little above where they
-- look (never down: looking at the ground ahead would burst it at their feet).
local function fire_from(player)
  local name=player:get_player_name()
  local s=war[name]
  if not s then return end
  local t=now()
  if (s.last.cannon or 0)+.8>t then return end
  if not use_ammo(player) then return end
  s.last.cannon=t
  local yaw=player:get_look_horizontal()
  local h={x=-math.sin(yaw),y=0,z=math.cos(yaw)}
  local e=math.max(.12,math.min(1.1,math.asin(player:get_look_dir().y)+.12))
  local eye=vector.offset(player:get_pos(),0,1.4,0)
  return fire(vector.add(eye,vector.multiply(h,.8)),
    {x=h.x*math.cos(e)*BALL_SPEED,y=math.sin(e)*BALL_SPEED,z=h.z*math.cos(e)*BALL_SPEED},name)
end

-- A cannon on wheels. Right click it in war: it turns the way you look and fires where you
-- aim (up to steep lobs; never down into the ground). A castle's cannons (_castle, on the
-- walls) need no cannonballs of yours and aim down at the ground below too. A Red Army's
-- cannons (_team) fire by themselves (red_cannon, below).
local red_cannon
C.register_entity(":brickcraft:cannon",{
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
  on_step=function(self) if self._team then red_cannon(self) end end,
  on_rightclick=function(self,clicker)
    local name=clicker:get_player_name()
    if self._team then return end
    if not war[name] then C.chat_send_player(name,"Cannons are for war mode: type /war to play."); return end
    local t=now()
    if (self._fired or 0)+1.2>t then return end
    if not self._castle and not use_ammo(clicker) then return end
    self._fired=t
    local yaw=clicker:get_look_horizontal()
    self.object:set_yaw(yaw)
    local h={x=-math.sin(yaw),y=0,z=math.cos(yaw)}
    local e=math.max(self._castle and -.8 or -.05,math.min(1.1,math.asin(clicker:get_look_dir().y)))
    local muzzle=vector.add(self.object:get_pos(),{x=h.x*.6,y=.38,z=h.z*.6})
    fire(muzzle,{x=h.x*math.cos(e)*BALL_SPEED,y=math.sin(e)*BALL_SPEED,z=h.z*math.cos(e)*BALL_SPEED},name)
  end,
})
C.register_tool(":brickcraft:cannon",{
  description="Cannon (war)\nLeft click: fire a cannonball where you look\nRight click the ground: set up a cannon (3 at most)\nRight click a cannon: aim and fire it\nLeft click your cannon: take it back",
  inventory_image="brickcraft_cannon.png",wield_image="brickcraft_cannon.png",range=7,
  groups={not_in_creative_inventory=1},
  on_place=function(stack,placer,pointed) return put_up("brickcraft:cannon",CANNONS,stack,placer,pointed) end,
  on_use=function(stack,user,pointed)
    local ent=pointed.type=="object" and pointed.ref:get_luaentity()
    if ent and ent.name=="brickcraft:cannon" and ent._owner==user:get_player_name() then ent.object:remove()
    else fire_from(user) end
    return stack
  end,
  on_secondary_use=function(stack,user,pointed)
    if pointed.type~="object" then fire_from(user) end -- a right clicked cannon fires itself
    return stack
  end,
  on_drop=keep,
})

-- Arrows: fast and nearly straight, exactly where you look (down off a wall too), a heart
-- each; as many as you like. A thin stick that turns the way it flies.
local ARROW_SPEED,ARROW_GRAVITY=30,5
C.register_entity(":brickcraft:arrow",{
  initial_properties={visual="cube",textures={"brickcraft_brown.png","brickcraft_brown.png","brickcraft_brown.png",
    "brickcraft_brown.png","brickcraft_cream.png","brickcraft_cream.png"},visual_size={x=.06,y=.06,z=.75},
    physical=false,pointable=false,static_save=false},
  on_step=function(self,dtime)
    local pos=self.object:get_pos()
    self._age=(self._age or 0)+dtime
    local prev=self._prev or pos
    self._prev=pos
    if self._age>4 or pos.y< -10 then self.object:remove(); return end
    local vel=self.object:get_velocity()
    self.object:set_rotation({x=-math.atan2(vel.y,math.sqrt(vel.x^2+vel.z^2)),y=math.atan2(-vel.x,vel.z),z=0})
    for pt in C.raycast(prev,pos,true,false) do
      if pt.type=="object" then
        local ref=pt.ref
        local own=(ref:is_player() and ref:get_player_name()==self._shooter) or ref==self._from or
          (self._side and side_of(ref)==self._side and not ref:is_player())
        if not own and is_target(ref) then
          hit(ref,self._shooter and C.get_player_by_name(self._shooter) or self._from,"arrow",vel,self._side)
          self.object:remove(); return
        end
      elseif pt.type=="node" then
        local def=C.registered_nodes[C.get_node(pt.under).name]
        if def and def.walkable~=false then self.object:remove(); return end
      end
    end
  end,
})
-- An arrow from pos along dir: a player's (shooter, their name) or an archer's (from).
local function loose(pos,dir,shooter,from,side)
  local obj=C.add_entity(pos,"brickcraft:arrow")
  if not obj then return end
  obj:set_velocity(vector.multiply(dir,ARROW_SPEED)); obj:set_acceleration({x=0,y=-ARROW_GRAVITY,z=0})
  local ent=obj:get_luaentity()
  ent._shooter,ent._from,ent._side=shooter,from,side
  return obj
end
local function shoot_arrow(player)
  local name=player:get_player_name()
  local s=war[name]
  if not s then return end
  local t=now()
  if (s.last.arrow or 0)+MOVES.arrow.cool>t then return end
  s.last.arrow=t
  local dir=player:get_look_dir()
  return loose(vector.add(vector.offset(player:get_pos(),0,1.45,0),vector.multiply(dir,.6)),dir,name,nil,team_of(name))
end
C.register_tool(":brickcraft:bow",{
  description="Bow (war)\nLeft click: shoot an arrow where you look (1 heart)\nAs many arrows as you like",
  inventory_image="brickcraft_bow.png",wield_image="brickcraft_bow.png",range=4,
  groups={not_in_creative_inventory=1},
  on_use=function(stack,user) shoot_arrow(user); return stack end,
  on_secondary_use=function(stack,user) shoot_arrow(user); return stack end,
  on_drop=keep,
})

-- Brick Knights. Practice knights (War Lab, no side) just stand there: knocked out, they
-- fall over and get back up at their spot. Blue knights (your Knight tool) follow you and
-- fight the Red Army. Red Knights charge at players in war and blue knights; their Red
-- Commander keeps back and lobs cannonballs. Knocked out, a red knight is gone (dropping
-- a pile of cannonballs), a blue one gets back up; the Commander takes its army with it.
local LOOKS={
  practice={tex="brickcraft_person_knight.png",name="Practice Target",tag="#d8dde6",hp=MAX_HP},
  archer={tex="brickcraft_person_blueknight.png^[colorize:#e8d9a8:70",name="Castle Archer",tag="#8fd0ff",hp=MAX_HP,speed=3.4,sight=15},
  blue={tex="brickcraft_person_blueknight.png",name="Blue Knight",tag="#8fd0ff",hp=MAX_HP,speed=3.4,sight=12},
  green={tex="brickcraft_person_blueknight.png^[colorize:#2fae45:150",name="Green Knight",tag="#7be08a",hp=MAX_HP,speed=3.4,sight=12},
  red={tex="brickcraft_person_redknight.png",name="Red Knight",tag="#ff7a6a",hp=6,speed=2.6,sight=14},
  boss={tex="brickcraft_person_redboss.png",name="Red Commander",tag="#ff5040",hp=20,speed=2,sight=20,size=1.3},
}
local armies={} -- id -> {boss=luaentity, lab=the War Lab world when it camps there}
local next_lab_army=0 -- not before this time (not saved: world tables are)
local function knight_tag(self)
  self.object:set_properties({nametag=self._name.."  "..math.max(0,self._hp).."/"..self._max})
end
local function look_of(self) return LOOKS[self._boss and "boss" or self._archer and "archer" or self._team or "practice"] end
local function dress(self)
  local l=look_of(self)
  local k=l.size or 1
  self._name,self._max,self._tex=l.name,l.hp,l.tex
  self._hp=self._hp or l.hp
  self.object:set_properties({textures={l.tex},visual_size={x=10*k,y=10*k},nametag_color=l.tag,
    collisionbox={-.3*k,0,-.3*k,.3*k,1.75*k,.3*k},selectionbox={-.3*k,0,-.3*k,.3*k,1.75*k,.3*k}})
  knight_tag(self)
end
-- Puts up a knight standing on the cell pos; team is nil (practice), "red", or a player's team.
local function spawn_knight(pos,team,opts)
  local obj=C.add_entity({x=pos.x,y=pos.y-.5,z=pos.z},"brickcraft:knight")
  if not obj then return end
  local ent=obj:get_luaentity()
  opts=opts or {}
  ent._team,ent._boss,ent._owner,ent._army,ent._lab=team,opts.boss,opts.owner,opts.army,opts.lab
  ent._home,ent._hp=obj:get_pos(),nil
  if opts.yaw then obj:set_yaw(opts.yaw) end
  dress(ent)
  return ent
end
local function face(obj,d) obj:set_yaw(math.atan2(-d.x,d.z)) end
local function alive(ent) return ent and ent.object:get_pos() and not ent._down end
local function flat_dist(a,b) return math.sqrt((a.x-b.x)^2+(a.z-b.z)^2) end
-- Is obj something this knight fights?
local function foe_of(self,obj)
  if obj:is_player() then
    local s=war[obj:get_player_name()]
    return self._team and s and s.shield<now() and s.team~=self._team
  end
  local e=obj:get_luaentity()
  return e and e.name=="brickcraft:knight" and not e._down and e._team and e._team~=self._team
end
-- The closest foe within radius of center (default: the knight, as far as it sees). want
-- picks a kind first ("commander", "knights", "players"); anything else will do after.
local function find_foe(self,p,radius,center,want)
  local best,bd,any,ad
  center=center or p
  for _,obj in ipairs(C.get_objects_inside_radius(center,radius or look_of(self).sight)) do
    if foe_of(self,obj) then
      local e=obj:get_luaentity()
      local kind=obj:is_player() and "players" or e._boss and "commander" or "knights"
      local d=vector.distance(p,obj:get_pos())
      if (want==kind or (want=="knights" and kind=="commander")) and (not bd or d<bd) then best,bd=obj,d end
      if not ad or d<ad then any,ad=obj,d end
    end
  end
  if best then return best,bd end
  return any,ad
end
local function poof(pos)
  C.add_particlespawner({amount=24,time=.15,minpos=pos,maxpos=vector.offset(pos,0,1.4,0),
    minvel={x=-1.5,y=0,z=-1.5},maxvel={x=1.5,y=2,z=1.5},minexptime=.5,maxexptime=1,minsize=4,maxsize=8,
    texture="brickcraft_smoke.png"})
end
local function defeat_army(id,by)
  local army=armies[id]
  if not army then return end
  armies[id]=nil
  if army.lab then next_lab_army=now()+30 end
  for ent in pairs(things) do
    if ent._army==id and ent.object:get_pos() and not ent._boss then
      ent._down=now()+1.5; ent._gone=true
      ent.object:set_rotation({x=-math.pi/2,y=ent.object:get_yaw(),z=0})
    end
  end
  tell_war((by and by:is_player() and label(by).." beat" or "Blue beat").." the Red Army! (/battle for another)")
end

-- The next spot on the way to `to`: straight there when it's right there, else along
-- a path (core.find_path, a block's jump at a time) round walls and up hills, planned
-- again every 1.5 s or when the target moves to another cell. No path: straight on.
local function cell_of(pos) return vector.round({x=pos.x,y=pos.y+.5,z=pos.z}) end
local function next_step(self,p,to)
  self._step_up=false
  if math.abs(to.y-p.y)<.6 and flat_dist(p,to)<1.5 then self._path=nil; return to end
  local t,goal=now(),cell_of(to)
  if self._path==nil or (self._path_at or 0)+1.5<t or
     (not vector.equals(self._goal,goal) and (self._path_at or 0)+.5<t) then
    self._path=C.find_path(cell_of(p),goal,24,1,3,"A*_noprefetch") or false
    self._path_at,self._goal=t,goal
  end
  local path=self._path
  if not path then return to end
  while path[1] and flat_dist(p,path[1])<.5 and math.abs(path[1].y-.5-p.y)<.8 do table.remove(path,1) end
  local wp=path[1]
  if not wp then return to end
  self._step_up=wp.y-.5>p.y+.3
  return {x=wp.x,y=wp.y-.5,z=wp.z}
end
-- Walks toward (or with back, away from) a spot: the knight's own speed, jumping a block
-- when it bumps into one, its path steps up, or it hasn't got anywhere for a second.
local function walk(self,to,back)
  local p=self.object:get_pos()
  if not back then to=next_step(self,p,to) end
  local d={x=to.x-p.x,y=0,z=to.z-p.z}
  local len=math.sqrt(d.x*d.x+d.z*d.z)
  if len<.1 then return end
  d={x=d.x/len,y=0,z=d.z/len}
  face(self.object,back and {x=-d.x,z=-d.z} or d)
  local k=(back and -.7 or 1)*look_of(self).speed
  local v=self.object:get_velocity()
  local vy=v.y
  local t=now()
  if not self._moved or vector.distance(self._moved,p)>.3 then self._moved,self._moved_at=p,t end
  local stuck=t-self._moved_at>1
  if (self._bumped or self._step_up or stuck) and self._grounded then vy=7.5 end
  self.object:set_velocity({x=d.x*k,y=vy,z=d.z*k})
end
-- Orders: each side's knights follow one order at a time. Blue knights take their
-- owner's (blue_orders[name], given through their AI builder or /orders); a Red Army
-- takes its Commander's (army.order, from its agent: plan_red). An order is
-- {mode, target ("commander"/"knights"/"players"/nil), side ("left"/"right"), at (time)}.
--   follow: blue's default; fight what comes, else stay by the owner.
--   charge: go for the target anywhere within 40, then anything.
--   flank:  walk round to the target's side first, then charge.
--   hold:   stay where they were told; fight only what comes within 4.
--   guard:  stay by the owner (red: the Commander); fight what comes within 6 of them.
--   retreat: back to the owner (Commander), no fighting.
local MODES={follow=true,charge=true,flank=true,hold=true,guard=true,retreat=true}
local blue_orders={}
local function order_of(self)
  if self._owner then return blue_orders[self._owner] end
  local army=armies[self._army or 0]
  return army and army.order
end
-- Who the knight stays by: its owner, or its Commander.
local function leader_of(self)
  if self._owner then return C.get_player_by_name(self._owner) end
  local army=armies[self._army or 0]
  return army and alive(army.boss) and army.boss.object
end
local function swing(self,foe,p)
  face(self.object,vector.subtract(foe:get_pos(),p))
  self._still=true
  local t=now()
  if (self._swung or 0)+MOVES.knight.cool<t then
    self._swung=t
    hit(foe,self.object,"knight")
  end
end
-- Goes for foe (sword when close).
local function engage(self,foe,fd,p)
  if fd<1.8 then swing(self,foe,p) else walk(self,foe:get_pos()) end
end
local function stay_by(self,spot,p,gap)
  if spot and flat_dist(p,spot)>gap then walk(self,spot) else self._still=true end
end
-- A cannonball from `from` (a lobbing thrower's hands, or a cannon: v) at foe, side's own.
local function lob(from,foe,thrower,side,v)
  local q=vector.offset(foe:get_pos(),0,.8,0)
  local dx,dz=q.x-from.x,q.z-from.z
  local dist=math.max(math.sqrt(dx*dx+dz*dz),.1)
  v=v or 13
  -- The low arc that reaches dist on level ground, 45 degrees if it can't.
  local sn=BALL_GRAVITY*dist/(v*v)
  local e=sn<1 and math.asin(sn)/2 or math.pi/4
  e=e+math.atan2(q.y-from.y,math.max(dist,1))*.5
  fire(from,{x=dx/dist*math.cos(e)*v,y=math.sin(e)*v,z=dz/dist*math.cos(e)*v},nil,thrower,side)
end
-- A Red Army's cannon fires every 6 seconds at the closest foe within 30, a castle wall in
-- the way or not. Three cannonballs or a few strikes put one out; it goes with its army.
local RED_CANNON_HP=9
local function red_cannon_tag(self)
  self.object:set_properties({nametag="Red Cannon  "..math.max(0,self._hp).."/"..RED_CANNON_HP})
end
red_cannon=function(self)
  if not armies[self._army or 0] then poof(self.object:get_pos()); self.object:remove(); return end
  local t=now()
  if (self._fired or 0)+TUNE.red_cannon_every>t then return end
  local p=self.object:get_pos()
  local foe=find_foe(self,p,30)
  if not foe then return end
  self._fired=t+math.random()
  local d=vector.subtract(foe:get_pos(),p)
  face(self.object,d)
  local h=vector.normalize({x=d.x,y=0,z=d.z})
  lob(vector.add(p,{x=h.x*.7,y=.45,z=h.z*.7}),foe,self.object,"red",BALL_SPEED)
end
local function red_cannon_hit(self,attacker,m)
  if m.dmg==0 or self._hp<=0 then return true end
  self._hp=self._hp-m.dmg
  red_cannon_tag(self)
  if self._hp<=0 then
    local p=self.object:get_pos()
    poof(p); drop_ammo(p)
    local by=attacker and attacker:is_player() and war[attacker:get_player_name()]
    if by then
      by.kos=by.kos+1; update_hud(attacker)
      C.chat_send_player(attacker:get_player_name(),"You knocked out a Red Cannon!")
    end
    things[self]=nil; self.object:remove()
  end
  return true
end
local function spawn_red_cannon(pos,yaw,army)
  local obj=C.add_entity({x=pos.x,y=pos.y-.5,z=pos.z},"brickcraft:cannon")
  if not obj then return end
  obj:set_yaw(yaw)
  obj:set_properties({textures={"brickcraft_brown.png^[colorize:#8a2418:120","brickcraft_cannon_metal.png"},
    visual_size={x=14,y=14},nametag_color="#ff7a6a",nametag_bgcolor="#14293699"})
  local ent=obj:get_luaentity()
  ent._team,ent._army,ent._name,ent._hp,ent._hit="red",army,"Red Cannon",RED_CANNON_HP,red_cannon_hit
  red_cannon_tag(ent)
  return ent
end
local build -- (below, the Siege Castle) a red builder's turn; true while it builds
local function think(self)
  local p=self.object:get_pos()
  if self._build and build(self,p) then return end
  if self._archer then
    -- A castle archer keeps its post: its sword for a foe right there, else an arrow every
    -- 1.5 seconds at the closest it sees (aimed a little high for the drop).
    local foe,fd=find_foe(self,p,1.8)
    if foe then swing(self,foe,p); return end
    if flat_dist(p,self._home)>.8 then walk(self,self._home); return end
    self._still=true
    foe,fd=find_foe(self,p)
    if not foe then return end
    local eye=vector.offset(p,0,1.45,0)
    local q=vector.offset(foe:get_pos(),0,.9,0)
    face(self.object,vector.subtract(q,p))
    local t=now()
    if (self._shot or 0)+TUNE.archer_every>t then return end
    self._shot=t
    local fly=vector.distance(eye,q)/ARROW_SPEED
    local dir=vector.normalize(vector.subtract(vector.offset(q,0,ARROW_GRAVITY*fly*fly/2,0),eye))
    loose(vector.add(eye,vector.multiply(dir,.6)),dir,nil,self.object,self._team)
    return
  end
  if self._boss then
    -- The Commander keeps 6 to 12 away and lobs a cannonball every 3 seconds; on retreat
    -- or guard it stays put behind its knights.
    local o=order_of(self) or {}
    local foe,fd=find_foe(self,p,nil,nil,o.target)
    if foe then
      if fd<6 then walk(self,foe:get_pos(),true)
      elseif fd>12 and o.mode~="retreat" and o.mode~="guard" and o.mode~="hold" and not (armies[self._army] or {}).stay then walk(self,foe:get_pos())
      else self._still=true end
      face(self.object,vector.subtract(foe:get_pos(),p))
      local t=now()
      if (self._lobbed or 0)+3<t then
        self._lobbed=t
        lob(vector.offset(p,0,2.2,0),foe,self.object,"red")
      end
    elseif flat_dist(p,self._home)>3 then walk(self,self._home) else self._still=true end
    return
  end
  local o=order_of(self) or {mode="follow"}
  local mode=o.mode
  local leader=leader_of(self)
  local lp=leader and leader:get_pos()
  if mode=="retreat" then
    local foe,fd=find_foe(self,p,1.8)
    if foe then swing(self,foe,p) else stay_by(self,lp or self._home,p,2.5) end
    return
  end
  if mode=="hold" then
    -- The spot each knight stood on when told.
    if self._held~=o.at then self._held,self._anchor=o.at,p end
    local foe,fd=find_foe(self,p,4,self._anchor)
    if foe then engage(self,foe,fd,p) else stay_by(self,self._anchor,p,1.5) end
    return
  end
  if mode=="guard" then
    local foe,fd=find_foe(self,p,6,lp or p)
    if foe then engage(self,foe,fd,p) else stay_by(self,lp,p,2.5) end
    return
  end
  if mode=="flank" then
    -- First round to the side of the target (left or right as seen from here), then charge.
    if self._flanked~=o.at then
      local foe=find_foe(self,p,40,nil,o.target)
      if foe then
        local t=foe:get_pos()
        local d=vector.direction({x=p.x,y=0,z=p.z},{x=t.x,y=0,z=t.z})
        local k=o.side=="right" and 1 or -1
        self._flank_to=vector.add(t,{x=d.z*k*7,y=0,z=-d.x*k*7})
        self._flank_until=now()+10
      else self._flank_to=nil end
      self._flanked=o.at
    end
    if self._flank_to and now()<self._flank_until and flat_dist(p,self._flank_to)>2.5 then
      local foe,fd=find_foe(self,p,1.8)
      if foe then swing(self,foe,p) else walk(self,self._flank_to) end
      return
    end
    self._flank_to=nil
    local foe,fd=find_foe(self,p,40,nil,o.target)
    if foe then engage(self,foe,fd,p) else stay_by(self,lp or self._home,p,2.5) end
    return
  end
  if mode=="charge" then
    local foe,fd=find_foe(self,p,40,nil,o.target)
    if foe then engage(self,foe,fd,p) else stay_by(self,lp or self._home,p,2.5) end
    return
  end
  -- follow (and red with no order): fight what it sees, else back by the leader.
  local foe,fd=find_foe(self,p)
  if foe then engage(self,foe,fd,p)
  elseif self._owner then stay_by(self,lp,p,3)
  else
    local home=self._home
    if leader then home=vector.add(lp,self._offset or {x=0,y=0,z=0}) end
    stay_by(self,home,p,2)
  end
end

C.register_entity(":brickcraft:knight",{
  initial_properties={visual="mesh",mesh="brickcraft_person_short.obj",textures={LOOKS.practice.tex},
    visual_size={x=10,y=10},physical=true,collide_with_objects=false,pointable=true,static_save=false,
    collisionbox={-.3,0,-.3,.3,1.75,.3},selectionbox={-.3,0,-.3,.3,1.75,.3},stepheight=.6,
    nametag_color="#d8dde6",nametag_bgcolor="#14293699"},
  on_activate=function(self)
    self.object:set_armor_groups({immortal=1})
    self.object:set_acceleration({x=0,y=-2*9.81,z=0})
    dress(self)
    things[self]=true
  end,
  on_deactivate=function(self) things[self]=nil end,
  on_punch=function() return true end,
  on_rightclick=function(self,clicker)
    if KIT_ITEM[clicker:get_wielded_item():get_name()] then move_by(clicker,self.object,"push") end
  end,
  _hit=function(self,attacker,m,v)
    if self._down then return false end
    self.object:add_velocity(self._boss and vector.multiply(v,.5) or v)
    self._stun=now()+.5
    if m.dmg==0 then return true end
    flash(self.object,self._tex)
    self._hp=self._hp-m.dmg
    if self._hp<=0 then
      -- Falls on its back, away from the hit.
      self._down=now()+(self._owner and 5 or self._team=="red" and 1.5 or 3)
      self._gone=self._team=="red" or self._archer -- archers are out until the next army
      self.object:set_rotation({x=-math.pi/2,y=self.object:get_yaw(),z=0})
      local by=attacker and attacker:is_player() and war[attacker:get_player_name()]
      if by then
        by.kos=by.kos+1; update_hud(attacker)
        C.chat_send_player(attacker:get_player_name(),"You knocked out the "..self._name.."!")
      end
      if self._boss then defeat_army(self._army,attacker) end
    end
    knight_tag(self)
    return true
  end,
  on_step=function(self,dtime,moveresult)
    local v=self.object:get_velocity()
    self._grounded=moveresult and moveresult.touching_ground
    self._bumped=false
    for _,c in ipairs(moveresult and moveresult.collisions or {}) do
      if c.type=="node" and c.axis~="y" then self._bumped=true end
    end
    local p=self.object:get_pos()
    if self._down then
      if now()>self._down then
        if self._gone then
          poof(p)
          if self._team=="red" then drop_ammo(p) end
          if self._boss then for _=1,2 do drop_ammo(vector.offset(p,math.random(-2,2),0,math.random(-2,2))) end end
          self.object:remove(); return
        end
        self._down,self._hp=nil,self._max
        self.object:set_rotation({x=0,y=self.object:get_yaw(),z=0})
        self.object:set_velocity({x=0,y=0,z=0})
        if not self._team and self._home then self.object:set_pos(self._home) end
        knight_tag(self)
      end
    elseif self._team and (self._stun or 0)<now() then
      self._t=(self._t or 0)+dtime
      if self._t>=.3 then self._t=0; self._still=false; think(self) end
      if self._still then self.object:set_velocity({x=0,y=v.y,z=0}) end
    elseif self._grounded then
      local f=math.max(0,1-dtime*6)
      self.object:set_velocity({x=v.x*f,y=v.y,z=v.z*f})
    end
    if p.y< -8 then
      if self._team=="red" then self.object:remove(); return end
      self.object:set_pos(self._home); self.object:set_velocity({x=0,y=0,z=0})
    end
  end,
})
C.register_tool(":brickcraft:knight",{
  description="Brick Knight (war)\nRight click the ground: a blue knight who follows you and fights the Red Army (4 at most)\nLeft click your knight: take it back",
  inventory_image="brickcraft_knight.png",wield_image="brickcraft_knight.png",range=7,
  groups={not_in_creative_inventory=1},
  on_place=function(stack,placer,pointed)
    if pointed.type~="node" or not placer:is_player() then return stack end
    local name=placer:get_player_name()
    if not war[name] then return stack end
    if count_owned("brickcraft:knight",name)>=KNIGHTS then
      C.chat_send_player(name,"You have "..KNIGHTS.." knights already. Left click one holding this to take it back.")
      return stack
    end
    local def=C.registered_nodes[C.get_node(pointed.under).name]
    spawn_knight((def and def.buildable_to) and pointed.under or pointed.above,team_of(name),
      {owner=name,yaw=placer:get_look_horizontal()})
    return stack
  end,
  on_use=take_back("brickcraft:knight"),
  on_drop=keep,
})

-- How many knights come with a Red Army's Commander: each world's own (/armysize), kept
-- in this mod's storage by world id (the Workshop's too), 8 unless set.
local ARMY_SIZE,ARMY_MAX=8,20
local war_storage=C.get_mod_storage()
local function army_size(w) return war_storage:get_int("army_size_"..w.id)>0 and war_storage:get_int("army_size_"..w.id) or ARMY_SIZE end
-- Their spots round the Commander: rings of 8, 2 apart from 2.5 out.
local function escort_of(n)
  local out={}
  for i=0,n-1 do
    local r,a=2.5+math.floor(i/8)*2,(i%8+(math.floor(i/8)%2)*.5)*math.pi/4
    out[#out+1]={x=math.floor(math.cos(a)*r+.5),z=math.floor(math.sin(a)*r+.5)}
  end
  return out
end
-- The Red Army: a Commander and its world's army size of knights at center (escort: other
-- offsets, {} for none), facing toward. Returns its id.
local army_seq=0
local function spawn_army(center,toward,lab,escort)
  army_seq=army_seq+1
  local id=army_seq
  local d=vector.subtract(toward,center)
  local yaw=math.atan2(-d.x,d.z)
  local boss=spawn_knight(center,"red",{boss=true,army=id,yaw=yaw})
  if not boss then return end
  armies[id]={boss=boss,lab=lab,order={mode="charge",at=now()},next_plan=now()+5}
  for _,o in ipairs(escort or escort_of(army_size(brickcraft.world_at(center)))) do
    local g=ground_at(center.x+o.x,center.y,center.z+o.z) or vector.offset(center,o.x,0,o.z)
    local k=spawn_knight(g,"red",{army=id,yaw=yaw})
    if k then k._offset={x=o.x,y=0,z=o.z} end
  end
  -- Red smoke marks where it turned up.
  C.add_particlespawner({amount=60,time=1.5,minpos=vector.offset(center,-3,0,-3),maxpos=vector.offset(center,3,1,3),
    minvel={x=-.3,y=1,z=-.3},maxvel={x=.3,y=2.5,z=.3},minexptime=1,maxexptime=2,minsize=6,maxsize=12,
    texture="brickcraft_smoke.png^[colorize:#d03020:160"})
  tell_war("The Red Army is coming! Knock out the Red Commander to beat it.")
  return id
end
-- /battle: a Red Army 16 blocks the way you look.
local function battle(player)
  local name=player:get_player_name()
  if not war[name] then return false,"Start war mode first: /war" end
  local n=0
  for _ in pairs(armies) do n=n+1 end
  if n>=2 then return false,"Two Red Armies are out already. Beat one first!" end
  local p=player:get_pos()
  local yaw=player:get_look_horizontal()
  local g
  for dist=16,6,-2 do
    g=ground_at(math.floor(p.x-math.sin(yaw)*dist+.5),p.y,math.floor(p.z+math.cos(yaw)*dist+.5))
    if g then break end
  end
  if not g then return false,"No room for an army there: look across open ground." end
  return spawn_army(g,p)~=nil,"Here comes the Red Army!"
end
C.register_chatcommand("armysize",{params="[1-"..ARMY_MAX.."]",description="War mode: how many knights come with each Red Army in this world",
  func=function(name,param)
    local p=C.get_player_by_name(name)
    if not p then return false,"Player is not connected." end
    if not war[name] then return false,"Start war mode first: /war" end
    local w=brickcraft.world_at(p:get_pos())
    local n=tonumber(param)
    if not n then return true,"Red Armies in "..w.name.." come with "..army_size(w).." knights. /armysize 1-"..ARMY_MAX.." to change it." end
    n=math.max(1,math.min(ARMY_MAX,math.floor(n)))
    war_storage:set_int("army_size_"..w.id,n)
    tell_war(label(p).." set Red Armies in "..w.name.." to "..n.." knights.")
    return true
  end})
C.register_chatcommand("battle",{description="War mode: call a Red Army to fight (a Commander and this world's army size of knights, 8 unless /armysize)",
  func=function(name)
    local p=C.get_player_by_name(name)
    if not p then return false,"Player is not connected." end
    return battle(p)
  end})

-- Where something is from here, in words: "8 east, 3 north".
local function rel(from,to)
  local dx,dz=math.floor(to.x-from.x+.5),math.floor(to.z-from.z+.5)
  return math.abs(dx).." "..(dx>=0 and "east" or "west")..", "..math.abs(dz).." "..(dz>=0 and "north" or "south")
end
local function blue_knights(name)
  local out={}
  for ent in pairs(things) do
    if ent.name=="brickcraft:knight" and ent._owner==name and ent.object:get_pos() then out[#out+1]=ent end
  end
  return out
end
local function red_knights(id)
  local out={}
  for ent in pairs(things) do
    if ent._army==id and ent.name=="brickcraft:knight" and not ent._boss and ent.object:get_pos() and not ent._down then out[#out+1]=ent end
  end
  return out
end
local ORDER_SYSTEM=[[You command one side in a friendly toy-brick battle game a family (kids included) plays. Knights are block people with swords; nobody really gets hurt. Orders for a side's knights, all of them at once:
- "follow": stay by the leader, fight what comes close (the default).
- "charge": go for the target anywhere on the field, then anyone.
- "flank": walk round to the target's "left" or "right" side first, then charge.
- "hold": stay where they stand, fight only what comes within 4 blocks.
- "guard": stay by the leader, fight what comes within 6 blocks of them.
- "retreat": back to the leader, no fighting.
Targets: "commander" (the enemy's leader), "knights" (their knights), "players" (people playing), or null for the nearest.

Answer with one JSON object and nothing else: {"mode": one of the orders, "target": a target or null, "side": "left" or "right" (flank only), "say": one short, cheerful line to say out loud (under 15 words, kid-friendly, no gore)}.]]
local RED_SYSTEM=ORDER_SYSTEM..[[


You are the Red Commander, leading the Red Army's knights against players and their blue knights. You stay back and throw cannonballs yourself. Pick the order that gives your army the best chance this moment: e.g. flank a strong group, guard yourself when they come for you, retreat to regroup when few knights are left, charge a player who is low on hearts. Vary your plans; be a sporting, theatrical villain in "say".]]
local function red_say(army,text)
  if type(text)~="string" or text=="" then return end
  local line=C.colorize("#ff5040","<Red Commander> ")..text:sub(1,140)
  local bp=army.boss.object:get_pos()
  for name in pairs(war) do
    local pl=C.get_player_by_name(name)
    if pl and bp and vector.distance(pl:get_pos(),bp)<60 then C.chat_send_player(name,line) end
  end
  C.log("action","[war] Red Commander: "..text)
end
-- An order from a reply (Claude's or a built-in one); nil when it isn't one.
local function clean_order(r)
  if type(r)~="table" or not MODES[r.mode] then return nil end
  local t=r.target
  if t~="commander" and t~="knights" and t~="players" then t=nil end
  return {mode=r.mode,target=t,side=r.side=="right" and "right" or "left",at=now()}
end
-- The Red Commander's agent: every 15 seconds it looks over the field and picks its
-- army's next order. With Claude (the AI builders' Local AI API) it plans in its own
-- words; without, it runs through a few built-in tactics.
local function red_field(army,id)
  local bp=army.boss.object:get_pos()
  local mine=red_knights(id)
  local hearts={}
  for _,k in ipairs(mine) do hearts[#hearts+1]=k._hp.."/6" end
  local lines={("You: %d/20 hearts. Your knights: %d left%s."):format(army.boss._hp,#mine,
    #mine>0 and " (hearts "..table.concat(hearts,", ")..")" or "")}
  local foes,weakest=0,nil
  for name,s in pairs(war) do
    local pl=C.get_player_by_name(name)
    local q=pl and pl:get_pos()
    if q and vector.distance(q,bp)<50 then
      foes=foes+1
      local blues=#blue_knights(name)
      lines[#lines+1]=("Player %s: %d/10 hearts, %s of you, %d cannonballs, %d blue knight%s."):format(
        label(pl),s.hp,rel(bp,q),s.ammo,blues,blues==1 and "" or "s")
      if not weakest or s.hp<weakest then weakest=s.hp end
    end
  end
  return lines,mine,foes,weakest
end
local TACTICS={{mode="flank",side="left"},{mode="charge"},{mode="flank",side="right"},{mode="charge",target="players"}}
local function plan_red(army,id)
  if army.asking or not alive(army.boss) then return end
  local lines,mine,foes,weakest=red_field(army,id)
  if foes==0 then army.order={mode="guard",at=now()}; return end
  local function built_in()
    army.plan_n=(army.plan_n or 0)+1
    local o
    if #mine<=1 then o={mode="guard"}
    elseif weakest and weakest<=4 then o={mode="charge",target="players"}
    else o=TACTICS[(army.plan_n-1)%#TACTICS+1] end
    army.order=clean_order(o)
    local words={guard="Guard me, knights!",charge="Charge!",flank="Round the "..(o.side or "left").." side, knights!"}
    red_say(army,o.target=="players" and "Get the one with the fewest hearts!" or words[o.mode])
  end
  local ask=brickcraft.ai and brickcraft.ai.ask
  if not ask or not C.settings:get_bool("brickcraft_war_ai",true) then return built_in() end
  army.asking=true
  ask(RED_SYSTEM,"The battlefield now:\n"..table.concat(lines,"\n").."\nYour current order: "..
    ((army.order and army.order.mode) or "none")..". What now?",function(reply)
    army.asking=false
    if not armies[id] then return end
    local o=clean_order(reply)
    if not o then return built_in() end
    army.order=o
    red_say(army,reply.say)
  end,function(r) return clean_order(r)~=nil end)
end

-- Orders for a player's blue knights, in their words. Returns true when the words were an
-- order (or a war question); say(text) answers as their commander (their AI builder, or
-- the chat); not_order() takes back words that turn out not to be about the battle.
local ORDER_WORDS={
  {"retreat",{"retreat","fall back","back off","run away","come back","후퇴"}},
  {"hold",{"hold","stay","wait","halt","don't move","stand still","멈춰","대기"}},
  {"guard",{"guard","defend","protect","cover me","bodyguard","지켜"}},
  {"follow",{"follow","with me","따라"}},
  {"flank",{"flank","sneak","go around","from the left","from the right","on the left","on the right","돌아"}},
  {"charge",{"charge","attack","fight","kill","get them","get him","go get","go!","공격","돌격"}},
}
local function parse_order(low)
  local mode
  for _,m in ipairs(ORDER_WORDS) do
    for _,w in ipairs(m[2]) do if low:find(w,1,true) then mode=m[1]; break end end
    if mode then break end
  end
  if not mode then return nil end
  local target=(low:find("commander") or low:find("boss") or low:find("leader") or low:find("사령관")) and "commander"
    or (low:find("knight") or low:find("기사")) and "knights" or nil
  local side=(low:find("right") or low:find("오른")) and "right" or "left"
  return {mode=mode,target=target,side=side,at=now()}
end
local SAY_ORDER={follow="Knights, follow %s!",charge="Knights, charge%s!",hold="Knights, hold this spot!",
  guard="Knights, guard %s!",retreat="Knights, fall back to %s!"}
local function announce(o,who)
  local t=o.target=="commander" and " the Red Commander" or o.target=="knights" and " their knights" or ""
  if o.mode=="flank" then return "Knights, round the "..o.side.." side"..(t~="" and " of"..t or "")..", then charge!" end
  if o.mode=="charge" then return SAY_ORDER.charge:format(t) end
  return SAY_ORDER[o.mode]:format(who)
end
local function status(name,player)
  local mine=blue_knights(name)
  local o=blue_orders[name]
  local p=player:get_pos()
  local reds={}
  for id,army in pairs(armies) do
    local bp=army.boss.object:get_pos()
    if bp and vector.distance(p,bp)<80 then
      reds[#reds+1]=("a Red Army %s of you: Commander %d/20, %d knights"):format(rel(p,bp),army.boss._hp,#red_knights(id))
    end
  end
  return ("You're on the %s team with %d knight%s (order: %s). %s."):format(war[name].team,#mine,#mine==1 and "" or "s",o and o.mode or "follow",
    #reds>0 and table.concat(reds,"; ") or "No Red Army near: /battle calls one")
end
-- A player's AI builder fights beside them. As a soldier (no knights of theirs up, or the
-- Red Army right on them) it goes for the closest foe with its sword; as a commander it
-- stays by them behind the knights and lobs cannonballs, the Red Commander first. Told to
-- fix the castle (repairs[name]), it mends it instead (mend, below), fighting only a foe
-- right on it. Returns nil with no foe near, else {role="soldier"|"commander"|"repair",
-- to=where to walk (nil: stand), say=what it says taking that role}.
local repairs={} -- player name -> {say=their builder's voice}: their builder mends the castle
local mend -- (below, the Siege Castle)
local function bot_fight(player,bot)
  local name=player:get_player_name()
  if not war[name] then return end
  local BOT={_team=team_of(name)}
  local pp,bp=player:get_pos(),bot:get_pos()
  local foe,fd=find_foe(BOT,bp,16,pp)
  local st=bot:get_luaentity()
  local t=now()
  local function strike(f)
    face(bot,vector.subtract(f:get_pos(),bp))
    -- A knight's blow for players (it can't be hurt back), its sword for knights.
    local move=f:is_player() and "knight" or "sword"
    if (st._swung or 0)+MOVES[move].cool*1.5<t then st._swung=t; hit(f,bot,move,nil,BOT._team) end
  end
  if repairs[name] then
    local near=find_foe(BOT,bp,2)
    if near then strike(near); return {role="soldier"} end
    local r=mend(name,bot)
    if r then return r end
  end
  if not foe then return end
  local close=find_foe(BOT,bp,4,pp)
  local role=(#blue_knights(name)==0 or close) and "soldier" or "commander"
  if role=="soldier" then
    foe,fd=close or foe,close and vector.distance(bp,close:get_pos()) or fd
    if fd<2 then strike(foe); return {role=role} end
    return {role=role,to=foe:get_pos()}
  end
  local near=find_foe(BOT,bp,2)
  if near then strike(near); return {role=role} end
  local aim=find_foe(BOT,bp,20,nil,"commander") or foe
  face(bot,vector.subtract(aim:get_pos(),bp))
  if (st._lobbed or 0)+2.5<t then st._lobbed=t; lob(vector.offset(bp,0,2,0),aim,bot,BOT._team) end
  if flat_dist(bp,pp)>4 then return {role=role,to=pp} end
  return {role=role}
end
-- Fills name's blue knights up to KNIGHTS in a ring round them; returns how many came.
local function reinforce(name,player)
  local n=KNIGHTS-#blue_knights(name)
  if n<=0 then return 0 end
  local p=player:get_pos()
  for i=1,n do
    local a=i*2*math.pi/n
    local g=ground_at(math.floor(p.x+math.cos(a)*2+.5),p.y,math.floor(p.z+math.sin(a)*2+.5))
    if g then spawn_knight(g,team_of(name),{owner=name,yaw=player:get_look_horizontal()}) end
  end
  return n
end
-- An order with nobody to follow it calls up a squad first ("protect me" with no knights).
local function first_knights(name,player)
  if #blue_knights(name)>0 then return "" end
  local n=reinforce(name,player)
  return n>0 and " ("..n.." knights came to help!)" or ""
end
local function command(name,text,say,not_order)
  local player=C.get_player_by_name(name)
  local s=war[name]
  if not player or not s then return false end
  local low=text:lower()
  local who=label(player)
  if low:find("^help") or low:find("orders?%?") or low:find("what can") or low=="" then
    say("Ready for orders, "..who.."! Say: charge, attack the commander, flank left/right, hold, guard me, follow, retreat, more knights, status, or (in the Siege Castle) fix the holes.")
    return true
  end
  if low:find("status") or low:find("how are we") or low:find("situation") or low:find("how many") then
    say(status(name,player)); return true
  end
  -- "fix the holes", "repair the wall": their builder mends the Siege Castle.
  if (low:find("fix") or low:find("repair") or low:find("mend") or low:find("patch") or low:find("고쳐") or low:find("수리")) and
     (low:find("hole") or low:find("wall") or low:find("castle") or low:find("gate") or low:find("crack") or low:find("구멍") or low:find("성")) and
     brickcraft.war.castle() and brickcraft.world_at(player:get_pos())==brickcraft.war.castle() then
    repairs[name]={say=say}
    say("On it, "..who.."! I'll mend the castle's walls, cracks and holes first.")
    return true
  end
  if low:find("more knights") or low:find("reinforce") or low:find("recruit") or low:find("지원") then
    local n=reinforce(name,player)
    if n<=0 then say("You already have "..KNIGHTS.." knights, "..who.."!"); return true end
    say("Reinforcements! "..n.." more knight"..(n==1 and "" or "s").." for "..who..".")
    return true
  end
  local o=parse_order(low)
  if o then
    blue_orders[name]=o
    say(announce(o,who)..first_knights(name,player))
    return true
  end
  local ask=brickcraft.ai and brickcraft.ai.ask
  if not ask then
    if not_order then return false end
    say("I didn't catch that order, "..who..". Try: charge, flank left, hold, guard me, retreat."); return true
  end
  ask(ORDER_SYSTEM..[[


You are the commander of ]]..who..[['s blue knights. Turn what they just said into an order. If it isn't about the battle at all (a building request, or a question about something else), answer {"mode": "none"}.]],
    ("%s has %d/10 hearts. %s\n%s says: %s"):format(who,s.hp,status(name,player),who,text),function(reply)
      if type(reply)=="table" and reply.mode=="none" then
        if not_order then not_order() else say("That's not an order I know, "..who..".") end
        return
      end
      if reply==nil then
        -- Claude is busy (one request at a time): building words still go to the builder.
        if not_order and (low:find("build") or low:find("make") or low:find("지어")) then return not_order() end
        say("My radio's busy, "..who.."! Give me a simple order: charge, flank left, hold, guard me, retreat.")
        return
      end
      local ord=clean_order(reply)
      if not ord or not war[name] then say("I didn't catch that order, "..who..". Try: charge, flank left, hold, guard me, retreat."); return end
      blue_orders[name]=ord
      local came=first_knights(name,player)
      say((type(reply.say)=="string" and reply.say~="" and reply.say:sub(1,140) or announce(ord,who))..came)
    end,function(r) return type(r)=="table" and (r.mode=="none" or clean_order(r)~=nil) end)
  return true
end
-- /orders works without an AI builder too.
C.register_chatcommand("orders",{params="<order>",description="War mode: order your blue knights (charge, flank left, hold, guard me, retreat, status)",
  func=function(name,param)
    if not war[name] then return false,"Start war mode first: /war" end
    command(name,param or "",function(t) C.chat_send_player(name,C.colorize("#8fd0ff","<Knights' commander> ")..t) end)
    return true
  end})

-- The sword, cannon, boot or bow each player holds shows in their right hand, for everyone.
-- An attached object is drawn in its parent's scale, and players are drawn 10 times their
-- mesh (visual_size 10): its size and place are a tenth of what they look like (else it
-- floats, giant, over their head).
local SHOWN={["brickcraft:sword"]=true,["brickcraft:cannon"]=true,["brickcraft:boot"]=true,["brickcraft:bow"]=true}
C.register_entity(":brickcraft:held",{
  initial_properties={visual="wielditem",visual_size={x=.03,y=.03},physical=false,pointable=false,static_save=false},
  on_step=function(self) if not self.object:get_attach() then self.object:remove() end end,
})
local function show_held(player,s)
  local item=player:get_wielded_item():get_name()
  if not SHOWN[item] then item=nil end
  if item==s.held_item and (not item or s.held and s.held:get_pos()) then return end
  if s.held then s.held:remove(); s.held=nil end
  s.held_item=item
  if not item then return end
  local obj=C.add_entity(player:get_pos(),"brickcraft:held")
  if not obj then return end
  obj:set_properties({wield_item=item,textures={item}})
  obj:set_attach(player,"",{x=-.41,y=.62,z=.15},{x=-90,y=0,z=0})
  s.held=obj
end
local held_timer=0
C.register_globalstep(function(dt)
  held_timer=held_timer+dt
  if held_timer<.2 then return end
  held_timer=0
  for name,s in pairs(war) do
    local pl=C.get_player_by_name(name)
    if pl then show_held(pl,s) end
  end
end)

-- /team: blue (everyone's, against the Red Army) or green (against the blue players too).
-- Your knights change sides with you.
C.register_chatcommand("team",{params="blue|green",description="War mode: pick your team; blue and green fight each other",
  func=function(name,param)
    local s=war[name]
    if not s then return false,"Start war mode first: /war" end
    local t=param:lower():match("%a+")
    if not TEAMS[t or ""] then return true,"You're on the "..s.team.." team. /team green or /team blue to switch." end
    if t==s.team then return true,"You're on the "..t.." team already." end
    s.team=t
    for _,k in ipairs(blue_knights(name)) do k._team=t; dress(k) end
    local pl=C.get_player_by_name(name)
    if pl then update_hud(pl) end
    tell_war(label(pl).." joined the "..t.." team!")
    return true
  end})

-- Piles of cannonballs turn up 5 to 14 blocks from each player in war (3 near them at most);
-- a Red Army gives up when nobody in war has been near it for 30 seconds.
local supply_timer=0
C.register_globalstep(function(dt)
  supply_timer=supply_timer+dt
  if supply_timer<3 then return end
  supply_timer=0
  for name,s in pairs(war) do
    local pl=C.get_player_by_name(name)
    local p=pl and pl:get_pos()
    -- Out of the fight a while, hearts come back slowly (and with them, speed).
    if pl and s.hp<MAX_HP and now()-(s.hurt or 0)>HEAL_AFTER then s.hp=s.hp+1; update_hud(pl) end
    if p then
      local near=0
      for ent in pairs(piles) do
        local q=ent.object:get_pos()
        if q and vector.distance(p,q)<16 then near=near+1 end
      end
      if near<3 then
        local a,r=math.random()*2*math.pi,5+math.random()*9
        local g=ground_at(math.floor(p.x+math.cos(a)*r+.5),p.y,math.floor(p.z+math.sin(a)*r+.5))
        if g then drop_ammo(g) end
      end
    end
  end
  for id,army in pairs(armies) do
    if (army.next_plan or 0)<now() then army.next_plan=now()+15; plan_red(army,id) end
    local bp=army.boss.object:get_pos()
    local seen=false
    if bp then
      for name in pairs(war) do
        local pl=C.get_player_by_name(name)
        if pl and vector.distance(pl:get_pos(),bp)<48 then seen=true end
      end
    end
    if seen then army.alone=nil else army.alone=(army.alone or 0)+3 end
    if not bp or (army.alone or 0)>=30 then
      armies[id]=nil
      for ent in pairs(things) do if ent._army==id and ent.object:get_pos() then things[ent]=nil; ent.object:remove() end end
    end
  end
end)

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
  war[name]={team="blue",hp=MAX_HP,lives=LIVES,kos=0,ammo=AMMO_START,shield=now()+SHIELD,last={},hud={}}
  update_hud(player)
  brickcraft.refresh_inventory(player)
  tell_war(label(player).." is in the war! ("..(function()
    local n=0 for _ in pairs(war) do n=n+1 end return n end)().." playing)")
  return true
end
function stop(player)
  local name=player:get_player_name()
  local s=war[name]
  if not s then unstash(player); return false end
  for _,id in pairs(s.hud) do player:hud_remove(id) end
  if s.held then s.held:remove() end
  war[name]=nil
  condition(player)
  blue_orders[name]=nil
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
    return true,"War mode! 1 Sword  2 Cannon (left click fires)  3 Boot  4 Blue Knight  5 Bow. /battle calls a Red Army. You have 3 lives; low on hearts you slow down, and hearts come back if you keep out of the fight. Only players in war can be hit; builds are safe. /war again to stop."
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
-- "Which world?". Coral cover walls on the baseplate east of the start spots, a row of
-- Brick Knights that stand up whenever someone is there (knights aren't saved), and the
-- Red Army's camp to the west: red ground where its armies turn up. Test worlds skip it
-- (but the war check).
local LAB_WALLS={{x=9,z0=-9,z1=-5},{x=9,z0=-1,z1=3},{x=13,z0=-6,z1=0}}
local LAB_KNIGHTS={{x=17,z=-8},{x=17,z=-4},{x=17,z=0},{x=19,z=-6},{x=19,z=-2}}
local LAB_CAMP,CAMP_R={x=-18,z=-6},3
C.register_node(":brickcraft:red_camp",{
  description="Red Army Camp",tiles={"brickcraft_baseplate.png^[colorize:#c23a2b:150"},
  groups={not_in_creative_inventory=1},diggable=false,is_ground_content=false,
})
local CAMP_GROUND={["brickcraft:baseplate"]=true,["brickcraft:grass"]=true,["brickcraft:dirt"]=true}
local function lab() for _,w in ipairs(brickcraft.worlds()) do if w.lab then return w end end end
local function build_lab(w)
  if not w.lab_built then
    for _,wall in ipairs(LAB_WALLS) do
      for z=wall.z0,wall.z1 do for y=0,1 do
        local pos={x=w.x+wall.x,y=y,z=w.z+z}
        if C.get_node(pos).name=="air" then C.set_node(pos,{name="brickcraft:coral"}) end
      end end
    end
  end
  -- The camp (added to War Labs made before it): the ground under it turns red.
  for dx=-CAMP_R,CAMP_R do for dz=-CAMP_R,CAMP_R do
    local g=ground_at(w.x+LAB_CAMP.x+dx,0,w.z+LAB_CAMP.z+dz)
    local under=g and {x=g.x,y=g.y-1,z=g.z}
    if under and CAMP_GROUND[C.get_node(under).name] then C.set_node(under,{name="brickcraft:red_camp"}) end
  end end
  w.lab_built,w.lab_camp=true,true; brickcraft.save_worlds()
  C.log("action","BrickCraft War Lab built at "..w.x..","..w.z)
end
C.after(0,function()
  if brickcraft.testing and not C.settings:get_bool("brickcraft_war_test",false) then return end
  local w=lab()
  if w then
    if w.built and not (w.lab_built and w.lab_camp) then
      C.emerge_area({x=w.x-22,y=-3,z=w.z-10},{x=w.x+20,y=2,z=w.z+20},function(_,_,r) if r==0 then build_lab(w) end end)
    end
    return
  end
  w=brickcraft.make_world("War Lab (experimental)","BrickCraft",build_lab)
  C.log("action","BrickCraft War Lab "..(w and "being made at "..w.x..","..w.z or "has no room"))
  if w then w.lab=true; brickcraft.save_worlds() end
end)
-- Siege Castle (experimental): a world made once, after the War Lab, with a stone castle in
-- the middle to hold against a Red Army of 52 knights. The castle's walls are rows 9 and 10
-- out from the center, y 0..4 (walk on top), battlements on row 10, corner towers 8..11
-- out, stairs up the inside of each wall and a gate in the south wall; inside, a keep and
-- two towers with stairs. Its cannons, in gaps of the battlements, need no cannonballs
-- and aim down; its archers (a blue garrison, new with each army) hold the battlements
-- and the tower tops and shoot at the Red Army. The Red Army comes from all
-- four sides, its Commander behind the north line, with a red cannon a side that cracks
-- the walls between it and its foes; four builders a side put up a siege tower, stairs
-- against the east and west walls up to the battlements. Each army finds the castle whole
-- again: cracks and holes mended, siege towers gone (bricks players put there stay).
local INNER={{x0=-2,x1=2,z0=5,z1=8},{x0=-7,x1=-5,z0=-6,z1=-4},{x0=5,x1=7,z0=-6,z1=-4}}
local STAIRS={{x=-7,z=8,dx=1,dz=0},{x=7,z=-8,dx=-1,dz=0},{x=8,z=-7,dx=0,dz=1},{x=-8,z=7,dx=0,dz=-1}}
local function castle_cell(x,y,z)
  local ax,az=math.abs(x),math.abs(z)
  local m=math.max(ax,az)
  if ax>=8 and ax<=11 and az>=8 and az<=11 then
    if y<=6 then return "brickcraft:castle_wall" end
    if y==7 and (ax==11 or az==11) and (x+z)%2==0 then return "brickcraft:castle_wall" end
    return nil
  end
  if m==9 or m==10 then
    if y<=4 then return (z<=-9 and ax<=1 and y<=2) and "brickcraft:castle_gate" or "brickcraft:castle_wall" end
    if y==5 and m==10 and (ax==10 and z or x)%2==0 then return "brickcraft:castle_wall" end
    return nil
  end
  -- Inside: the keep against the north wall and two towers in the south of the courtyard
  -- (solid to y 6, battlements round the top), each tower with stairs up its north side.
  for _,b in ipairs(INNER) do
    if x>=b.x0 and x<=b.x1 and z>=b.z0 and z<=b.z1 then
      if y<=6 then return "brickcraft:castle_wall" end
      if y==7 and (x==b.x0 or x==b.x1 or z==b.z0 or z==b.z1) and (x+z)%2==0 then return "brickcraft:castle_wall" end
      return nil
    end
  end
  if z==-3 and ax>=2 and ax<=7 and y<=ax-2 then return "brickcraft:castle_wall" end
  for _,st in ipairs(STAIRS) do
    for i=0,4 do
      if x==st.x+st.dx*i and z==st.z+st.dz*i and y<=i then return "brickcraft:castle_wall" end
    end
  end
end
-- The sides (n: outward, a: along the wall), the castle's cannons (in gaps, 5 along) and
-- the siege towers: stairs one block wide along the wall, the top step by a gap.
local SIDES={north={n={x=0,z=1},a={x=1,z=0}},south={n={x=0,z=-1},a={x=1,z=0}},
  east={n={x=1,z=0},a={x=0,z=1}},west={n={x=-1,z=0},a={x=0,z=1}}}
-- The Red Army comes from the south (the gate) and the east: a moat, 5 wide and 3 deep,
-- runs round the north and west from 12 out (knights that fall in can't climb out; players
-- can swim). Siege towers: stairs along the east and south walls, the top step by a gap.
local ATTACK={"south","east"}
local SIEGE_TOWERS={east={x=11,z=-7,dz=1,stand={x=13,z=-5}},south={x=3,z=-11,dx=1,stand={x=5,z=-13}}}
local function moat(x,z)
  local m=math.max(math.abs(x),math.abs(z))
  return m>=12 and m<=16 and (z>=12 or x<=-12)
end
local function moat_side(x,z)
  if moat(x,z) then return false end
  for dx=-1,1 do for dz=-1,1 do if moat(x+dx,z+dz) then return true end end end
  return false
end
C.register_node(":brickcraft:water",{description="Moat Water",drawtype="liquid",
  tiles={{name="brickcraft_sky.png^[colorize:#2a6fb8:120",backface_culling=false}},use_texture_alpha="blend",
  paramtype="light",walkable=false,pointable=false,diggable=false,buildable_to=true,is_ground_content=false,
  liquidtype="source",liquid_alternative_source="brickcraft:water",liquid_alternative_flowing="brickcraft:water",
  liquid_range=0,liquid_renewable=false,liquid_viscosity=1,drowning=0,post_effect_color={a=110,r=30,g=90,b=170},
  groups={not_in_creative_inventory=1,water=1}})
local function castle() for _,w in ipairs(brickcraft.worlds()) do if w.castle then return w end end end
local OURS={["brickcraft:siege_tower"]=true}
for from,to in pairs(CRACKS) do OURS[from]=true end
-- Someone inside the castle's stone (it grew round where they stood, or they left the
-- game there before it did) sees only black: they go to their start spot.
local function unstick(player)
  local w=castle()
  local p=player:get_pos()
  if not w or brickcraft.world_at(p)~=w then return false end
  for dy=0,1 do
    local name=C.get_node(vector.round(vector.offset(p,0,.5+dy,0))).name
    if OURS[name] or name=="brickcraft:castle_wall" or name=="brickcraft:castle_gate" then
      player:set_pos(brickcraft.home_pos(player,w)); return true
    end
  end
  return false
end
C.register_on_joinplayer(function(player)
  C.after(1,function() if player:is_player() then unstick(player) end end)
end)
local function build_castle(w,first)
  local vm=C.get_voxel_manip()
  local emin,emax=vm:read_from_map({x=w.x-24,y=-4,z=w.z-24},{x=w.x+24,y=8,z=w.z+24})
  local area=VoxelArea:new({MinEdge=emin,MaxEdge=emax})
  local data=vm:get_data()
  local air=C.get_content_id("air")
  local ours={}
  for name in pairs(OURS) do ours[C.get_content_id(name)]=true end
  -- The first time, the workshop's stacks and arch go.
  for z=-24,24 do for x=-24,24 do for y=0,8 do
    local i=area:index(w.x+x,y,w.z+z)
    local want=castle_cell(x,y,z)
    if want and (first or data[i]==air or ours[data[i]]) then data[i]=C.get_content_id(want)
    elseif not want and (first or ours[data[i]]) then data[i]=air end
  end end end
  -- The moat: water y -3..-1 on a baseplate floor, baseplate sides under the ground.
  local water,plate=C.get_content_id("brickcraft:water"),C.get_content_id("brickcraft:baseplate")
  for z=-17,17 do for x=-17,17 do
    local m,side=moat(x,z),moat_side(x,z)
    for y=-4,-1 do
      local i=area:index(w.x+x,y,w.z+z)
      if m then data[i]=y==-4 and plate or water
      elseif side and y<=-2 then data[i]=plate end
    end
  end end
  -- Light is worked out again with the sky above loaded too: on a fresh start only these
  -- blocks are, and lighting them alone left the castle pitch black.
  vm:set_data(data); vm:write_to_map(false)
  C.fix_light({x=w.x-24,y=-4,z=w.z-24},{x=w.x+24,y=31,z=w.z+24})
  for _,pl in ipairs(C.get_connected_players()) do unstick(pl) end
  if first or not w.castle_lit then w.castle_built,w.castle_moat,w.castle_lit=true,true,true; brickcraft.save_worlds() end
end
-- A builder's turn: by its stand it puts the next missing step of its siege tower every
-- 4 seconds, fighting only who comes right up to it. Done, it joins the fight.
build=function(self,p)
  local foe,fd=find_foe(self,p,1.8)
  if foe then swing(self,foe,p); return true end
  local b=self._build
  for _,c in ipairs(b.cells) do
    if C.get_node(c).name~="brickcraft:siege_tower" then
      if flat_dist(p,b.stand)>1.2 then walk(self,b.stand); return true end
      face(self.object,vector.subtract(c,p))
      self._still=true
      local t=now()
      if (self._built or 0)+TUNE.build_every<t and C.get_node(c).name=="air" then
        self._built=t
        C.set_node(c,{name="brickcraft:siege_tower"}); poof(vector.offset(c,0,-.5,0))
      end
      return true
    end
  end
  self._build=nil
end
-- Damage: castle cells cracked, or empty where the castle should be (bricks players put
-- in a hole stay). Mending puts one back whole.
local function castle_damage(w)
  local out={}
  for x=-11,11 do for z=-11,11 do for y=0,8 do
    local want=castle_cell(x,y,z)
    if want then
      local pos={x=w.x+x,y=y,z=w.z+z}
      local name=C.get_node(pos).name
      if name~=want and (name=="air" or CRACKS[name]) then out[#out+1]=pos end
    end
  end end end
  return out
end
-- A builder told to fix the castle: to the closest damage, standing on the ground toward
-- the courtyard, and from within 4.5 a block every 0.6 seconds. All done, it says so.
mend=function(name,bot)
  local w=castle()
  local bp=bot:get_pos()
  local rep=repairs[name]
  if not w or brickcraft.world_at(bp)~=w then repairs[name]=nil; return end
  local t=now()
  if not rep.list or (rep.scanned or 0)+5<t then rep.list,rep.scanned=castle_damage(w),t end
  local best,bd
  for i=#rep.list,1,-1 do
    local pos=rep.list[i]
    local name_now=C.get_node(pos).name
    if name_now~="air" and not CRACKS[name_now] or name_now==castle_cell(pos.x-w.x,pos.y,pos.z-w.z) then table.remove(rep.list,i)
    else
      local d=vector.distance(bp,pos)
      if not bd or d<bd then best,bd=pos,d end
    end
  end
  if not best then
    repairs[name]=nil
    rep.say("The castle's all fixed!")
    return
  end
  local eye=vector.offset(bp,0,1.4,0)
  if vector.distance(eye,best)<=4.5 then
    face(bot,vector.subtract(best,bp))
    if (rep.at or 0)+.6<t then
      rep.at=t
      C.set_node(best,{name=castle_cell(best.x-w.x,best.y,best.z-w.z)}); poof(vector.offset(best,0,-.5,0))
    end
    return {role="repair",say="Mending the castle!"}
  end
  -- Stand 2.5 nearer the middle than the damage, on whatever is there.
  local r={x=best.x-w.x,z=best.z-w.z}
  local len=math.max(math.sqrt(r.x*r.x+r.z*r.z),.1)
  local k=math.max(0,len-2.5)/len
  local g=ground_at(math.floor(w.x+r.x*k+.5),best.y,math.floor(w.z+r.z*k+.5))
  return {role="repair",to=g or best,say="Mending the castle!"}
end
-- The castle's archers: 8 in gaps of the battlements on the two sides the Red Army comes
-- from (two where the siege towers reach), 2 on each inner tower and the keep.
local ARCHERS={}
for _,key in ipairs(ATTACK) do local s=SIDES[key]; for _,t in ipairs({-7,-3,3,7}) do
  ARCHERS[#ARCHERS+1]={x=s.n.x*10+s.a.x*t,y=5,z=s.n.z*10+s.a.z*t,yaw=math.atan2(-s.n.x,s.n.z)}
end end
for _,a in ipairs({{-6,-5},{6,-5},{-1,6},{1,6}}) do ARCHERS[#ARCHERS+1]={x=a[1],y=7,z=a[2],yaw=math.pi} end
local function garrison(w)
  for ent in pairs(things) do
    if ent._archer==w.id and ent.object:get_pos() then things[ent]=nil; ent.object:remove() end
  end
  for _,a in ipairs(ARCHERS) do
    local k=spawn_knight({x=w.x+a.x,y=a.y,z=w.z+a.z},"blue",{yaw=a.yaw})
    if k then k._archer=w.id; dress(k) end
  end
end
local function siege_army(w)
  build_castle(w)
  local c={x=w.x,y=0,z=w.z}
  local function at(r) return ground_at(math.floor(w.x+r.x+.5),0,math.floor(w.z+r.z+.5)) end
  -- The Commander stays back at the south edge, out of the archers' reach.
  local id=spawn_army(at({x=0,z=-26}) or vector.offset(c,0,0,-26),c,w,{})
  if not id then return end
  armies[id].stay=true
  garrison(w)
  for _,key in ipairs(ATTACK) do
    local s=SIDES[key]
    local yaw=math.atan2(s.n.x,-s.n.z) -- facing the castle
    local tw=SIEGE_TOWERS[key]
    local b=tw and {cells={},stand={x=w.x+tw.stand.x,y=0,z=w.z+tw.stand.z}}
    if tw then
      for i=0,4 do for y=0,i do b.cells[#b.cells+1]={x=w.x+tw.x+(tw.dx or 0)*i,y=y,z=w.z+tw.z+(tw.dz or 0)*i} end end
    end
    for i=1,TUNE.siege_per_side do
      local t=-9+(i-1)*18/math.max(1,TUNE.siege_per_side-1)
      local out=i%2==0 and 23 or 21
      local g=at({x=s.n.x*out+s.a.x*t,z=s.n.z*out+s.a.z*t})
      local k=g and spawn_knight(g,"red",{army=id,yaw=yaw})
      if k and b and i>=5 and i<=8 then k._build=b end
    end
    for _,t in ipairs({-5,5}) do
      local g=at({x=s.n.x*19+s.a.x*t,z=s.n.z*19+s.a.z*t})
      if g then spawn_red_cannon(g,yaw,id) end
    end
  end
end
-- War worlds made once for everyone: the War Lab and the Siege Castle. While someone in
-- war is in one, a Red Army comes (a new one 30 s after the last is beaten).
local WAR_WORLDS={
  {find=lab,ready="lab_built",welcome="fight the Red Army coming from its red camp in the west. The gray Practice Targets just stand there; your own blue knights come from slot 4 (right click the ground).",
    army=function(w) spawn_army({x=w.x+LAB_CAMP.x,y=0,z=w.z+LAB_CAMP.z},{x=w.x,y=0,z=w.z},w) end},
  {find=castle,ready="castle_built",welcome="hold the castle against a Red Army of 50 coming from the hills! Stairs inside each wall lead up; the cannons in the battlements need no cannonballs (right click: aim and fire, down too), and 5 is your Bow. Knock out the Red Commander to win.",
    army=siege_army},
}
local lab_timer,welcomed=0,{}
C.register_globalstep(function(dt)
  lab_timer=lab_timer+dt
  if lab_timer<2 then return end
  lab_timer=0
  for _,kind in ipairs(WAR_WORLDS) do
    local w=kind.find()
    if w and w[kind.ready] then
      local here,fighting=false,false
      for _,p in ipairs(C.get_connected_players()) do
        local name=p:get_player_name()
        if brickcraft.world_at(p:get_pos())==w then
          here=true
          fighting=fighting or war[name]~=nil
          if welcomed[name]~=w then
            C.chat_send_player(name,C.colorize("#ff9a76",w.name..": "..(war[name] and "" or "type /war, then ")..kind.welcome))
          end
          welcomed[name]=w
        elseif welcomed[name]==w then welcomed[name]=nil end
      end
      local camp=false
      for _,army in pairs(armies) do if army.lab==w then camp=true end end
      if fighting and not camp and next_lab_army<now() then kind.army(w) end
      if here and w.lab then
        local up=0
        for ent in pairs(things) do if ent._lab and not ent._team then up=up+1 end end
        if up==0 then
          for _,k in ipairs(LAB_KNIGHTS) do
            spawn_knight({x=w.x+k.x,y=0,z=w.z+k.z},nil,{lab=true,yaw=math.pi/2}) -- facing west, toward the walls
          end
        end
      end
      if here and w.castle then
        local up=0
        for ent in pairs(things) do if ent._castle==w.id and ent.object:get_pos() then up=up+1 end end
        if up==0 then
          for _,s in pairs(SIDES) do for _,t in ipairs({-5,5}) do
            local obj=C.add_entity({x=w.x+s.n.x*10+s.a.x*t,y=4.5,z=w.z+s.n.z*10+s.a.z*t},"brickcraft:cannon")
            if obj then obj:set_yaw(math.atan2(-s.n.x,s.n.z)); obj:get_luaentity()._castle=w.id end
          end end
        end
      end
    end
  end
end)
-- /resetcastle: the castle as it was first made (bricks in its square go too), its Red
-- Army sent away, the next 15 seconds later.
local function reset_castle(w)
    for id,army in pairs(armies) do
      if army.lab==w then
        armies[id]=nil
        for ent in pairs(things) do if ent._army==id and ent.object:get_pos() then things[ent]=nil; ent.object:remove() end end
      end
    end
    for ent in pairs(things) do
      if ent._archer==w.id and ent.object:get_pos() then things[ent]=nil; ent.object:remove() end
    end
    build_castle(w,true)
    next_lab_army=now()+15
end
C.register_chatcommand("resetcastle",{description="Siege Castle: put the castle back as new and send the Red Army away",
  func=function(name)
    local p=C.get_player_by_name(name)
    local w=castle()
    if not p or not w or brickcraft.world_at(p:get_pos())~=w then return false,"Go to the Siege Castle world first (Which world?)." end
    reset_castle(w)
    tell_war(label(p).." reset the Siege Castle. The next Red Army comes in 15 seconds.")
    return true,"The castle is new again."
  end})
C.after(0,function()
  if brickcraft.testing and not C.settings:get_bool("brickcraft_war_test",false) and
    not C.settings:get_bool("brickcraft_siege_test",false) and not C.settings:get_bool("brickcraft_siege_sim",false) then return end
  local w=castle()
  if w then
    if w.built and not (w.castle_built and w.castle_moat and w.castle_lit) then
      -- (a castle from before the moat, or left dark by it, keeps what players built: it
      -- gets the moat and its light worked out again)
      C.emerge_area({x=w.x-24,y=-4,z=w.z-24},{x=w.x+24,y=31,z=w.z+24},function(_,_,r) if r==0 then build_castle(w,not w.castle_built) end end)
    end
    return
  end
  w=brickcraft.make_world("Siege Castle (experimental)","BrickCraft",function(w) build_castle(w,true) end)
  C.log("action","BrickCraft Siege Castle "..(w and "being made at "..w.x..","..w.z or "has no room"))
  if w then w.castle=true; brickcraft.save_worlds() end
end)

brickcraft.war={unstick=unstick,tune=TUNE,reset_castle=reset_castle,siege_army=siege_army,garrison=garrison,castle_damage=castle_damage,army_size=army_size,lab=lab,castle=castle,castle_cell=castle_cell,shoot_arrow=shoot_arrow,start=start,stop=stop,hit=hit,fire=fire,fire_from=fire_from,max_hp=MAX_HP,
  spawn_knight=spawn_knight,_things=function() return things end,command=command,
  orders=function(name) return blue_orders[name] end,bot_fight=bot_fight,plan_red=plan_red,spawn_army=spawn_army,battle=battle,armies=armies,drop_ammo=drop_ammo,
  on=function(player) return war[player:get_player_name()] end}
