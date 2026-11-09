-- Bunnyland's small Korean reading game. Glowing word bricks are spread across the
-- existing habitat; some sit one scenery block inside a hill. Each profile collects its
-- own copy, then orders words on a separate storybook formspec. The objects never enter
-- the ordinary BrickCraft inventory and never overwrite player builds.
return function(H)
local C=core
local storage=brickcraft.storage
local FORM_BOOK="brickcraft_habitat:word_story"
local FORM_SENTENCE="brickcraft_habitat:word_sentence"
local NUM={"①","②","③","④"}
local COLORS={"coral","gold","mint","sky"}
local REWARD="brickcraft_habitat:magic_carrot_soup"

local SENTENCES={
  {text="클로버밭에서 반짝이는 클로버를 세 송이 모아요.",picture="반짝이는 클로버 세 송이"},
  {text="당근밭에서 싱싱한 주황 당근을 두 개 뽑아요.",picture="막 뽑은 주황 당근 두 개"},
  {text="연못에서 맑은 물을 한 병 천천히 떠요.",picture="맑은 연못물 한 병"},
  {text="거대 토끼상 앞의 마법 냄비에 재료를 차례로 넣어요.",picture="금빛으로 빛나는 마법 당근 수프"},
}

-- Open words use the meadow and landmarks. The last sentence leads into the outer hills:
-- ground and wall words are inside one ordinary scenery node, with a glow outside it.
local WORDS={
  {s=1,word="클로버밭에서",dx=-9,dz=-12},{s=1,word="반짝이는",dx=-3,dz=-15},
  {s=1,word="클로버를",dx=3,dz=-14},{s=1,word="세 송이",dx=9,dz=-10},
  {s=1,word="모아요",dx=14,dz=-5},

  {s=2,word="당근밭에서",dx=-18,dz=-6},{s=2,word="싱싱한",dx=-14,dz=-1},
  {s=2,word="주황 당근을",dx=-10,dz=4},{s=2,word="두 개",dx=-16,dz=8},
  {s=2,word="뽑아요",dx=-9,dz=12},

  {s=3,word="연못에서",dx=-18,dz=22},{s=3,word="맑은 물을",dx=-10,dz=27},
  {s=3,word="한 병",dx=-3,dz=22},{s=3,word="천천히",dx=8,dz=27},
  {s=3,word="떠요",dx=17,dz=21},

  {s=4,word="거대 토끼상 앞의",dx=-31,dz=29,mode="ground"},
  {s=4,word="마법 냄비에",dx=-34,dz=10,mode="wall"},
  {s=4,word="재료를",dx=33,dz=9,mode="wall"},
  {s=4,word="차례로",dx=29,dz=30,mode="ground"},
  {s=4,word="넣어요",dx=9,dz=45},
}
for i,d in ipairs(WORDS) do d.id=i; SENTENCES[d.s].words=SENTENCES[d.s].words or {}; SENTENCES[d.s].words[#SENTENCES[d.s].words+1]=i end
local RECIPE_STEPS={
  {label="클로버 세 송이 모으기",color="green"},
  {label="주황 당근 두 개 뽑기",color="coral"},
  {label="맑은 연못물 한 병 뜨기",color="sky"},
  {label="마법 냄비에 차례로 넣기",color="gold"},
}

local function profile(p) return brickcraft.playing_as(p) or p:get_player_name() end
local function state_key(p,w) return "word_story_"..w.id.."_"..C.sha1(profile(p)) end
local function state(p,w)
  local s=C.deserialize(storage:get_string(state_key(p,w))) or {}
  s.got=s.got or {}; s.complete=s.complete or {}; s.attempts=s.attempts or {}
  return s
end
local function save(p,w,s) storage:set_string(state_key(p,w),C.serialize(s)) end
local function bunny_world(p)
  local w,v=H.world_at(p:get_pos())
  if w and v and v.id=="bunny" then return w,v end
end
local function count_sentence(s,n)
  local got=0
  for _,i in ipairs(SENTENCES[n].words) do if s.got[i] then got=got+1 end end
  return got
end
local function total(s)
  local got,done=0,0
  for i=1,#WORDS do if s.got[i] then got=got+1 end end
  for i=1,#SENTENCES do if s.complete[i] then done=done+1 end end
  return got,done
end

C.register_craftitem(REWARD,{
  description="마법 당근 수프\n버니에게 사용하면 배고픔, 목마름과 체력을 회복해요",
  inventory_image="brickcraft_habitat_carrot.png^[colorize:#ffe27a:70",
  stack_max=9,
  on_use=function(stack,user,pointed)
    if not (user and pointed and pointed.type=="object") then return stack end
    local ent=pointed.ref:get_luaentity()
    if not (ent and ent._kind=="bunny" and not ent._dead) then
      C.chat_send_player(user:get_player_name(),"마법 당근 수프는 버니에게 줄 수 있어요.")
      return stack
    end
    local hp=(H.creatures.bunny or {}).hp or 10
    ent._food,ent._water,ent._hp=100,100,hp
    local pos=pointed.ref:get_pos()
    if pos then C.add_particle({pos=vector.offset(pos,0,.5,0),velocity={x=0,y=.8,z=0},expirationtime=.8,size=6,
      texture="brickcraft_habitat_spark.png",glow=14}) end
    stack:take_item()
    C.chat_send_player(user:get_player_name(),C.colorize("#ffe27a","버니가 마법 당근 수프를 먹고 건강해졌어요!"))
    return stack
  end,
})

local function reward(p,w,s)
  if s.rewarded then return true end
  if not brickcraft.room_for(p,REWARD) then s.reward_pending=true; save(p,w,s); return false end
  local left=brickcraft.give(p,REWARD)
  if left and not left:is_empty() then s.reward_pending=true; save(p,w,s); return false end
  s.rewarded=true; s.reward_pending=nil; save(p,w,s)
  C.chat_send_player(p:get_player_name(),C.colorize("#ffe27a","레시피 완성 보상: 마법 당근 수프! 버니에게 사용해 보세요."))
  return true
end

local drafts={}
local function selected(order)
  local out={}
  for _,i in ipairs(order or {}) do out[i]=true end
  return out
end
local function joined(order)
  local out={}
  for _,i in ipairs(order or {}) do out[#out+1]=WORDS[i].word end
  return #out>0 and table.concat(out,"  ") or "아래에서 단어를 골라 문장을 만드세요."
end

local open_book,open_sentence
open_book=function(p,message)
  local w=bunny_world(p)
  if not w then C.chat_send_player(p:get_player_name(),"이야기책은 Bunnyland에서 열 수 있어요."); return end
  local s=state(p,w); s.started=true; save(p,w,s)
  if s.reward_pending then reward(p,w,s) end
  local got,done=total(s)
  local E=C.formspec_escape
  local fs="formspec_version[6]size[12,9.4]bgcolor[#142936;true]"..
    "label[.6,.55;BUNNYLAND / 이야기책]"..
    "label[.6,1.05;버니의 마법 당근 수프]"..
    "label[8.2,1.05;찾은 단어 "..got.."/"..#WORDS.."   문장 "..done.."/"..#SENTENCES.."]"..
    "textarea[.6,1.45;10.8,.8;;;"..E(message or "빛나는 단어 브릭을 세퍼레이터로 캐고, 같은 번호끼리 문장을 만드세요.").."]"
  for n,sen in ipairs(SENTENCES) do
    local y=2.25+(n-1)*1.45
    local have=count_sentence(s,n)
    local line=s.complete[n] and sen.text or (NUM[n].."  찾은 단어 "..have.."/"..#sen.words)
    fs=fs.."box[.55,"..y..";10.9,1.1;#1d3b4c]"..
      "label[.8,"..(y+.18)..";"..E(line).."]"..
      "button[8.7,"..(y+.17)..";2.35,.65;open_"..n..";"..E(s.complete[n] and "다시 읽기" or "문장 만들기").."]"
    if s.complete[n] then fs=fs.."tooltip[open_"..n..";"..E(sen.picture).."]" end
  end
  if done==#SENTENCES then
    local step=s.recipe_step or 0
    local line=s.rewarded and "레시피와 보상 완료! 수프를 버니에게 사용해 보세요." or
      s.reward_pending and "레시피 완료! 가방을 비운 뒤 이야기책을 다시 열어 보상을 받으세요." or
      ("레시피 실행 "..step.."/4 · 빛나는 재료 표식을 ①부터 차례로 따라가세요.")
    fs=fs.."label[.8,8.25;"..E(line).."]"
  else
    fs=fs.."label[.8,8.25;단어 브릭은 문장 번호별 색으로 빛나요. 일부는 빛나는 땅이나 벽 한 겹 뒤에 있어요.]"
  end
  fs=fs.."button_exit[8.7,8.65;2.35,.55;close;닫기]"
  C.show_formspec(p:get_player_name(),FORM_BOOK,fs)
end

open_sentence=function(p,n,message)
  local w=bunny_world(p)
  if not w or not SENTENCES[n] then return end
  local name=p:get_player_name()
  local s=state(p,w)
  local d=drafts[name]
  if not d or d.world~=w.id or d.sentence~=n then d={world=w.id,sentence=n,order={}}; drafts[name]=d end
  local E=C.formspec_escape
  if s.complete[n] then
    C.show_formspec(name,FORM_SENTENCE,"formspec_version[6]size[12,6]bgcolor[#142936;true]"..
      "label[.6,.6;"..NUM[n].." 완성된 문장]"..
      "textarea[.7,1.35;10.6,1.4;;;"..E(SENTENCES[n].text).."]"..
      "textarea[.7,3;10.6,1;;;그림: "..E(SENTENCES[n].picture).."]"..
      "button[.7,5;2.4,.6;back;이야기책]button_exit[8.9,5;2.4,.6;close;닫기]")
    return
  end
  local used=selected(d.order)
  local fs="formspec_version[6]size[12,8.2]bgcolor[#142936;true]"..
    "label[.6,.55;"..NUM[n].." 문장 만들기]"..
    "textarea[.6,1.05;10.8,1.15;;;"..E(joined(d.order)).."]"..
    "label[.6,2.25;찾은 단어]"
  local x,y=.6,2.65
  for _,i in ipairs(SENTENCES[n].words) do
    if s.got[i] and not used[i] then
      fs=fs.."button["..x..","..y..";2.05,.7;add_"..i..";"..E(WORDS[i].word).."]"
    else
      local label=used[i] and "✓ "..WORDS[i].word or "아직 못 찾음"
      fs=fs.."label["..(x+.12)..","..(y+.18)..";"..E(label).."]"
    end
    x=x+2.2
    if x>9.5 then x=.6; y=y+.85 end
  end
  fs=fs.."textarea[.6,4.45;10.8,.8;;;"..E(message or
    (count_sentence(s,n)==#SENTENCES[n].words and "단어를 눌러 자연스러운 문장 순서로 놓으세요." or "BunnyLand에서 같은 번호의 단어를 더 찾아보세요.")).."]"..
    "button[.6,5.55;2.2,.65;undo;한 칸 되돌리기]button[2.95,5.55;2.2,.65;clear;처음부터]"..
    "style[check;bgcolor=#f5872c]button[5.3,5.55;2.2,.65;check;문장 확인]"..
    "button[.6,6.55;2.2,.65;back;이야기책]button_exit[8.95,6.55;2.2,.65;close;닫기]"
  C.show_formspec(name,FORM_SENTENCE,fs)
end

local function collect(p,w,i,pos)
  if not i or not WORDS[i] then return end
  local s=state(p,w)
  if s.got[i] then
    C.chat_send_player(p:get_player_name(),C.colorize("#ffe27a","이미 찾은 단어예요: "..NUM[WORDS[i].s].." "..WORDS[i].word))
    return
  end
  s.started=true; s.got[i]=true; save(p,w,s)
  local n=WORDS[i].s
  C.chat_send_player(p:get_player_name(),C.colorize("#ffe27a","찾았다!  "..NUM[n].." "..WORDS[i].word.."  ("..count_sentence(s,n).."/"..#SENTENCES[n].words..")"))
  if pos then C.add_particle({pos=pos,velocity={x=0,y=1,z=0},expirationtime=.7,size=5,texture="brickcraft_habitat_spark.png",glow=14}) end
  if count_sentence(s,n)==#SENTENCES[n].words then
    C.chat_send_player(p:get_player_name(),C.colorize("#9ee6c6",NUM[n].." 단어를 모두 찾았어요. /story에서 문장을 만들 수 있어요."))
  end
end

local function recipe_collect(p,w,i,pos)
  local s=state(p,w)
  local _,done=total(s)
  if done<#SENTENCES then
    C.chat_send_player(p:get_player_name(),"먼저 단어를 모아 레시피 문장 네 개를 완성하세요. (/story)")
    return
  end
  local expected=(s.recipe_step or 0)+1
  if i<expected then
    C.chat_send_player(p:get_player_name(),"이미 끝낸 단계예요: "..NUM[i].." "..RECIPE_STEPS[i].label)
    return
  end
  if i~=expected then
    C.chat_send_player(p:get_player_name(),"레시피 순서를 다시 읽어 보세요. 다음은 "..NUM[expected].." 단계예요.")
    return
  end
  s.recipe_step=i; save(p,w,s)
  if pos then C.add_particle({pos=pos,velocity={x=0,y=1,z=0},expirationtime=.8,size=6,
    texture="brickcraft_habitat_spark.png",glow=14}) end
  C.chat_send_player(p:get_player_name(),C.colorize("#9ee6c6",NUM[i].." "..RECIPE_STEPS[i].label.." 완료!"))
  if i==#RECIPE_STEPS then reward(p,w,s)
  else C.chat_send_player(p:get_player_name(),"다음 단계: "..NUM[i+1].." "..RECIPE_STEPS[i+1].label) end
end

local objects={}
local recipe_objects={}
C.register_entity("brickcraft_habitat:story_glow",{
  initial_properties={visual="sprite",textures={"brickcraft_habitat_spark.png"},visual_size={x=.55,y=.55},
    physical=false,pointable=false,static_save=false,glow=14,collide_with_objects=false},
  on_activate=function(self) self.object:set_armor_groups({immortal=1}) end,
})

local function word_label(i) local d=WORDS[i]; return NUM[d.s].."  "..d.word end
C.register_entity("brickcraft_habitat:story_word",{
  initial_properties={visual="cube",textures={"brickcraft_gold.png"},visual_size={x=.55,y=.55,z=.55},
    physical=false,pointable=true,static_save=false,glow=10,collide_with_objects=false,
    selectionbox={-.38,-.38,-.38,.38,.38,.38}},
  on_activate=function(self,staticdata)
    local d=C.deserialize(staticdata or "") or {}
    if not WORDS[d.index] then self.object:remove(); return end
    self._world,self._index,self._buried,self._beacon_pos=d.world,d.index,d.buried,d.beacon
    self._timer=0
    local tex="brickcraft_"..COLORS[WORDS[d.index].s]..".png"
    self.object:set_properties({textures={tex,tex,tex,tex,tex,tex},
      nametag=d.buried and "" or word_label(d.index),nametag_color="#ffffff",nametag_bgcolor="#142936dd"})
    self.object:set_armor_groups({immortal=1})
  end,
  on_deactivate=function(self)
    if self._glow and self._glow:get_pos() then self._glow:remove() end
    local by=objects[self._world]
    if by and by[self._index]==self.object then by[self._index]=nil end
  end,
  _show_glow=function(self)
    if not self._beacon_pos or (self._glow and self._glow:get_pos()) then return end
    self._glow=C.add_entity(self._beacon_pos,"brickcraft_habitat:story_glow")
  end,
  _reveal=function(self)
    if self._revealed then return end
    self._revealed=true
    self.object:set_properties({nametag=word_label(self._index)})
    if self._glow and self._glow:get_pos() then self._glow:remove() end
    self._glow=nil
  end,
  on_step=function(self,dt)
    self._timer=self._timer+dt; if self._timer<.5 then return end; self._timer=0
    if not self._buried then self:_reveal(); return end
    local p=self.object:get_pos()
    local node=p and C.get_node(vector.round(p)).name
    if node=="air" then self:_reveal() else self:_show_glow() end
  end,
  _brickcraft_collect=function(self,p)
    local w=bunny_world(p)
    if not w or w.id~=self._world then return end
    if not self._revealed then
      C.chat_send_player(p:get_player_name(),"빛나는 흙이나 벽 한 겹을 먼저 캐 보세요.")
      return
    end
    collect(p,w,self._index,self.object:get_pos())
  end,
  on_punch=function(self,p)
    if p and p:is_player() and p:get_wielded_item():get_name()=="brickcraft:separator" then self:_brickcraft_collect(p) end
    return true
  end,
})

C.register_entity("brickcraft_habitat:story_recipe",{
  initial_properties={visual="cube",textures={"brickcraft_gold.png"},visual_size={x=.65,y=.65,z=.65},
    physical=false,pointable=true,static_save=false,glow=12,collide_with_objects=false,
    selectionbox={-.42,-.42,-.42,.42,.42,.42}},
  on_activate=function(self,staticdata)
    local d=C.deserialize(staticdata or "") or {}
    if not RECIPE_STEPS[d.step] then self.object:remove(); return end
    self._world,self._step=d.world,d.step
    local tex="brickcraft_"..RECIPE_STEPS[d.step].color..".png"
    self.object:set_properties({textures={tex,tex,tex,tex,tex,tex},nametag=NUM[d.step].."  "..RECIPE_STEPS[d.step].label,
      nametag_color="#ffffff",nametag_bgcolor="#142936dd"})
    self.object:set_armor_groups({immortal=1})
  end,
  on_deactivate=function(self)
    local by=recipe_objects[self._world]
    if by and by[self._step]==self.object then by[self._step]=nil end
  end,
  _brickcraft_collect=function(self,p)
    local w=bunny_world(p)
    if w and w.id==self._world then recipe_collect(p,w,self._step,self.object:get_pos()) end
  end,
  on_punch=function(self,p)
    if p and p:is_player() and p:get_wielded_item():get_name()=="brickcraft:separator" then self:_brickcraft_collect(p) end
    return true
  end,
})

local DIRS={{1,0},{-1,0},{0,1},{0,-1}}
local function scenery(pos) return C.get_item_group(C.get_node(pos).name,"scenery")>0 end
local function open_spot(w,d)
  local x,z=w.x+d.dx,w.z+d.dz
  local y=H.ground(x,z,34)
  if not y then return end
  return {pos={x=x,y=y+.4,z=z},buried=false}
end
local function ground_spot(w,d)
  local x,z=w.x+d.dx,w.z+d.dz
  local y=H.ground(x,z,34)
  if not y then return end
  local q={x=x,y=y-1,z=z}
  if not scenery(q) then return open_spot(w,d) end
  return {pos=q,buried=true,beacon={x=x,y=y+.25,z=z}}
end
local function wall_spot(w,d)
  local tx,tz=w.x+d.dx,w.z+d.dz
  for r=0,5 do
    for dz=-r,r do for dx=-r,r do
      if r==0 or math.max(math.abs(dx),math.abs(dz))==r then
        for y=0,18 do
          local q={x=tx+dx,y=y,z=tz+dz}
          if scenery(q) then
            for _,dir in ipairs(DIRS) do
              local air={x=q.x+dir[1],y=q.y,z=q.z+dir[2]}
              if C.get_node(air).name=="air" then
                return {pos=q,buried=true,beacon={x=air.x,y=air.y+.15,z=air.z}}
              end
            end
          end
        end
      end
    end end
  end
  return ground_spot(w,d)
end
local function stored_spot(w,i)
  local st=H.state(w); st.word_story_spots=st.word_story_spots or {}
  local spot=st.word_story_spots[i]
  if spot then return spot end
  local d=WORDS[i]
  spot=d.mode=="wall" and wall_spot(w,d) or d.mode=="ground" and ground_spot(w,d) or open_spot(w,d)
  if spot then st.word_story_spots[i]=spot; H.save(w) end
  return spot
end
local function recipe_spot(w,i)
  local x,z
  if i==1 then
    local found=C.find_nodes_in_area({x=w.x-22,y=0,z=w.z-22},{x=w.x+22,y=2,z=w.z+22},{"brickcraft_habitat:clover"})
    if #found>0 then
      table.sort(found,function(a,b)
        local da=(a.x-w.x)^2+(a.z-w.z)^2
        local db=(b.x-w.x)^2+(b.z-w.z)^2
        return da==db and (a.x==b.x and a.z<b.z or a.x<b.x) or da<db
      end)
      x,z=found[1].x,found[1].z
    end
  elseif i==2 then x,z=w.x-7,w.z+26
  elseif i==3 then x,z=w.x-9,w.z-3
  else x,z=w.x,w.z+29 end
  if not x then return end
  local y=H.ground(x,z,34)
  if not y then return end
  return {x=x,y=y+.55,z=z}
end
local function recipe_unlocked(w)
  for _,p in ipairs(H.players_in(w)) do
    local _,done=total(state(p,w))
    if done==#SENTENCES then return true end
  end
  return false
end
local function ensure_recipe(w)
  if not recipe_unlocked(w) then return end
  recipe_objects[w.id]=recipe_objects[w.id] or {}
  for i=1,#RECIPE_STEPS do
    local old=recipe_objects[w.id][i]
    if not (old and old:get_pos()) then
      local pos=recipe_spot(w,i)
      if pos then
        local obj=C.add_entity(pos,"brickcraft_habitat:story_recipe",C.serialize({world=w.id,step=i}))
        if obj then recipe_objects[w.id][i]=obj end
      end
    end
  end
end
local function ensure(w)
  objects[w.id]=objects[w.id] or {}
  for i=1,#WORDS do
    local old=objects[w.id][i]
    if not (old and old:get_pos()) then
      local spot=stored_spot(w,i)
      if spot then
        local obj=C.add_entity(spot.pos,"brickcraft_habitat:story_word",C.serialize({world=w.id,index=i,buried=spot.buried,beacon=spot.beacon}))
        if obj then objects[w.id][i]=obj end
      end
    end
  end
  ensure_recipe(w)
end

local elapsed=0
C.register_globalstep(function(dt)
  elapsed=elapsed+dt; if elapsed<2 then return end; elapsed=0
  local seen={}
  for _,p in ipairs(C.get_connected_players()) do
    local w,v=H.world_at(p:get_pos())
    if w and v and v.id=="bunny" and not seen[w.id] then seen[w.id]=true; ensure(w) end
  end
end)

C.register_on_player_receive_fields(function(p,form,fields)
  if form==FORM_BOOK then
    for n=1,#SENTENCES do if fields["open_"..n] then open_sentence(p,n); return true end end
    return true
  end
  if form~=FORM_SENTENCE then return end
  local name=p:get_player_name()
  local w=bunny_world(p)
  local d=w and drafts[name]
  if not w or not d or d.world~=w.id then return true end
  if fields.back then open_book(p); return true end
  for _,i in ipairs(SENTENCES[d.sentence].words) do
    if fields["add_"..i] then
      local s=state(p,w)
      if s.got[i] and not selected(d.order)[i] then d.order[#d.order+1]=i end
      open_sentence(p,d.sentence); return true
    end
  end
  if fields.undo then table.remove(d.order); open_sentence(p,d.sentence); return true end
  if fields.clear then d.order={}; open_sentence(p,d.sentence); return true end
  if fields.check then
    local sen=SENTENCES[d.sentence]
    if #d.order<#sen.words then open_sentence(p,d.sentence,"찾은 단어를 모두 문장에 넣어 주세요."); return true end
    local ok=true
    for j,i in ipairs(sen.words) do if d.order[j]~=i then ok=false; break end end
    local s=state(p,w)
    if ok then
      s.complete[d.sentence]=true; save(p,w,s); drafts[name]=nil
      local _,done=total(s)
      open_book(p,done==#SENTENCES and "레시피 완성! 네 문장을 읽고 BunnyLand에서 그대로 따라 해 보세요." or NUM[d.sentence].." 문장을 완성했어요!")
    else
      s.attempts[d.sentence]=(s.attempts[d.sentence] or 0)+1; save(p,w,s)
      local hint=s.attempts[d.sentence]>=2 and ("힌트: 첫 단어는 ‘"..WORDS[sen.words[1]].word.."’예요.") or "단어를 소리 내어 읽고 어순을 다시 생각해 보세요."
      open_sentence(p,d.sentence,hint)
    end
    return true
  end
  return true
end)
C.register_on_leaveplayer(function(p) drafts[p:get_player_name()]=nil end)

C.register_chatcommand("story",{params="[reset]",description="Bunnyland: open or reset the Korean word storybook",
  func=function(name,param)
    local p=C.get_player_by_name(name); if not p then return end
    local w=bunny_world(p)
    if not w then return false,"Bunnyland에서 사용할 수 있어요." end
    if param:match("^%s*reset%s*$") then storage:set_string(state_key(p,w),""); drafts[name]=nil; return true,"이야기를 처음부터 시작해요." end
    open_book(p); return true
  end})

brickcraft.help[#brickcraft.help+1]={"/story","Bunnyland: 빛나는 단어를 모아 별도 이야기책에서 문장 만들기"}
brickcraft.help[#brickcraft.help+1]={"빛나는 땅/벽 + separator","한 겹을 캐면 숨은 단어 브릭이 나옴"}

H.word_story={open=open_book,ensure=ensure,state=state,collect=collect,recipe_collect=recipe_collect,
  words=WORDS,sentences=SENTENCES,reward=REWARD}
end
