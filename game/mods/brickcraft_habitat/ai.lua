-- Help from the AI builders (brickcraft_ai) in a habitat: what they hear about the asker's
-- colony, the steps they can take, and doing them. brickcraft_ai adds H.ai.prompt to its
-- chat instructions, H.ai.context(name) to what it sees, and hands each step to
-- H.ai.step(name,text,say,api) first; api = {bot=ObjectRef, owner=<owner id>,
-- is_owner=<asker is the bot's owner>, go=function(pos) (walk near pos; true if it can)}.
return function(H)
local C=core
local now,flat=H.now,H.flat
H.ai={}
H.ai.prompt=[[

Habitats (Bunnyland): a habitat world has animals to keep safe (bunnies) from predators (wolves, lions that leap fences, eagles from the sky) and disasters (flood, earthquake, asteroids). Each player can have a colony of their own bunnies that grows by babies when it has homes (hutches), food (carrot patches), water (troughs) and safety; bunnies gather clovers to buy things. When the asker is in a habitat you also get their colony's numbers, what's in their bag and any predators or disaster. Steps you can take there (only for your owner's colony; for anyone else, just advise):
"herd the bunnies home" (their bunnies follow you home; you open and close their gates), "guard the bunnies" (for two minutes you chase predators near them or the colony), "fence the colony" (a ring of their fence pieces around the colony's home, the gate toward them), "put out food and water" (their carrot patches and troughs inside the fence), "bunnies stay here" (stop following; where they stand becomes home), "start a colony", "colony status", "buy <number> <hutch|carrot patch|water trough|fence|gate|nursery|lookout>".
For anything else there (calling a predator or disaster, skins, the shop, following), use the game's commands.
When a predator is coming or a disaster is on, offer to guard or herd (or just do it for your owner when they're worried about their bunnies).]]

local function in_habitat(name)
  local pl=C.get_player_by_name(name)
  if not pl then return end
  local w,v=H.world_at(pl:get_pos())
  if w and v.colony then return pl,w,v end
end
local function home_of(w,owner)
  local c=H.colony(w,owner)
  local o=H.tally(w)[owner]
  local anchor=c.home or c.start
  if not anchor then return nil end
  local best,bd
  for _,q in ipairs(o and o.homes or {}) do
    local d=flat(q,anchor)
    if d<14 and (not bd or d<bd) then best,bd=q,d end
  end
  return vector.copy(best or anchor)
end
H.colony_home=home_of
local function count(pl,id) return brickcraft.count_of(pl,"brickcraft_habitat:"..id) end

function H.ai.context(name)
  local pl,w,v=in_habitat(name)
  if not pl then return "" end
  local owner=H.owner_of(pl)
  local s=H.colony_status(w,v,owner)
  local out={"They are in "..w.name..", a "..v.label.." habitat."}
  if s.pop==0 then out[#out+1]="They have no colony right now (\"start a colony\" gives "..v.colony.start.." "..v.plural.." and a kit)."
  else
    out[#out+1]=string.format("Their colony (%s): %d %s, homes for %d, happiness %d%%, %d clovers, %d lost so far. The advisor says: %s",
      s.level,s.pop,v.plural,s.cap,s.happy,s.clovers,s.lost,s.advice)
  end
  local bag={}
  for _,id in ipairs({"fence","fence_gate","hutch","carrot_patch","water_trough","nursery","lookout"}) do
    local n=count(pl,id)
    if n>0 then bag[#bag+1]=n.." "..id:gsub("_"," ") end
  end
  out[#out+1]="In their bag: "..(#bag>0 and table.concat(bag,", ") or "no habitat things")
  local p=pl:get_pos()
  local preds={}
  for ent in pairs(H.hunters) do
    local q=ent.object:get_pos()
    if q and brickcraft.world_at(q)==w then
      preds[#preds+1]=H.predators[ent._kind].label:lower().." "..math.floor(vector.distance(p,q)).." blocks away"
    end
  end
  out[#out+1]=#preds>0 and "Predators here: "..table.concat(preds,", ") or "No predators here now."
  local ctx=H.active[w.id]
  if ctx then out[#out+1]="Disaster: "..ctx.def.label..(ctx.started and " happening now" or " coming soon").."." end
  return table.concat(out,"\n").."\n"
end

------------------------------------------------------------------------------------------
-- Jobs that run on: herding and guarding.
------------------------------------------------------------------------------------------
local herds,guards={},{}
local function gates_near(pos,r,open)
  for _,q in ipairs(C.find_nodes_in_area(vector.offset(pos,-r,-1,-r),vector.offset(pos,r,2,r),
      open and {"group:habitat_fence"} or {"group:habitat_fence"})) do
    local n=C.get_node(q)
    if open and n.name:find("_gate$") then C.swap_node(q,{name=n.name.."_open",param2=n.param2})
    elseif not open and n.name:find("_gate_open$") then C.swap_node(q,{name=n.name:gsub("_open$",""),param2=n.param2}) end
  end
end
C.register_globalstep(function(dtime)
  for key,h in pairs(herds) do
    local bp=h.bot:get_pos()
    if not bp or now()>h.until_t then
      for _,ent in ipairs(h.list) do if ent._follow_obj==h.bot then ent._follow_obj=nil end end
      if h.opened then gates_near(h.home,10,false) end
      herds[key]=nil
    elseif flat(bp,h.home)<2.5 then
      h.there=h.there or now()
      if now()-h.there>4 then
        for _,ent in ipairs(h.list) do if ent._follow_obj==h.bot then ent._follow_obj=nil; ent._home_until=nil end end
        if h.opened then gates_near(h.home,10,false) end
        h.say("They're home! "..(h.opened and "I closed the gate." or ""))
        herds[key]=nil
      end
    elseif now()>(h.next_go or 0) then
      h.next_go=now()+2; h.go(h.home)
    end
  end
  for key,g in pairs(guards) do
    local bp=g.bot:get_pos()
    if not bp or now()>g.until_t then
      if bp then g.say("I'm done guarding. Call me if a predator comes back!") end
      guards[key]=nil
    else
      local target,td
      for ent in pairs(H.hunters) do
        local q=ent.object:get_pos()
        if q and not ent._gone and (flat(q,g.center())<24) then
          local d=vector.distance(bp,q)
          if not td or d<td then target,td=ent,d end
        end
      end
      if target then
        if td<2.6 and now()>(g.next_hit or 0) then
          g.next_hit=now()+1.2
          target:_hit(g.bot,{dmg=2})
          if target._gone then g.say("I chased the "..H.predators[target._kind].label:lower().." away!") end
        elseif now()>(g.next_go or 0) then
          g.next_go=now()+1.5; g.go(target.object:get_pos())
        end
      end
    end
  end
end)

------------------------------------------------------------------------------------------
-- Steps
------------------------------------------------------------------------------------------
local function has(low,...) for _,w in ipairs({...}) do if low:find(w,1,true) then return true end end end
local function fence_ring(pl,w,v,owner,say)
  local home=home_of(w,owner)
  if not home then say("Start a colony first, then I'll fence it."); return end
  local r=4
  local cells={}
  for dx=-r,r do for dz=-r,r do
    if math.max(math.abs(dx),math.abs(dz))==r then cells[#cells+1]={x=home.x+dx,z=home.z+dz} end
  end end
  -- The gate goes on the side toward the asker.
  local pp=pl:get_pos()
  local gx,gz=0,0
  if math.abs(pp.x-home.x)>math.abs(pp.z-home.z) then gx=pp.x>home.x and r or -r else gz=pp.z>home.z and r or -r end
  local placed,short,gate=0,0,false
  for _,c in ipairs(cells) do
    local g=H.ground(c.x,c.z,home.y+3)
    if g and math.abs(g-home.y)<=1 and C.get_node({x=c.x,y=g,z=c.z}).name=="air" then
      local isgate=(c.x==home.x+gx and gx~=0 and c.z==home.z) or (c.z==home.z+gz and gz~=0 and c.x==home.x)
      local id=isgate and "fence_gate" or "fence"
      if count(pl,id)>0 and brickcraft.take(pl,"brickcraft_habitat:"..id) then
        C.set_node({x=c.x,y=g,z=c.z},{name="brickcraft_habitat:"..id,param2=isgate and (gx~=0 and 1 or 0) or 0})
        placed=placed+1; gate=gate or isgate
      elseif isgate and count(pl,"fence")>0 and brickcraft.take(pl,"brickcraft_habitat:fence") then
        C.set_node({x=c.x,y=g,z=c.z},{name="brickcraft_habitat:fence"}); placed=placed+1
      else short=short+1 end
    end
  end
  say("I put up "..placed.." fence pieces around your colony"..(gate and ", with the gate on your side" or "")..
    (short>0 and ". I was "..short.." pieces short: the shop sells 8 for 10 clovers." or ".")..
    " Bunnies outside? Ask me to herd them home.")
end
local function put_out(pl,w,v,owner,say)
  local home=home_of(w,owner)
  if not home then say("Start a colony first."); return end
  local put={}
  for _,id in ipairs({"carrot_patch","water_trough"}) do
    local n=count(pl,id)
    for r=1,3 do for dx=-r,r do for dz=-r,r do
      if n>0 and math.max(math.abs(dx),math.abs(dz))==r and (dx+dz)%2==0 then
        local g=H.ground(home.x+dx,home.z+dz,home.y+3)
        local q=g and {x=home.x+dx,y=g,z=home.z+dz}
        if q and math.abs(g-home.y)<=1 and C.get_node(q).name=="air" and brickcraft.take(pl,"brickcraft_habitat:"..id) then
          C.set_node(q,{name="brickcraft_habitat:"..id}); C.get_meta(q):set_string("owner",owner)
          n=n-1; put[id]=(put[id] or 0)+1
        end
      end
    end end end
  end
  if not next(put) then say("You don't have carrot patches or troughs in your bag. The shop has them (/colony).") return end
  say("I put out "..(put.carrot_patch or 0).." carrot patches and "..(put.water_trough or 0).." troughs by your colony's home.")
end

function H.ai.step(name,text,say,api)
  local low=text:lower()
  local about=has(low,"bunn","rabbit","토끼","colony","hutch","fence","울타리","herd","round up","guard","predator","wolf","lion","eagle","carrot","trough","clover")
  if not about then return false end
  local pl,w,v=in_habitat(name)
  if not pl then
    if has(low,"herd","guard","fence","colony","carrot","trough") then
      say("That's for a habitat world like Bunnyland (I > Switch world). Ask me again there!") return true
    end
    return false
  end
  local owner=H.owner_of(pl)
  local s=H.colony_status(w,v,owner)
  if has(low,"status","how are","how's","how is","doing","advice","어때") and not has(low,"herd","guard","fence") then
    if s.pop==0 then say("You don't have a colony here yet. Say \"start a colony\" and I'll help you set it up!") return true end
    say(string.format("Your %s has %d %s and homes for %d, %d%% happy, %d clovers. %s",s.level,s.pop,v.plural,s.cap,s.happy,s.clovers,s.advice))
    return true
  end
  if not api.is_owner then
    say("I can only do that for "..(api.owner_label or "my owner").."'s colony. Ask your own builder, or try /colony!") return true
  end
  if has(low,"start") and has(low,"colony") then local _,msg=H.start_colony(pl); say(msg) return true end
  if has(low,"buy") then
    local n=math.max(1,math.min(tonumber(low:match("%d+")) or 1,10))
    local id=has(low,"hutch") and "hutch" or has(low,"carrot") and "carrot_patch" or has(low,"trough","water") and "water_trough" or
      has(low,"gate") and "fence_gate" or has(low,"fence") and "fence" or has(low,"nursery") and "nursery" or has(low,"lookout") and "lookout"
    if not id then say("What should I buy? Hutch, carrot patch, water trough, fence, gate, nursery or lookout.") return true end
    local got,msg=0,nil
    for _=1,n do local ok,m=H.buy(pl,id); msg=m; if ok then got=got+1 else break end end
    say(got>0 and "Bought "..got.."! "..(got<n and msg or "It's in your bag (I).") or msg) return true
  end
  if has(low,"fence","울타리") then fence_ring(pl,w,v,owner,say) return true end
  if has(low,"food","feed","water","carrot","trough","먹이") then put_out(pl,w,v,owner,say) return true end
  local bodily=has(low,"guard","chase","protect","scare","wolf","lion","eagle","predator","지켜","herd","round up","bring","몰")
  if bodily and not api.bot then say("I need to be here with you to do that. Say \"come here\" first!") return true end
  if has(low,"guard","chase","protect","scare","wolf","lion","eagle","predator","지켜") then
    guards[api.bot]={bot=api.bot,go=api.go,say=say,until_t=now()+120,
      center=function() local p=pl:get_pos() and pl:get_pos() or api.bot:get_pos(); local h=home_of(w,owner); return h and flat(p,h)>20 and p or h or p end}
    say("I'll guard your bunnies for two minutes and chase off anything that comes!") return true
  end
  if has(low,"stay") then local _,msg=H.stay(pl); say(msg) return true end
  if has(low,"herd","round up","bring","home","몰") then
    local home=home_of(w,owner)
    if not home then say("Your colony doesn't have a home yet: start one, or stand where it should be and say \"bunnies stay here\".") return true end
    local list={}
    for ent in pairs(H.live) do
      local q=ent.object:get_pos()
      if q and ent._owner==owner and vector.distance(q,api.bot:get_pos())<45 and flat(q,home)>2 then
        ent._follow_obj,ent._follow_until=api.bot,now()+90; list[#list+1]=ent
      end
    end
    if #list==0 then say("Your bunnies are all home already!") return true end
    gates_near(home,10,true)
    herds[api.bot]={bot=api.bot,go=api.go,say=say,list=list,home=home,opened=true,until_t=now()+90}
    api.go(home)
    say("Follow me, bunnies! I'm taking "..#list.." home. I opened your gate; I'll close it when they're in.")
    return true
  end
  return false
end
brickcraft.assist.register({name="habitat",prompt=H.ai.prompt,context=H.ai.context,step=H.ai.step})
end
