-- Colonies: each player raises their own colony in a habitat, SimCity style. It starts
-- with a few creatures (5 bunnies in Bunnyland) and grows by domestication or births, which need
-- room (homes), food, water and safety. Creatures gather clovers (income per creature);
-- clovers buy structures from the shop. Bigger colonies reach new levels and rewards.
--
-- A variant opts in with def.colony = {start=5, max=60, clovers=40 (to start with),
-- income=0.1 (clovers a second per creature), birth=50 (seconds between births, before
-- nurseries), kit={[item id]=n} (given at the start), shop={{id,cost},...},
-- levels={{pop,name,reward},...}}. Structures are registered with H.register_structure.
return function(H)
local C=core
local now,flat=H.now,H.flat
local function rnd(a,b) return a+math.random()*(b-a) end
local function owner_of(p) return brickcraft.playing_as(p) or p:get_player_name() end
H.owner_of=owner_of
local function label_of(owner) return (brickcraft.styles[owner] or {}).label or owner end
H.label_of=label_of

------------------------------------------------------------------------------------------
-- Structures
------------------------------------------------------------------------------------------
H.structures={}
-- def: label, effect ("home", "nursery", "lookout"), capacity (homes), hideout (creatures
-- inside can't be reached), tiles, node_box, inventory_image, walkable, about (one line).
function H.register_structure(id,def)
  def.id,def.name=id,"brickcraft_habitat:"..id
  H.structures[id]=def
  local groups={habitat_structure=1,["habitat_"..def.effect]=1,habitat_hideout=def.hideout and 1 or nil}
  local box={type="fixed",fixed=def.node_box}
  C.register_node(def.name,{description=def.label..(def.about and "\n"..def.about or "")..
      "\nRight click with the separator: pick up",
    drawtype="nodebox",node_box=box,selection_box={type="fixed",fixed={-.5,-.5,-.5,.5,.5,.5}},
    collision_box=def.walkable~=false and box or nil,walkable=def.walkable~=false,
    tiles=def.tiles,paramtype="light",paramtype2="facedir",sunlight_propagates=true,groups=groups,
    inventory_image=def.inventory_image,wield_image=def.inventory_image,range=7,stack_max=99,
    drop=def.name,brickcraft_shape="habitat",
    after_place_node=function(pos,placer) H.claim(pos,placer) end,
    brickcraft_turn=function(pos,node,player)
      if not brickcraft.room_for(player,def.name) then return end
      C.remove_node(pos); brickcraft.give(player,def.name)
    end,
  })
end
-- Fence pieces: posts and rails that join each other, gates and bricks. They stand a
-- brick and a half tall to anything walking into them: higher than a creature or a
-- predator jumps (1.1), lower than a player does (2). A gate opens and closes with the
-- separator's right click (open, anything walks through); punch it to pick it up.
function H.register_fence(id,def)
  local name="brickcraft_habitat:"..id
  local post={-.12,-.5,-.12,.12,.5,.12}
  local rails=function(side)
    local r={front={-.05,0,-.5,.05,0,-.12},back={-.05,0,.12,.05,0,.5},left={-.5,0,-.05,-.12,0,.05},right={.12,0,-.05,.5,0,.05}}
    local b=r[side]
    return {{b[1],.15,b[3],b[4],.35,b[6]},{b[1],-.3,b[3],b[4],-.1,b[6]}}
  end
  local tall=function(side)
    local r={front={-.05,-.5,-.5,.05,1,-.12},back={-.05,-.5,.12,.05,1,.5},left={-.5,-.5,-.05,-.12,1,.05},right={.12,-.5,-.05,.5,1,.05}}
    return r[side]
  end
  local connects={"group:habitat_fence","group:brick"}
  local function pickup(pos,player)
    if not (player and player:is_player()) or not brickcraft.room_for(player,name) then return end
    C.remove_node(pos); brickcraft.give(player,name)
  end
  C.register_node(name,{description=def.label.."\nA brick and a half tall: bunnies can't hop out, wolves and lions can't hop in"..
      "\nRight click with the separator: pick up",
    drawtype="nodebox",paramtype="light",sunlight_propagates=true,tiles=def.tiles,
    inventory_image=def.inventory_image,wield_image=def.inventory_image,range=7,stack_max=999,
    node_box={type="connected",fixed=post,connect_front=rails("front"),connect_back=rails("back"),
      connect_left=rails("left"),connect_right=rails("right")},
    collision_box={type="connected",fixed={-.12,-.5,-.12,.12,1,.12},connect_front=tall("front"),connect_back=tall("back"),
      connect_left=tall("left"),connect_right=tall("right")},
    selection_box={type="fixed",fixed=post},connects_to=connects,
    groups={habitat_fence=1},drop=name,brickcraft_shape="habitat",
    brickcraft_turn=function(pos,node,player) pickup(pos,player) end})
  if not def.gate then return end
  local gname=name.."_gate"
  local function gate(open)
    return {description=def.label.." gate\nRight click with the separator: open / close\nPunch: pick up",
      drawtype="nodebox",paramtype="light",paramtype2="facedir",sunlight_propagates=true,tiles=def.tiles,
      inventory_image=def.gate_image,wield_image=def.gate_image,range=7,stack_max=99,
      node_box={type="fixed",fixed=open and {{-.5,-.5,-.06,-.38,.5,.06},{.38,-.5,-.06,.5,.5,.06},{-.5,-.3,-.5,-.4,.35,-.06}}
        or {{-.5,-.5,-.06,-.38,.5,.06},{.38,-.5,-.06,.5,.5,.06},{-.38,.15,-.04,.38,.35,.04},{-.38,-.3,-.04,.38,-.1,.04}}},
      collision_box={type="fixed",fixed=open and {{-.5,-.5,-.06,-.38,1,.06},{.38,-.5,-.06,.5,1,.06}} or {{-.5,-.5,-.06,.5,1,.06}}},
      selection_box={type="fixed",fixed={-.5,-.5,-.1,.5,.5,.1}},
      groups={habitat_fence=1,not_in_creative_inventory=open and 1 or nil},drop=gname,brickcraft_shape="habitat",
      brickcraft_turn=function(pos,node)
        C.swap_node(pos,{name=open and gname or gname.."_open",param2=node.param2})
      end,
      on_punch=function(pos,_,puncher) pickup(pos,puncher) end}
  end
  C.register_node(gname,gate(false))
  C.register_node(gname.."_open",gate(true))
end

-- Placed structures and sources belong to who placed them (their colony counts them).
function H.claim(pos,placer)
  if not (placer and placer.is_player and placer:is_player()) then return end
  local owner=owner_of(placer)
  local meta=C.get_meta(pos)
  meta:set_string("owner",owner)
  local def=C.registered_nodes[C.get_node(pos).name]
  local what=(def and def.description or ""):match("^[^\n]+") or ""
  if meta:get_string("infotext")=="" or not meta:get_string("infotext"):find(label_of(owner),1,true) then
    meta:set_string("infotext",label_of(owner).."'s "..what:lower()..(meta:get_string("infotext")~="" and "\n"..meta:get_string("infotext") or ""))
  end
end

-- What each owner has placed in a world: homes' room, nurseries, lookouts, food, water
-- (and where the homes and lookouts are). Counted at most every 2 s.
local tallies={}
function H.tally(w,fresh)
  local t=tallies[w.id]
  if t and not fresh and now()-t.at<2 then return t.by end
  local by={}
  local E=H.EDGE
  for _,q in ipairs(C.find_nodes_in_area({x=w.x-E,y=-2,z=w.z-E},{x=w.x+E,y=30,z=w.z+E},{"group:habitat_structure","group:habitat_source"})) do
    local owner=C.get_meta(q):get_string("owner")
    if owner~="" then
      local o=by[owner] or {cap=0,nursery=0,food=0,water=0,homes={},lookouts={}}
      by[owner]=o
      local name=C.get_node(q).name
      local id=name:match("^brickcraft_habitat:(.+)$")
      local s=H.structures[id]
      if s then
        if s.effect=="home" then o.cap=o.cap+(s.capacity or 4); o.homes[#o.homes+1]=q
        elseif s.effect=="nursery" then o.nursery=o.nursery+1
        elseif s.effect=="lookout" then o.lookouts[#o.lookouts+1]=q end
      elseif C.get_item_group(name,"habitat_food")>0 then o.food=o.food+1
      elseif C.get_item_group(name,"habitat_water")>0 then o.water=o.water+1 end
    end
  end
  tallies[w.id]={at=now(),by=by}
  return by
end
local EMPTY={cap=0,nursery=0,food=0,water=0,homes={},lookouts={}}

------------------------------------------------------------------------------------------
-- Colony state and status
------------------------------------------------------------------------------------------
function H.colony(w,owner)
  local st=H.state(w)
  st.colonies=st.colonies or {}
  st.colonies[owner]=st.colonies[owner] or {clovers=0,born=0,lost=0,best=0,losses={}}
  return st.colonies[owner]
end
local function level_of(v,best)
  local lv,i=v.colony.levels[1],1
  for k,l in ipairs(v.colony.levels) do if best>=l[1] then lv,i=l,k end end
  return lv,i
end
-- A win belongs to each player in this habitat and survives later losses/restarts.
function H.colony_progress(w,v,owner)
  local c=H.colony(w,owner)
  local pop=H.creature_count(w,owner)
  local changed=false
  if pop>(c.best or 0) then
    local before=level_of(v,c.best or 0)
    c.best=pop; changed=true
    local lv=level_of(v,pop)
    if lv~=before then
      c.clovers=(c.clovers or 0)+(lv[3] or 0)
      H.tell(w,label_of(owner).."'s colony is now a "..lv[2].."! +"..(lv[3] or 0).." clovers","#ffe27a")
    end
  end
  if v.colony.win_count and pop>=v.colony.win_count and not c.won then
    c.won=true; changed=true
    H.tell(w,label_of(owner).." wins! "..pop.." "..v.plural.." in their colony!","#ffe27a")
  end
  if changed then H.save(w) end
end

function H.colony_scores(w)
  local counts={}
  for owner in pairs(H.state(w).colonies or {}) do counts[owner]=0 end
  for _,p in ipairs(H.players_in(w)) do counts[owner_of(p)]=counts[owner_of(p)] or 0 end
  for ent in pairs(H.live) do
    local q=ent.object:get_pos()
    if q and not ent._dead and ent._owner and brickcraft.world_at(q)==w then
      counts[ent._owner]=(counts[ent._owner] or 0)+1
    end
  end
  local rows={}
  for owner,n in pairs(counts) do
    local c=(H.state(w).colonies or {})[owner]
    rows[#rows+1]={owner=owner,pop=n,won=c and c.won or false}
  end
  table.sort(rows,function(a,b) if a.pop~=b.pop then return a.pop>b.pop end return a.owner<b.owner end)
  return rows
end
function H.score_line(w,v)
  local out={}
  for _,r in ipairs(H.colony_scores(w)) do
    out[#out+1]=label_of(r.owner)..": "..r.pop..(v.colony.win_count and "/"..v.colony.win_count or "")..(r.won and " WON!" or "")
  end
  return "Players: "..table.concat(out,"  |  ")
end

-- Right click a wild animal, then explicitly welcome it into your colony.
local taming={}
function H.domesticate(ent,p)
  if H.actions_blocked and H.actions_blocked(p) then return false,"Rest until dawn to domesticate animals." end
  local q=ent.object:get_pos()
  local w,v=H.world_at(p:get_pos())
  if not q or ent._dead or ent._carried then return false,"That animal isn't available to domesticate." end
  if ent._owner then return false,"That animal already belongs to a colony." end
  if not (w and v.colony and ent._kind==v.creature and brickcraft.world_at(q)==w) then
    return false,"Domesticate wild animals in their habitat world."
  end
  if vector.distance(q,p:get_pos())>7 or not C.line_of_sight(vector.offset(p:get_pos(),0,.5,0),vector.offset(q,0,.2,0)) then
    return false,"Move closer to the wild animal, with nothing between you."
  end
  local owner=owner_of(p)
  if H.creature_count(w,owner)>=(v.colony.max or 60) then return false,"Your colony is full." end
  local c=H.colony(w,owner)
  if not c.start then
    c.start=vector.round(p:get_pos()); c.started=1; c.kit_given={}
    c.clovers=math.max(c.clovers or 0,v.colony.clovers or 40)
  end
  ent._owner=owner; ent._home_until=nil
  ent._follow,ent._follow_until=p:get_player_name(),now()+120
  ent:_dress()
  c.domesticated=(c.domesticated or 0)+1; c.gone=nil
  H.colony_progress(w,v,owner); H.save(w)
  return true,"This "..H.creatures[ent._kind].label:lower().." is now yours and follows you! Lead it home, then /colony stay."
end
function H.domestication_panel(ent,p)
  if ent._dead or ent._carried then return end
  taming[p:get_player_name()]=ent
  C.show_formspec(p:get_player_name(),"brickcraft_habitat:domesticate",
    "formspec_version[6]size[8,3.6]bgcolor[#142936;true]"..
    "label[.5,.6;Wild "..C.formspec_escape(H.creatures[ent._kind].label:lower()).."]"..
    "label[.5,1.2;Make it part of your colony. It gets your label and follows you.]"..
    "button_exit[.5,2.2;4,.8;domesticate;Domesticate & follow]button_exit[4.8,2.2;2.7,.8;cancel;Leave wild]")
end
C.register_on_player_receive_fields(function(p,formname,fields)
  if formname~="brickcraft_habitat:domesticate" then return end
  local name=p:get_player_name()
  local ent=taming[name]; taming[name]=nil
  if fields.domesticate and ent then
    local _,msg=H.domesticate(ent,p); C.chat_send_player(name,msg)
  end
  return true
end)
C.register_on_leaveplayer(function(p) taming[p:get_player_name()]=nil end)
-- How a colony is doing: pop, cap, happy (0-100), each need (0-1), advice, level name.
function H.colony_status(w,v,owner)
  local c=H.colony(w,owner)
  local t=H.tally(w)[owner] or EMPTY
  -- Wild food and water (clover, ponds) within 10 of where the colony started count too.
  if c.start then
    t=table.copy(t)
    for _,q in ipairs(C.find_nodes_in_area(vector.offset(c.start,-10,-2,-10),vector.offset(c.start,10,3,10),{"group:habitat_food","group:habitat_water"})) do
      if C.get_meta(q):get_string("owner")=="" then
        if C.get_item_group(C.get_node(q).name,"habitat_food")>0 then t.food=t.food+1 else t.water=t.water+1 end
      end
    end
  end
  local pop=H.creature_count(w,owner)
  local n=math.max(pop,1)
  local cfg=v.colony
  local food=math.min(1,t.food*(cfg.feeds or 4)/n)
  local water=math.min(1,t.water*(cfg.waters or 6)/n)
  local housing=math.min(1,t.cap/n)
  local recent={}
  for _,at in ipairs(c.losses or {}) do if now()-at<300 then recent[#recent+1]=at end end
  c.losses=recent
  local safety=math.max(0,1-#recent/4)
  local happy=math.floor(100*(.3*food+.2*water+.3*housing+.2*safety)+.5)
  local P=v.plural
  local advice
  if pop==0 then advice="Start a colony: /colony start (or the button)."
  elseif t.cap<=pop then advice="Homes full ("..pop.."/"..t.cap.."). /colony: buy or build a hutch, then place it (+4 room)."
  elseif food<1 then advice="Hungry: each carrot patch feeds "..(cfg.feeds or 4).." "..P..". Place more."
  elseif water<1 then advice="Thirsty: each water trough serves "..(cfg.waters or 6).." "..P..". Place more."
  elseif safety<1 then advice=#recent.." lost lately: fences two high, roofs, hutches and a lookout keep them safe."
  elseif happy<(cfg.happy or 60) then advice="Not happy enough to grow yet."
  elseif pop<2 then advice="One alone can't have babies."
  else advice="Happy and growing! Room for "..(t.cap-pop).." more." end
  local lv=level_of(v,c.best or 0)
  return {pop=pop,cap=t.cap,happy=happy,food=food,water=water,housing=housing,safety=safety,
    advice=advice,level=lv[2],nursery=t.nursery,lookouts=#t.lookouts,clovers=math.floor(c.clovers or 0),
    best=c.best or 0,lost=c.lost or 0,born=c.born or 0}
end
function H.colony_line(p,w,v)
  if not v.colony then return nil end
  local owner=owner_of(p)
  local s=H.colony_status(w,v,owner)
  local goal=v.colony.win_count and "/"..v.colony.win_count or ""
  local won=H.colony(w,owner).won and "  YOU WON!" or ""
  if s.pop==0 then return "Your "..v.plural..": 0"..goal..won.." · /colony start, or right click a wild animal to domesticate it." end
  return "Your "..v.plural..": "..s.pop..goal..won.." ("..s.level.."), homes "..s.cap.."  ·  happy "..s.happy..
    "%  ·  "..s.clovers.." clovers\n"..s.advice
end

------------------------------------------------------------------------------------------
-- Hooks the creatures use (init.lua): homes, hiding, lookouts, losses.
------------------------------------------------------------------------------------------
local function nearest(list,p,r)
  local best,bd
  for _,q in ipairs(list) do
    local d=flat(p,q)+math.abs(q.y-p.y)
    if d<r and (not bd or d<bd) then best,bd=q,d end
  end
  return best
end
-- A hutch to hide in with room left (its capacity), the owner's nearest, else anyone's.
local function room_in(q,self)
  local s=H.structures[(C.get_node(q).name:match("^brickcraft_habitat:(.+)$") or "")]
  local n=0
  for ent in pairs(H.live) do
    local e=ent.object:get_pos()
    if ent~=self and e and flat(e,q)<.8 and math.abs(e.y-q.y)<1 then n=n+1 end
  end
  return n<(s and s.capacity or 4)
end
local function free_home(list,p,r,self)
  local best,bd
  for _,q in ipairs(list) do
    local d=flat(p,q)+math.abs(q.y-p.y)
    if d<r and (not bd or d<bd) and room_in(q,self) then best,bd=q,d end
  end
  return best
end
function H.hideout_near(self,p)
  local w=brickcraft.world_at(p)
  local by=H.tally(w)
  local mine=self._owner and by[self._owner]
  local q=mine and free_home(mine.homes,p,24,self)
  if not q then
    for _,o in pairs(by) do q=q or free_home(o.homes,p,16,self) end
  end
  return q and vector.copy(q)
end
-- Where a colony creature stays near: its owner's nearest home, else where it started.
function H.home_of(self)
  if not self._owner then return nil end
  if self._home_until and now()<self._home_until then return self._home end
  local p=self.object:get_pos()
  local w=brickcraft.world_at(p)
  local o=H.tally(w)[self._owner]
  local c=H.variant_of(w) and H.colony(w,self._owner)
  -- Told where home is (/colony stay): the nearest hutch there, or that spot.
  if c and c.home then self._home=(o and nearest(o.homes,c.home,14)) or c.home
  else self._home=(o and nearest(o.homes,p,60)) or (c and c.start) end
  self._home_until=now()+5
  return self._home
end
-- A lookout of the owner's within 20 cells: predators are seen from 20 away.
function H.alert_of(self,p)
  if not self._owner then return nil end
  local o=H.tally(brickcraft.world_at(p))[self._owner]
  if o and nearest(o.lookouts,p,20) then return 20 end
end
local warned={}
-- Lookouts warn their owner when a predator comes near the colony.
local function lookout_watch(w)
  for owner,o in pairs(H.tally(w)) do
    for _,q in ipairs(o.lookouts) do
      for ent in pairs(H.hunters) do
        local hp=ent.object:get_pos()
        local key=owner..tostring(ent)
        if hp and flat(hp,q)<24 and not warned[key] then
          warned[key]=true
          local p=C.get_player_by_name(owner) or nil
          for _,pl in ipairs(H.players_in(w)) do
            if owner_of(pl)==owner then
              C.chat_send_player(pl:get_player_name(),C.colorize("#ffb0a0","Lookout: a "..
                H.predators[ent._kind].label:lower().." is near your colony!"))
            end
          end
        end
      end
    end
  end
end
function H.colony_lost(w,ent,how)
  local c=H.colony(w,ent._owner)
  c.lost=(c.lost or 0)+1
  c.losses=c.losses or {}; c.losses[#c.losses+1]=now()
  H.save(w)
  local def=H.creatures[ent._kind]
  H.tell(w,"Oh no! One of "..label_of(ent._owner).."'s "..(def and def.label:lower().."s" or "creatures").." "..
    (how or "was lost")..". "..H.creature_count(w,ent._owner).." left in the colony.","#ff9a8a")
end

------------------------------------------------------------------------------------------
-- Starting, growing, buying
------------------------------------------------------------------------------------------
-- A new colony of owner's at pos: its first creatures, its clovers. Returns how many.
function H.found_colony(w,v,owner,pos)
  local c=H.colony(w,owner)
  local pp=vector.round(pos)
  local made=0
  for i=1,v.colony.start do
    local a=i/v.colony.start*2*math.pi
    local x,z=math.floor(pp.x+math.cos(a)*1.5+.5),math.floor(pp.z+math.sin(a)*1.5+.5)
    local g=H.ground(x,z,pp.y+1) -- at the player's level (not on a roof over them)
    if g and H.spawn_creature(v.creature,{x=x,y=g+.1,z=z},{owner=owner}) then made=made+1 end
  end
  c.start={x=pp.x,y=pp.y,z=pp.z}
  c.started=(c.started or 0)+1
  c.clovers=math.max(c.clovers or 0,v.colony.clovers or 40)
  c.born=(c.born or 0)+made
  c.best=math.max(c.best or 0,made)
  c.losses={}; c.gone=nil
  c.kit_given={}
  for id in pairs(v.colony.kit or {}) do c.kit_given[id]=true end
  H.save(w)
  return made
end
-- Kit items added to the game after a colony started (the fence) come to its owner the
-- next time they're in the world. Colonies from before kit_given had the first kit.
local FIRST_KIT={hutch=true,carrot_patch=true,water_trough=true}
local function top_up(w,v,owner,c)
  if not c.started then return end
  c.kit_given=c.kit_given or table.copy(FIRST_KIT)
  for _,p in ipairs(H.players_in(w)) do
    if owner_of(p)==owner then
      local got={}
      for id,n in pairs(v.colony.kit or {}) do
        if not c.kit_given[id] then
          local left=brickcraft.give(p,"brickcraft_habitat:"..id.." "..n)
          if left:get_count()<n then
            c.kit_given[id]=true
            local d=C.registered_items["brickcraft_habitat:"..id]
            got[#got+1]=(n-left:get_count()).." "..((d and d.description or id):match("^[^\n]+"))
          end
          if not left:is_empty() then C.chat_send_player(p:get_player_name(),"Your bag is full: make room for the rest of your colony kit.") end
        end
      end
      if #got>0 then
        table.sort(got); H.save(w)
        C.chat_send_player(p:get_player_name(),C.colorize("#ffd27a","New for your colony: "..table.concat(got,", ")..
          ". It's in your bag (I). Ring your colony with fence, hutches, carrots and water inside."))
      end
    end
  end
end
function H.start_colony(p)
  if H.actions_blocked and H.actions_blocked(p) then return false,"Rest until dawn to start a colony." end
  local w,v=H.world_at(p:get_pos())
  if not w then return false,"Colonies are started in a habitat world (like Bunnyland)." end
  if not v.colony then return false,v.label.." has no colonies." end
  local owner=owner_of(p)
  local c=H.colony(w,owner)
  local pop=H.creature_count(w,owner)
  if pop>0 then return false,"You already have a colony of "..pop.." "..v.plural.."." end
  local made=H.found_colony(w,v,owner,p:get_pos())
  local got={}
  for id,n in pairs(v.colony.kit or {}) do
    brickcraft.give(p,"brickcraft_habitat:"..id.." "..n)
    local d=C.registered_items["brickcraft_habitat:"..id]
    got[#got+1]=n.." "..((d and d.description or id):match("^[^\n]+"))
  end
  table.sort(got)
  H.tell(w,label_of(owner).." started a colony of "..made.." "..v.plural.."!","#ffd6e8")
  return true,"Your colony of "..made.." is here. You got "..table.concat(got,", ")..
    ". Place hutches (homes), food and water near them; /colony shows how it's doing."
end
-- Herding: your colony's creatures within 30 follow you (2 minutes), or stop and make
-- where you stand their home.
local function mine_near(p,r)
  local owner,pp,out=owner_of(p),p:get_pos(),{}
  for ent in pairs(H.live) do
    local q=ent.object:get_pos()
    if q and ent._owner==owner and vector.distance(q,pp)<r then out[#out+1]=ent end
  end
  return out
end
function H.call(p)
  if H.actions_blocked and H.actions_blocked(p) then return false,"Rest until dawn to call your colony." end
  local w,v=H.world_at(p:get_pos())
  if not (w and v.colony) then return false,"Call your colony in a habitat world." end
  local list=mine_near(p,30)
  for _,ent in ipairs(list) do ent._follow,ent._follow_until=p:get_player_name(),now()+120 end
  if #list==0 then return false,"None of your "..v.plural.." are within 30 blocks." end
  return true,#list.." "..v.plural.." follow you (2 minutes). Lead them through the gate, then /colony stay."
end
function H.stay(p)
  if H.actions_blocked and H.actions_blocked(p) then return false,"Rest until dawn to settle your colony." end
  local w,v=H.world_at(p:get_pos())
  if not (w and v.colony) then return false,"Not in a habitat world." end
  local name=p:get_player_name()
  local n=0
  for _,ent in ipairs(mine_near(p,60)) do
    if ent._follow==name then ent._follow=nil; n=n+1 end
    ent._home_until=nil
  end
  local c=H.colony(w,owner_of(p))
  c.home=vector.round(p:get_pos()); H.save(w)
  return true,(n>0 and n.." stopped. " or "").."Your colony's home is here now: they stay near it (or your nearest hutch here)."
end
function H.buy(p,id)
  if H.actions_blocked and H.actions_blocked(p) then return false,"Rest until dawn to use the shop." end
  local w,v=H.world_at(p:get_pos())
  if not (w and v.colony) then return false,"Buy things in a habitat with colonies." end
  local cost,count
  for _,e in ipairs(v.colony.shop) do if e[1]==id then cost,count=e[2],e[3] or 1 end end
  if not cost then return false,"That isn't for sale here." end
  local c=H.colony(w,owner_of(p))
  if (c.clovers or 0)<cost then return false,"That costs "..cost.." clovers; you have "..math.floor(c.clovers or 0).."." end
  local item="brickcraft_habitat:"..id
  if not brickcraft.room_for(p,item.." "..count) then return false,"No room in your bag." end
  c.clovers=c.clovers-cost; H.save(w)
  brickcraft.give(p,item.." "..count)
  local d=C.registered_items[item]
  local what=((d and d.description or id):match("^[^\n]+")):lower()
  return true,"Bought "..(count>1 and count.." "..what.."s" or "a "..what).." for "..cost.." clovers."
end
-- Build housing from collected basic bricks as an alternative to spending clovers.
function H.craft_hutch(p)
  if H.actions_blocked and H.actions_blocked(p) then return false,"Rest until dawn to build a hutch." end
  local w,v=H.world_at(p:get_pos())
  if not (w and v.colony and v.colony.hutch_bricks) then return false,"Build bunny hutches in Bunnyland." end
  local cost=v.colony.hutch_bricks
  local plan,left={},cost
  for _,color in ipairs(brickcraft.colors) do
    local item="brickcraft:"..color
    local n=math.min(left,brickcraft.count_of(p,item))
    if n>0 then plan[#plan+1]={item=item,count=n}; left=left-n end
    if left==0 then break end
  end
  if left>0 then return false,"A hutch needs "..cost.." basic 2 x 2 bricks, in any mix of colors. Collect more bricks first." end
  if not brickcraft.room_for(p,"brickcraft_habitat:hutch") then return false,"Make room in your bag for a hutch first." end
  for _,e in ipairs(plan) do brickcraft.take(p,e.item.." "..e.count) end
  brickcraft.give(p,"brickcraft_habitat:hutch")
  return true,"Built a hutch from "..cost.." bricks! Place it near your colony: it adds room for 4 bunnies so babies can be born."
end
local save_wait={}
-- Every second, for each colony in w (someone's there): clovers come in, babies are born
-- when there's room and the colony's happy, levels are reached.
function H.colony_tick(w,v)
  if not v.colony then return end
  lookout_watch(w)
  local st=H.state(w)
  local cfg=v.colony
  for owner,c in pairs(st.colonies or {}) do
    top_up(w,v,owner,c)
    local s=H.colony_status(w,v,owner)
    if s.pop>0 then
      c.clovers=(c.clovers or 0)+s.pop*(cfg.income or .1)*(s.happy/100+.5)
      local nurseries=math.min(2,s.nursery)
      if s.pop>=2 and s.pop<s.cap and s.pop<(cfg.max or 60) and s.happy>=(cfg.happy or 60) then
        c.next_birth=c.next_birth or now()+(cfg.birth or 90)/(1+.5*nurseries)
        if now()>=c.next_birth then
          c.next_birth=now()+(cfg.birth or 90)/(1+.5*nurseries)*rnd(.8,1.2)
          local parents={}
          for ent in pairs(H.live) do
            local q=ent.object:get_pos()
            if q and ent._owner==owner and not ent._baby and brickcraft.world_at(q)==w then parents[#parents+1]=q end
          end
          if #parents>0 then
            local q=parents[math.random(#parents)]
            if H.spawn_creature(v.creature,vector.offset(q,.3,.2,0),{baby=true,owner=owner}) then
              c.born=(c.born or 0)+1
              local n=s.pop+1
              H.tell(w,"A baby "..H.creatures[v.creature].label:lower().." was born in "..label_of(owner).."'s colony! ("..n..")","#ffd6e8")
              H.save(w)
            end
          end
        end
      else c.next_birth=nil end
      c.gone=nil
    elseif (c.started or 0)>0 and not c.gone and ((c.born or 0)+(c.domesticated or 0))>0 then
      c.gone=true; H.save(w)
      H.tell(w,label_of(owner).."'s colony is gone. /colony start begins a new one.","#ff9a8a")
    end
    H.colony_progress(w,v,owner)
  end
  save_wait[w.id]=(save_wait[w.id] or 10)-1
  if save_wait[w.id]<=0 then save_wait[w.id]=10; H.save(w) end
end

------------------------------------------------------------------------------------------
-- The colony panel (/colony)
------------------------------------------------------------------------------------------
local function bar(x,y,label,f)
  local col=f>=1 and "#5fbf6a" or f>=.5 and "#e8be5c" or "#e0614f"
  return "label["..x..","..(y+.25)..";"..label.."]box["..(x+1.6)..","..y..";3,.45;#24343d]"..
    "box["..(x+1.6)..","..y..";"..string.format("%.2f",3*math.max(.02,math.min(1,f)))..",.45;"..col.."]"
end
function H.colony_panel(p)
  local name=p:get_player_name()
  local w,v=H.world_at(p:get_pos())
  if not (w and v.colony) then C.chat_send_player(name,"Colonies are in habitat worlds like Bunnyland."); return end
  local owner=owner_of(p)
  local s=H.colony_status(w,v,owner)
  local P=v.plural
  local fs="formspec_version[6]size[11,12.2]bgcolor[#142936;true]"..
    "label[.6,.6;"..C.formspec_escape((label_of(owner).."'s colony / "..s.level):upper()).."]"..
    "label[.6,1.2;"..C.formspec_escape(s.pop..(v.colony.win_count and "/"..v.colony.win_count or "").." "..P..(H.colony(w,owner).won and "  YOU WON!" or "").."   homes for "..s.cap.."   best "..s.best..
      "   born "..s.born.."   lost "..s.lost).."]"..
    "label[.6,1.7;"..C.formspec_escape(s.clovers.." clovers   (each of your "..P.." gathers clovers; happier ones gather more)").."]"..
    "label[6.2,2.3;Happiness "..s.happy.."%]"..
    bar(.6,2.1,"Homes",s.pop==0 and 1 or s.housing)..bar(.6,2.7,"Food",s.food)..bar(.6,3.3,"Water",s.water)..bar(.6,3.9,"Safety",s.safety)..
    bar(6.2,2.7,"Happy",s.happy/100)..
    "label[6.2,3.45;"..C.formspec_escape("Nurseries "..s.nursery.."   Lookouts "..s.lookouts).."]"..
    "box[.6,4.6;9.8,.8;#1d3a4a]label[.8,5.0;"..C.formspec_escape("Advisor: "..s.advice).."]"..
    "label[.6,5.9;Shop (clovers)]"
  for i,e in ipairs(v.colony.shop) do
    local d=C.registered_items["brickcraft_habitat:"..e[1]]
    local lbl=((e[3] and e[3].." x " or "")..(d and d.description or e[1]):match("^[^\n]+")).."  "..e[2]
    local x,y=.6+((i-1)%3)*3.3,6.2+math.floor((i-1)/3)*.9
    fs=fs.."style[buy_"..e[1]..";bgcolor="..(s.clovers>=e[2] and "#3a7a52" or "#3a5566").."]"..
      "button["..x..","..y..";3.2,.75;buy_"..e[1]..";"..C.formspec_escape(lbl).."]"..
      "tooltip[buy_"..e[1]..";"..C.formspec_escape((d and d.description or ""):gsub("\nRight click.*$","")).."]"
  end
  if v.colony.hutch_bricks then
    fs=fs.."button[.6,9.2;5.4,.7;craft_hutch;Build hutch: "..v.colony.hutch_bricks.." basic bricks]"..
      "label[6.2,9.55;Place it: +4 bunny spaces]"..
      "tooltip[craft_hutch;Trade basic 2 x 2 bricks of any colors for one hutch. No clovers needed.]"
  end
  local lv,i=level_of(v,s.best)
  local nxt=v.colony.levels[i+1]
  fs=fs.."label[.6,10.2;"..C.formspec_escape(nxt and ("Next: "..nxt[2].." at "..nxt[1].." "..P.." (+"..(nxt[3] or 0).." clovers)") or "Top level reached!").."]"
  if s.pop==0 then fs=fs.."style[start;bgcolor=#f5872c]button[.6,10.8;3.6,.8;start;Start a colony of "..v.colony.start.."]"
  else fs=fs.."button[.6,10.8;1.75,.8;call;Call them]button[2.45,10.8;1.75,.8;stay;Stay here]" end
  fs=fs.."button[4.4,10.8;3,.8;habitat;Habitat panel]button_exit[7.6,10.8;2.8,.8;close;Back to building]"
  C.show_formspec(name,"brickcraft_habitat:colony",fs)
end
C.register_on_player_receive_fields(function(p,formname,fields)
  if formname~="brickcraft_habitat:colony" then return end
  local name=p:get_player_name()
  if fields.habitat then H.panel(p); return true end
  if fields.start then local _,msg=H.start_colony(p); C.chat_send_player(name,msg); H.colony_panel(p); return true end
  if fields.call then local _,msg=H.call(p); C.chat_send_player(name,msg); C.close_formspec(name,"brickcraft_habitat:colony"); return true end
  if fields.stay then local _,msg=H.stay(p); C.chat_send_player(name,msg); H.colony_panel(p); return true end
  if fields.craft_hutch then local _,msg=H.craft_hutch(p); C.chat_send_player(name,msg); H.colony_panel(p); return true end
  for f in pairs(fields) do
    local id=f:match("^buy_(.+)$")
    if id then local _,msg=H.buy(p,id); C.chat_send_player(name,msg); H.colony_panel(p); return true end
  end
  return true
end)
C.register_chatcommand("colony",{params="[start | call | stay | buy <item> | craft hutch | top]",
  description="Your own colony in a habitat: start one with 5 bunnies, see how it's doing, buy hutches and food",
  func=function(name,param)
    local p=C.get_player_by_name(name); if not p then return end
    local cmd,arg=param:match("^(%S*)%s*(.-)%s*$")
    if cmd=="start" then local _,msg=H.start_colony(p); return true,msg end
    if cmd=="buy" then local _,msg=H.buy(p,arg); return true,msg end
    if cmd=="craft" and arg=="hutch" then return H.craft_hutch(p) end
    if cmd=="call" then local _,msg=H.call(p); return true,msg end
    if cmd=="stay" then local _,msg=H.stay(p); return true,msg end
    if cmd=="top" then
      local w,v=H.world_at(p:get_pos())
      if not (w and v.colony) then return true,"Not a habitat with colonies." end
      local rows={}
      for owner in pairs(H.state(w).colonies or {}) do
        local s=H.colony_status(w,v,owner)
        rows[#rows+1]={owner=owner,s=s}
      end
      table.sort(rows,function(a,b) return a.s.pop>b.s.pop end)
      local out={}
      for i,r in ipairs(rows) do out[#out+1]=i..". "..label_of(r.owner)..": "..r.s.pop.." "..v.plural.." ("..r.s.level..", best "..r.s.best..")"..(H.colony(w,r.owner).won and " WON!" or "") end
      return true,#out>0 and table.concat(out,"\n") or "No colonies yet."
    end
    H.colony_panel(p); return true
  end})
end
