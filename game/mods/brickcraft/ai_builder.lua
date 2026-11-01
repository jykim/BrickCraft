-- AI builders: block people who build what players ask for in chat ("Leona bot, build a
-- red tower"). Every player has their own builder, which follows them and works in their
-- world; they name it themselves (/botname). jms, the host's builder, looks after the
-- Workshop on his own when it's quiet; he is off unless brickcraft_ai_jms is set.
-- Requests are designed by Claude Code through the host's Local AI API (an OpenAI-style
-- chat completions endpoint, brickcraft_ai_url; it runs on the Claude login of the jms Mac).
-- If it doesn't answer, builders use the built-in blueprints below. Pieces go through the
-- same nodes a player places, so anyone can collect or change them. Builders' bricks are free.
local C=core
local S=C.settings
local NAME=S:get("brickcraft_ai_name") or "jms"
local LNAME=NAME:lower()
local STEP=tonumber(S:get("brickcraft_ai_step")) or .35       -- seconds per piece
local IDLE=tonumber(S:get("brickcraft_ai_idle")) or 90        -- quiet seconds before building alone
local AUTO_MAX=tonumber(S:get("brickcraft_ai_auto_max")) or 6 -- own builds per server run
local MODEL=S:get("brickcraft_ai_model") or "opus"
local URL=S:get("brickcraft_ai_url") or "http://127.0.0.1:8099/claude/v1/chat/completions"
local http=brickcraft.http
local use_claude=http and URL~="" and S:get_bool("brickcraft_ai_llm",true)
local shapes,colors=brickcraft.shapes,brickcraft.colors
local storage=C.get_mod_storage()
local EDGE=24 -- the baseplate
C.log("action","BrickCraft AI builders: "..(use_claude and "Claude Code ("..MODEL..") via "..URL or
  "built-in blueprints"..(http and "" or " (no HTTP access: add brickcraft to secure.http_mods)")))

local quiet=0 -- seconds since anyone (builders included) said something in chat
local function display_name(name)
  local p=C.get_player_by_name(name)
  local id=p and brickcraft.playing_as(p)
  return id and brickcraft.styles[id].label or name
end

-- Plans ---------------------------------------------------------------------------------
-- A plan is pieces {piece,color,x,y,z,turn} in local cells; later pieces in a cell replace
-- earlier ones. Turn 0 = long/high side toward +z, 1 = +x, 2 = -z, 3 = -x; fronts face -z.
local function key(x,y,z) return x..","..y..","..z end
-- Plans stay within what jms can reach and build: 18 x 18 cells, 8 high, 500 pieces.
local MAX_PIECES,MAX_SPAN,MAX_HEIGHT=500,18,8
local SIDES={{x=0,y=-1,z=0},{x=1,y=0,z=0},{x=-1,y=0,z=0},{x=0,y=0,z=1},{x=0,y=0,z=-1},{x=0,y=1,z=0}}
local function new_plan() return {pieces={},at={}} end
local function add(p,piece,color,x,y,z,turn)
  local k=key(x,y,z)
  local item={piece=piece,color=color,x=x,y=y,z=z,turn=(turn or 0)%4}
  if p.at[k] then p.pieces[p.at[k]]=item
  else p.pieces[#p.pieces+1]=item; p.at[k]=#p.pieces end
end
local function clear(p,x,y,z)
  local k=key(x,y,z)
  if p.at[k] then p.pieces[p.at[k]]=false; p.at[k]=nil end
end
local function box(p,piece,color,x1,y1,z1,x2,y2,z2,hollow)
  for y=math.min(y1,y2),math.max(y1,y2) do
    for z=math.min(z1,z2),math.max(z1,z2) do
      for x=math.min(x1,x2),math.max(x1,x2) do
        local edge=x==x1 or x==x2 or z==z1 or z==z2
        if not hollow or edge then
          if piece then add(p,piece,color,x,y,z) else clear(p,x,y,z) end
        end
      end
    end
  end
end
local function cells_of(it)
  local cells={{x=it.x,y=it.y,z=it.z}}
  if shapes[it.piece].long then
    local d=C.facedir_to_dir(it.turn)
    cells[2]={x=it.x+d.x,y=it.y,z=it.z+d.z}
  end
  return cells
end
-- Turns a plan k quarter turns clockwise seen from above (+z goes to +x) and moves it to
-- start at 0,0,0. Pieces that overlap an earlier one or fall outside the limits are dropped.
-- jms places a piece only against one already there, like a player, so each piece comes
-- after a piece it touches (or the ground), lowest first; pieces touching nothing are dropped.
local function finish(p,k)
  local list={}
  for _,it in ipairs(p.pieces) do
    if it then
      local x,z=it.x,it.z
      for _=1,(k or 0)%4 do x,z=z,-x end
      list[#list+1]={piece=it.piece,color=it.color,x=x,y=it.y,z=z,turn=(it.turn+(k or 0))%4}
    end
  end
  if #list==0 then return list end
  local mx,my,mz=math.huge,math.huge,math.huge
  for _,it in ipairs(list) do
    for _,c in ipairs(cells_of(it)) do mx,my,mz=math.min(mx,c.x),math.min(my,c.y),math.min(mz,c.z) end
  end
  local taken,out={}, {}
  for _,it in ipairs(list) do
    it.x,it.y,it.z=it.x-mx,it.y-my,it.z-mz
    local ok=#out<MAX_PIECES
    for _,c in ipairs(cells_of(it)) do
      if taken[key(c.x,c.y,c.z)] or c.x>=MAX_SPAN or c.z>=MAX_SPAN or c.y>=MAX_HEIGHT then ok=false end
    end
    if ok then
      for _,c in ipairs(cells_of(it)) do taken[key(c.x,c.y,c.z)]=true end
      out[#out+1]=it
    end
  end
  table.sort(out,function(a,b)
    if a.y~=b.y then return a.y<b.y end
    if a.z~=b.z then return a.z<b.z end
    return a.x<b.x
  end)
  local placed,order=({}),{}
  local function touches(it)
    for _,c in ipairs(cells_of(it)) do
      if c.y==0 then return true end
      for _,d in ipairs(SIDES) do if placed[key(c.x+d.x,c.y+d.y,c.z+d.z)] then return true end end
    end
  end
  local progress=true
  while progress do
    progress=false
    for i,it in ipairs(out) do
      if it and touches(it) then
        order[#order+1]=it; out[i]=false; progress=true
        for _,c in ipairs(cells_of(it)) do placed[key(c.x,c.y,c.z)]=true end
        break
      end
    end
  end
  return order
end
local function bounds(list)
  local b={x=0,y=0,z=0}
  for _,it in ipairs(list) do
    for _,c in ipairs(cells_of(it)) do b.x,b.y,b.z=math.max(b.x,c.x),math.max(b.y,c.y),math.max(b.z,c.z) end
  end
  return b
end

-- Built-in blueprints. o = {color, accent, size 1..3, n (a number from the request)}.
local font={
  A={"010","101","111","101","101"},B={"110","101","110","101","110"},C={"011","100","100","100","011"},
  D={"110","101","101","101","110"},E={"111","100","110","100","111"},F={"111","100","110","100","100"},
  G={"011","100","101","101","011"},H={"101","101","111","101","101"},I={"111","010","010","010","111"},
  J={"001","001","001","101","010"},K={"101","101","110","101","101"},L={"100","100","100","100","111"},
  M={"101","111","111","101","101"},N={"110","101","101","101","101"},O={"010","101","101","101","010"},
  P={"110","101","110","100","100"},Q={"010","101","101","110","011"},R={"110","101","110","101","101"},
  S={"011","100","010","001","110"},T={"111","010","010","010","010"},U={"101","101","101","101","111"},
  V={"101","101","101","101","010"},W={"101","101","111","111","101"},X={"101","101","010","101","101"},
  Y={"101","101","010","010","010"},Z={"111","001","010","100","111"},
  ["0"]={"111","101","101","101","111"},["1"]={"010","110","010","010","111"},["2"]={"110","001","010","100","111"},
  ["3"]={"110","001","010","001","110"},["4"]={"101","101","111","001","001"},["5"]={"111","100","110","001","110"},
  ["6"]={"011","100","111","101","111"},["7"]={"111","001","010","010","010"},["8"]={"111","101","111","101","111"},
  ["9"]={"111","101","111","001","110"},["!"]={"010","010","010","000","010"},["?"]={"110","001","010","000","010"},
}
local function pick(o,a,b,c) return ({a,b,c})[o.size] end
local blueprints={}
blueprints.house={words={"house","home","cottage","hut","cabin","집"},title="house",
  build=function(p,o)
  local w,d,h=pick(o,5,6,8),pick(o,4,5,6),3
  local wall,roof=o.color or "coral",o.accent or "navy"
  box(p,"2x2",wall,0,0,0,w-1,h-1,d-1,true)
  box(p,"plate","cream",1,0,1,w-2,0,d-2)
  local door=math.floor((w-1)/2)
  clear(p,door,0,0); clear(p,door,1,0)
  add(p,"round_2x2","sky",1,1,0); add(p,"round_2x2","sky",w-2,1,0)
  add(p,"round_2x2","sky",0,1,math.floor(d/2)); add(p,"round_2x2","sky",w-1,1,math.floor(d/2))
  add(p,"2x2","gold",door,h-1,0) -- lintel
  add(p,"slope_2x1","sky",door,0,-1,0) -- doorstep
  for k=0,d do
    local zf,zb=k,d-1-k
    if zf>zb then break end
    for x=0,w-1 do
      if zf==zb then add(p,"plate",roof,x,h+k,zf)
      else add(p,"slope_2x2",roof,x,h+k,zf,0); add(p,"slope_2x2",roof,x,h+k,zb,2) end
    end
    for z=zf+1,zb-1 do add(p,"2x2",wall,0,h+k,z); add(p,"2x2",wall,w-1,h+k,z) end
  end
end}
blueprints.tower={words={"tower","lighthouse","탑"},title="tower",build=function(p,o)
  local s,h=pick(o,3,4,5),math.min(o.n or pick(o,5,6,7),7)
  local c=o.color or "cream"
  box(p,"2x2",c,0,0,0,s-1,h-1,s-1,true)
  local mid=math.floor(s/2)
  clear(p,mid,0,0); clear(p,mid,1,0)
  for y=2,h-1,3 do
    add(p,"round_2x2","sky",mid,y,0); add(p,"round_2x2","sky",mid,y,s-1)
    add(p,"round_2x2","sky",0,y,mid); add(p,"round_2x2","sky",s-1,y,mid)
  end
  for z=0,s-1 do for x=0,s-1 do
    if (x==0 or z==0 or x==s-1 or z==s-1) and (x+z)%2==0 then add(p,"2x2",o.accent or "gold",x,h,z) end
  end end
end}
blueprints.castle={words={"castle","fort","palace","성"},title="castle",build=function(p,o)
  local n,c,a=pick(o,9,11,13),o.color or "cream",o.accent or "navy"
  box(p,"2x2",c,0,0,0,n-1,2,n-1,true)
  for x=0,n-1,2 do add(p,"2x2",c,x,3,0); add(p,"2x2",c,x,3,n-1) end
  for z=0,n-1,2 do add(p,"2x2",c,0,3,z); add(p,"2x2",c,n-1,3,z) end
  local mid=math.floor(n/2)
  box(p,nil,nil,mid-1,0,0,mid+1,1,0) -- gate
  add(p,"2x2","gold",mid,3,0)
  for _,t in ipairs({{0,0},{n-3,0},{0,n-3},{n-3,n-3}}) do
    box(p,"2x2",c,t[1],0,t[2],t[1]+2,4,t[2]+2)
    for _,q in ipairs({{0,0},{2,0},{0,2},{2,2}}) do add(p,"2x2",a,t[1]+q[1],5,t[2]+q[2]) end
    add(p,"round_2x2","sky",t[1]+1,3,t[2])
  end
  add(p,"round_2x2","coral",mid,4,mid); add(p,"round_2x2","coral",mid,5,mid) -- flag pole
  add(p,"plate_1x2","rose",mid,6,mid)
end}
blueprints.wall={words={"wall","fence","벽","울타리"},title="wall",build=function(p,o)
  local L,c=o.n or pick(o,7,11,15),o.color or "coral"
  for y=0,2 do
    local x=0
    if y%2==1 then add(p,"2x2",c,0,y,0); x=1 end
    while x<L do
      if x+1<L then add(p,"2x4",c,x,y,0,1); x=x+2 else add(p,"2x2",c,x,y,0); x=x+1 end
    end
  end
  for x=0,L-1,2 do add(p,"2x2",o.accent or "gold",x,3,0) end
end}
blueprints.pyramid={words={"pyramid","피라미드"},title="pyramid",build=function(p,o)
  local n=o.n or pick(o,5,7,9)
  local k=0
  while k<=n-1-k do
    box(p,"2x2",k%2==0 and (o.color or "gold") or (o.accent or "tan"),k,k,k,n-1-k,k,n-1-k,true)
    k=k+1
  end
end}
blueprints.tree={words={"tree","forest","나무"},title="tree",build=function(p,o)
  local h=pick(o,3,4,5)
  for y=0,h-1 do add(p,"round_2x2","brown",2,y,2) end
  for dy=-1,1 do
    local r=dy==1 and 1 or 2
    for dz=-r,r do for dx=-r,r do
      if math.abs(dx)+math.abs(dz)<=r+(r==2 and 1 or 0) then
        local y=h+dy
        local apple=r==2 and (dx+dz+y)%4==0 and math.abs(dx)+math.abs(dz)==3
        add(p,"2x2",apple and (o.accent or "coral") or (o.color or "green"),2+dx,y,2+dz)
      end
    end end
  end
end}
blueprints.car={words={"car","truck","bus","vehicle","자동차"},title="car",build=function(p,o)
  local c,L=o.color or "coral",pick(o,4,5,6)
  for z=0,1 do
    add(p,"round_2x2","navy",0,0,z); add(p,"round_2x2","navy",L-1,0,z)
    for x=1,L-2 do add(p,"plate","cream",x,0,z) end
    for x=0,L-1 do add(p,x==L-1 and "slope_2x2" or "2x2",c,x,1,z,3) end
    for x=1,L-3 do add(p,"2x2","sky",x,2,z) end
    add(p,"slope_2x2","sky",L-2,2,z,3)
    for x=1,L-3 do add(p,"plate",o.accent or c,x,3,z) end
  end
  add(p,"plate_1x2","gold",L-1,2,0); add(p,"plate_1x2","gold",L-1,2,1) -- headlights
end}
blueprints.rocket={words={"rocket","spaceship","로켓"},title="rocket",build=function(p,o)
  local h=pick(o,4,5,6)
  for y=0,h-1 do add(p,"round_2x2",y==math.floor(h/2) and "sky" or (o.color or "cream"),1,y,1) end
  add(p,"round_2x2",o.accent or "coral",1,h,1); add(p,"plate","gold",1,h+1,1)
  add(p,"slope_2x2",o.accent or "coral",2,0,1,3); add(p,"slope_2x2",o.accent or "coral",0,0,1,1)
  add(p,"slope_2x2",o.accent or "coral",1,0,2,2); add(p,"slope_2x2",o.accent or "coral",1,0,0,0)
end}
blueprints.flower={words={"flower","rose","tulip","꽃"},title="flower",build=function(p,o)
  local h=pick(o,2,3,4)
  for y=0,h-1 do add(p,"round_2x2","green",1,y,1) end
  add(p,"slope_2x1","green",2,1,1,1); add(p,"slope_2x1","green",0,0,1,3)
  add(p,"round_2x2",o.accent or "gold",1,h,1)
  for _,d in ipairs({{-1,0},{1,0},{0,-1},{0,1}}) do add(p,"2x2",o.color or "rose",1+d[1],h,1+d[2]) end
  add(p,"plate",o.color or "rose",1,h+1,1)
end}
blueprints.heart={words={"heart","love","하트"},title="heart",build=function(p,o)
  local rows={"0110110","1111111","1111111","0111110","0011100","0001000"}
  for r,row in ipairs(rows) do for x=1,#row do
    if row:sub(x,x)=="1" then add(p,"2x2",o.color or "rose",x-1,#rows-r,0) end
  end end
end}
blueprints.arch={words={"arch","bridge","gate","다리"},title="arch",build=function(p,o)
  local L,c=o.n or pick(o,5,7,9),o.color or "coral"
  for z=0,1 do
    for y=0,2 do add(p,"2x2",c,0,y,z); add(p,"2x2",c,L-1,y,z) end
    for x=0,L-1 do add(p,"2x2",o.accent or "gold",x,3,z) end
    add(p,"slope_2x2",c,1,2,z,3); add(p,"slope_2x2",c,L-2,2,z,1)
  end
end}
blueprints.stairs={words={"stairs","staircase","steps","계단"},title="staircase",build=function(p,o)
  local n=math.min(o.n or pick(o,4,6,8),8)
  for i=0,n-1 do box(p,"2x2",o.color or "tan",0,0,i,1,i,i) end
end}
blueprints.word={words={"write","spell","sign","name"},title="sign",build=function(p,o)
  local x=0
  for ch in (o.text or "HI"):upper():gmatch(".") do
    local g=font[ch]
    if g then
      for r,row in ipairs(g) do for i=1,3 do
        if row:sub(i,i)=="1" then add(p,"2x2",o.color or "violet",x+i-1,5-r,0) end
      end end
      x=x+4
    elseif ch==" " then x=x+2 end
  end
end}
local blueprint_order={"house","tower","castle","wall","pyramid","tree","car","rocket","flower","heart","arch","stairs","word"}

local color_words={
  {"coral",{"red","coral","orange","빨간","빨강","주황"}},{"gold",{"yellow","gold","노란","노랑","금색"}},
  {"mint",{"mint","teal","turquoise","민트","청록"}},{"sky",{"blue","sky","하늘","파란","파랑"}},
  {"violet",{"purple","violet","보라"}},{"cream",{"white","cream","snow","흰","하얀"}},
  {"navy",{"navy","dark blue","black","남색","검은","검정"}},{"rose",{"pink","rose","분홍","핑크"}},
  {"green",{"green","초록","녹색"}},{"brown",{"brown","wood","갈색"}},{"tan",{"tan","beige","sand","베이지"}},
}
local function find_word(text,w)
  if w:find("^[%a ]+$") then return text:find("%f[%a]"..w) end
  return text:find(w,1,true)
end
-- Reads "a big red house with a blue roof" into a blueprint and options.
local function parse_request(text)
  local low=text:lower()
  local best,bpos
  for _,id in ipairs(blueprint_order) do
    for _,w in ipairs(blueprints[id].words) do
      local s=find_word(low,w)
      if s and (not bpos or s<bpos) then best,bpos=id,s end
    end
  end
  if not best then return nil end
  local found={}
  for _,cw in ipairs(color_words) do
    for _,w in ipairs(cw[2]) do
      local s=find_word(low,w)
      -- "dark blue" is navy, not sky.
      if s and not (cw[1]=="sky" and low:find("dark blue",1,true)) then
        found[#found+1]={s=s,color=cw[1]}; break
      end
    end
  end
  table.sort(found,function(a,b) return a.s<b.s end)
  local o={size=2,color=found[1] and found[1].color,accent=found[2] and found[2].color}
  for _,w in ipairs({"small","tiny","little","mini","작은","조그만"}) do if find_word(low,w) then o.size=1 end end
  for _,w in ipairs({"big","large","huge","giant","tall","enormous","큰","커다란","높은"}) do if find_word(low,w) then o.size=3 end end
  local n=tonumber(low:match("%d+"))
  if n and best~="word" then o.n=math.max(2,math.min(20,n)) end
  if best=="word" then
    local s=bpos+#(blueprints.word.words[1])
    for _,w in ipairs(blueprints.word.words) do
      local a,b=find_word(low,w)
      if a==bpos then s=b+1 end
    end
    local rest=text:sub(s):gsub("^%s*:?%s*",""):gsub("[\"'“”]",""):gsub("^[Tt]he%s+[Ww]ord%s+","")
    rest=rest:gsub("%s+in%s+%a+$",""):gsub("%s+with%s+.*$","")
    o.text=rest:sub(1,14)
    if not o.text:upper():find("[A-Z0-9!?]") then return nil end
  end
  return best,o
end
local function blueprint(id,o,turns)
  local p=new_plan()
  blueprints[id].build(p,o)
  return finish(p,turns)
end

-- Plans from Claude: "<piece> <color> x y z [turn]", "box|walls <color> x1 y1 z1 x2 y2 z2",
-- "clear x1 y1 z1 x2 y2 z2". Unknown lines are skipped; the result is capped and clamped.
local function plan_lines(lines)
  local p=new_plan()
  local count=0
  local function n(v) return tonumber(v) and math.floor(tonumber(v)) end
  for _,line in ipairs(lines) do
    local t={}
    for w in tostring(line):lower():gmatch("%S+") do t[#t+1]=w end
    if t[1]=="box" or t[1]=="walls" then
      local c,a={n(t[3]),n(t[4]),n(t[5]),n(t[6]),n(t[7]),n(t[8])},t[2]
      if c[6] and C.registered_nodes["brickcraft:"..(a or "")] and
         math.abs(c[1]-c[4])<MAX_SPAN and math.abs(c[3]-c[6])<MAX_SPAN and math.abs(c[2]-c[5])<24 then
        box(p,"2x2",a,c[1],c[2],c[3],c[4],c[5],c[6],t[1]=="walls")
      end
    elseif t[1]=="clear" then
      local c={n(t[2]),n(t[3]),n(t[4]),n(t[5]),n(t[6]),n(t[7])}
      if c[6] and math.abs(c[1]-c[4])<MAX_SPAN and math.abs(c[3]-c[6])<MAX_SPAN and math.abs(c[2]-c[5])<24 then
        box(p,nil,nil,c[1],c[2],c[3],c[4],c[5],c[6])
      elseif n(t[4]) then clear(p,n(t[2]),n(t[3]),n(t[4])) end
    elseif shapes[t[1] or ""] and C.registered_nodes["brickcraft:"..(t[2] or "")] and n(t[5]) then
      add(p,t[1],t[2],n(t[3]),n(t[4]),n(t[5]),n(t[6]) or 0)
    end
    count=count+1
    if #p.pieces>MAX_PIECES*2 then break end
  end
  return p
end
local function parse_plan(lines,turns) return finish(plan_lines(lines),turns) end

-- The world ----------------------------------------------------------------------------
-- Builders play by the players' rules: they walk (with collision, gravity and the players'
-- walk and jump speeds), reach 7 nodes, point at faces they can see, place against a
-- piece already there, climb by pillar-jumping and dig their scaffold back down. Placing
-- and collecting run the same item callbacks a player's clicks run, with their own brick
-- inventory. The one difference: their bricks are free, so they restock a color that runs out.
local function def_of(pos) return C.registered_nodes[C.get_node(pos).name] end
local function is_free(pos)
  local def=def_of(pos)
  return def and def.buildable_to and pos.y>=-1 -- y -1 is the ground: holes in it can be filled
end
local function walkable(pos) local def=def_of(pos); return not def or def.walkable end
local function node_name(it) return "brickcraft:"..it.color..shapes[it.piece].suffix end
-- Node name -> {piece,color}, for reading what's already built.
local piece_of={}
for _,sh in ipairs(brickcraft.shape_list) do
  for _,color in ipairs(colors) do piece_of["brickcraft:"..color..sh.suffix]={piece=sh.id,color=color} end
end
-- The brick color a node is (scenery is the color it collects as).
local function color_of(name)
  local pc=piece_of[name] or piece_of[(name:gsub("_tail$",""))]
  if pc then return pc.color end
  local def=C.registered_nodes[name]
  if def and def.brickcraft_scenery and type(def.drop)=="string" then return def.drop:match("^brickcraft:(.+)$") end
end
-- The player whose body (.3 around their feet, 1.75 high) is partly inside the cell, if any.
local function player_in(pos)
  for _,pl in ipairs(C.get_connected_players()) do
    local pp=pl:get_pos()
    if math.abs(pp.x-pos.x)<.8 and math.abs(pp.z-pos.z)<.8 and pos.y+.5>pp.y and pos.y-.5<pp.y+1.75 then return pl end
  end
end
-- Worlds are copies of the workshop around their own centers (init.lua). A player's builder
-- works in the world its owner is in; jms stays in the Workshop.
local function center_of(pos) local w=brickcraft.world_at(pos); return {x=w.x,y=0,z=w.z},w end
local function same_world(a,b) local ca,cb=center_of(a),center_of(b); return ca.x==cb.x and ca.z==cb.z end
local workers={} -- owner (a player id, or "jms") -> builder
-- Finds the free baseplate spot nearest to `near` for a w x d footprint with a 1-cell
-- margin, in near's world. Columns with anything standing on the baseplate (y 0..30) are
-- taken, and so are the plots of builds any builder has under way or waiting.
local function find_plot(w,d,near,avoid_spawn)
  local c=center_of(near)
  local vm=C.get_voxel_manip()
  local emin,emax=vm:read_from_map({x=c.x-EDGE,y=0,z=c.z-EDGE},{x=c.x+EDGE,y=30,z=c.z+EDGE})
  local area=VoxelArea:new({MinEdge=emin,MaxEdge=emax})
  local data=vm:get_data()
  local air=C.get_content_id("air")
  local taken={}
  for z=c.z-EDGE,c.z+EDGE do for x=c.x-EDGE,c.x+EDGE do
    for y=0,30 do
      if data[area:index(x,y,z)]~=air then taken[x..","..z]=true; break end
    end
  end end
  for _,pl in ipairs(C.get_connected_players()) do
    local pp=pl:get_pos()
    for _,dx in ipairs({-.3,.3}) do for _,dz in ipairs({-.3,.3}) do
      taken[math.floor(pp.x+dx+.5)..","..math.floor(pp.z+dz+.5)]=true
    end end
  end
  for _,wk in pairs(workers) do
    local bp=wk.pos()
    if bp then taken[math.floor(bp.x+.5)..","..math.floor(bp.z+.5)]=true end
    for _,j in ipairs(wk.jobs()) do
      if j.kind=="build" and j.origin then
        j.size=j.size or bounds(j.list)
        for z=j.origin.z,j.origin.z+j.size.z do for x=j.origin.x,j.origin.x+j.size.x do taken[x..","..z]=true end end
      end
    end
  end
  local best,bd
  for z0=c.z-EDGE+1,c.z+EDGE-d do for x0=c.x-EDGE+1,c.x+EDGE-w do
    local cx,cz=x0+w/2,z0+d/2
    local dist=(cx-near.x)^2+(cz-near.z)^2
    -- Keep the players' start spots (around x -6..6, z 1..4) clear of builders' own builds.
    local spawn=avoid_spawn and x0-c.x<=7 and x0+w-1-c.x>=-7 and z0-c.z<=5 and z0+d-1-c.z>=0
    if not spawn and (not bd or dist<bd) then
      local ok=true
      for z=z0-1,z0+d do
        for x=x0-1,x0+w do if taken[x..","..z] then ok=false; break end end
        if not ok then break end
      end
      if ok then best,bd={x=x0,y=0,z=z0},dist end
    end
  end end
  return best
end

-- The players' numbers: walk speed, jump, gravity, reach (the separator's and bricks' range).
local WALK=tonumber(S:get("movement_speed_walk")) or 4
local JUMP=tonumber(S:get("movement_speed_jump")) or 6.5
local GRAVITY=tonumber(S:get("movement_gravity")) or 9.81
local REACH,EYE=7,1.5

local function feet_of(pos) return {x=math.floor(pos.x+.5),y=math.floor(pos.y+.51),z=math.floor(pos.z+.5)} end
local function eye_of(pos) return {x=pos.x,y=pos.y+EYE,z=pos.z} end
-- What a player at `eye` would point at by aiming at `aim`: the first node the ray hits.
local function point(eye,aim)
  for pt in C.raycast(eye,aim,false,false) do
    if pt.type=="node" then return pt end
  end
end
-- A face a builder can point at to put a piece into `cell`: a neighbor whose face toward
-- the cell is the first thing their line of sight hits, within reach.
local function aim_place(eye,cell)
  for _,d in ipairs(SIDES) do
    local n=vector.add(cell,d)
    local def=def_of(n)
    if def and def.pointable~=false and not def.buildable_to then
      -- Aim into the neighbor near that face (and deeper, for plates and slopes).
      for _,t in ipairs({.45,.2,0,-.3}) do
        local aim=vector.add(n,vector.multiply(vector.subtract(cell,n),t))
        local pt=point(eye,aim)
        if pt and vector.equals(pt.under,n) and vector.equals(pt.above,cell) and
           vector.distance(eye,pt.intersection_point)<=REACH then
          return {type="node",under=n,above=cell},vector.distance(eye,pt.intersection_point)
        end
      end
    end
  end
end
-- Pointing at a placed piece (or its end cell) to collect it.
local function aim_collect(eye,pos,name)
  for _,t in ipairs({0,-.3,.3}) do
    local pt=point(eye,vector.offset(pos,0,t,0))
    if pt and vector.distance(eye,pt.intersection_point)<=REACH and
       (vector.equals(pt.under,pos) or C.get_node(pt.under).name==name.."_tail") then
      return {type="node",under=pt.under,above=pt.above}
    end
  end
end
local function standable(f)
  return not walkable(f) and not walkable(vector.offset(f,0,1,0)) and walkable(vector.offset(f,0,-1,0))
end
-- A cell beside a player where a builder can stand (their own cell if none is free).
local function beside(pl)
  local f=feet_of(pl:get_pos())
  for _,d in ipairs({{1,0},{-1,0},{0,1},{0,-1},{1,1},{-1,-1},{1,-1},{-1,1}}) do
    local to={x=f.x+d[1],y=f.y,z=f.z+d[2]}
    if standable(to) then return to end
  end
  return f
end

-- The players, as a builder sees them (like their nametags on screen): who they play,
-- where they stand and face, and how far and which way from the builder. +z is north.
-- Connections still at "Who's playing?" aren't anyone yet, so they aren't listed.
local COMPASS={"north","north-east","east","south-east","south","south-west","west","north-west"}
local function compass(dx,dz)
  return COMPASS[math.floor(math.deg((math.atan2 or math.atan)(dx,dz))/45+.5)%8+1]
end
-- Fills in how far and which way p (with .pos) is from `me`, or the world p is away in.
local function seen_from(me,p)
  if not me then return p end
  if not same_world(me,p.pos) then p.away=brickcraft.world_at(p.pos).name; return p end
  p.dist,p.dir,p.up=vector.distance(me,p.pos),compass(p.pos.x-me.x,p.pos.z-me.z),p.pos.y-me.y
  return p
end
local function players(me)
  local list={}
  for _,pl in ipairs(C.get_connected_players()) do
    local id,name=brickcraft.playing_as(pl),pl:get_player_name()
    if id then
      local pos,look=pl:get_pos(),C.yaw_to_dir(pl:get_look_horizontal())
      list[#list+1]=seen_from(me,{name=name,id=id,label=brickcraft.styles[id].label,pos=pos,look=look,facing=compass(look.x,look.z)})
    end
  end
  table.sort(list,function(a,b) return (a.dist or math.huge)<(b.dist or math.huge) end)
  return list
end
-- Words that name a player: their label, nicknames, then the connection name.
local NICKNAMES={dad={"daddy","아빠"},daughter={"레오나"},builder={"빌더"},explorer={"탐험가"}}
local function names_of(p)
  local words={p.label:lower()}
  for _,w in ipairs(NICKNAMES[p.id] or {}) do words[#words+1]=w end
  words[#words+1]=p.name:lower()
  return words
end
-- A name as a whole word ("dad" isn't in "daddy"); Korean particles join the name directly.
local function find_name(low,w)
  if not w:find("^[%w _%-]+$") then return low:find(w,1,true) end
  local i=1
  while true do
    local s,e=low:find(w,i,true)
    if not s then return end
    if not low:sub(s-1,s-1):find("[%w_]") and not low:sub(e+1,e+1):find("[%w_]") then return s,e end
    i=s+1
  end
end
local function named_in(text,list)
  local low=text:lower()
  for _,p in ipairs(list) do
    for _,w in ipairs(names_of(p)) do if find_name(low,w) then return p end end
  end
end
-- The builder a text names ("where is Leona bot?"), longest name first.
local function worker_named(low)
  local best
  for _,wk in pairs(workers) do
    if wk.pos() and find_name(low,wk.name:lower()) and (not best or #wk.name>#best.name) then best=wk end
  end
  return best
end
-- "near Leona", "for Dad", "레오나 옆에": the player a build should go by, and the request
-- without those words.
local NEAR_WORDS={"next to","in front of","near","beside","by","for","facing","toward","towards","around"}
local NEAR_KO={"옆","앞","근처","한테","에게","위해"}
local function near_phrase(text,list)
  local low=text:lower()
  for _,p in ipairs(list) do
    for _,w in ipairs(names_of(p)) do
      local phrases={}
      for _,n in ipairs(NEAR_WORDS) do phrases[#phrases+1]=n.." "..w end
      for _,k in ipairs(NEAR_KO) do phrases[#phrases+1]=w.." "..k; phrases[#phrases+1]=w..k end
      for _,ph in ipairs(phrases) do
        local s,e=find_name(low,ph)
        if s then
          local rest=(text:sub(1,s-1)..text:sub(e+1)):gsub("^[%s,]+",""):gsub("[%s,]+$",""):gsub("%s%s+"," ")
          return p,rest
        end
      end
    end
  end
end
local function blocks(n)
  n=math.floor(n+.5)
  return n==1 and "1 block" or n.." blocks"
end
-- "Leona is 9 blocks north-east of me (4 blocks west of you), facing south."
local function where(p,asker)
  local s=(p.name==asker and "You're" or p.label.." is")
  if p.away then return s.." in "..p.away..", facing "..p.facing.."." end
  if not p.dist then return s.." somewhere, facing "..p.facing.."." end
  s=s..(p.dist<2.5 and " right next to me" or " "..blocks(p.dist).." "..p.dir.." of me")
  if p.up>2.5 then s=s..", "..blocks(p.up).." up" elseif p.up< -2.5 then s=s..", "..blocks(-p.up).." down" end
  local a=asker~=p.name and C.get_player_by_name(asker)
  if a and same_world(a:get_pos(),p.pos) then
    local ap=a:get_pos()
    local d=vector.distance(ap,p.pos)
    s=s..(d<2.5 and " (right next to you)" or " ("..blocks(d).." "..compass(p.pos.x-ap.x,p.pos.z-ap.z).." of you)")
  end
  return s..", facing "..p.facing.."."
end

local function front_of(name)
  local pl=C.get_player_by_name(name)
  if not pl then return {x=0,z=0},0 end
  local pos,dir=pl:get_pos(),pl:get_look_dir()
  local h=vector.normalize({x=dir.x,y=0,z=dir.z})
  if h.x~=h.x then h={x=0,y=0,z=1} end
  return {x=pos.x+h.x*7,z=pos.z+h.z*7},pos
end
-- Turns that make the build's front (-z) face a point.
local function turns_toward(from,to)
  local d={x=to.x-from.x,y=0,z=to.z-from.z}
  if d.x==0 and d.z==0 then return 0 end
  return (C.dir_to_facedir(d)-2)%4
end
-- Taking a build down: the builder collects its pieces, top first, with the separator.
local function takedown(j,by)
  local list={}
  for i=#j.placed,1,-1 do list[#list+1]=j.placed[i] end
  return {kind="collect",title=j.title,by=by,list=list,i=1,n=0,scaffold={},of=j}
end
local function plan_for(text,name,near,from)
  local id,o=parse_request(text)
  if not id then return nil end
  -- Face the front toward the asker, seen from where the build will roughly go.
  local turns=from and turns_toward(near,from) or 0
  return blueprint(id,o,turns),(o.color and o.color.." " or "")..(id=="word" and "sign \""..o.text.."\"" or blueprints[id].title)
end

-- Maintenance ---------------------------------------------------------------------------
-- A builder looks over what's already there, as a player walking by would: holes in the
-- ground (y -1 is solid all around each world's center) and gaps in walls (an empty cell
-- with bricks on both sides, above and below; a doorway has air above, so it isn't one).
local GROUND=30                -- how far out from a world's center the flat ground is checked
local PATCH_AFTER=tonumber(S:get("brickcraft_ai_patch_after")) or 300 -- seconds a fresh dig is left alone
local dug={}                   -- when players dug cells
C.register_on_dignode(function(pos,_,digger)
  if digger and digger.get_player_name and not digger:get_player_name():find(" %(AI%)$") then
    dug[key(pos.x,pos.y,pos.z)]=os.time()
  end
end)
local function survey(minp,maxp,gaps)
  local c=center_of({x=(minp.x+maxp.x)/2,y=0,z=(minp.z+maxp.z)/2})
  local vm=C.get_voxel_manip()
  local emin,emax=vm:read_from_map(vector.offset(minp,-1,-1,-1),vector.offset(maxp,1,1,1))
  local area=VoxelArea:new({MinEdge=emin,MaxEdge=emax})
  local data=vm:get_data()
  local air=C.get_content_id("air")
  local solid={}
  local function at(x,y,z)
    local id=data[area:index(x,y,z)]
    if solid[id]==nil then
      local def=C.registered_nodes[C.get_name_from_content_id(id)]
      solid[id]=def and def.walkable or false
    end
    return solid[id]
  end
  local holes={}
  for z=minp.z,maxp.z do for x=minp.x,maxp.x do
    if minp.y<=-1 and math.abs(x-c.x)<=GROUND and math.abs(z-c.z)<=GROUND and data[area:index(x,-1,z)]==air then
      holes[#holes+1]={x=x,y=-1,z=z,ground=true}
    end
    if gaps then
      for y=math.max(minp.y,0),maxp.y do
        if data[area:index(x,y,z)]==air and at(x,y-1,z) and at(x,y+1,z) and
           ((at(x-1,y,z) and at(x+1,y,z)) or (at(x,y,z-1) and at(x,y,z+1))) then holes[#holes+1]={x=x,y=y,z=z} end
      end
    end
  end end
  return holes
end
-- Puts pieces at fixed world spots (origin + their cells). Cells that aren't free (unless
-- in `freed`, about to be emptied) or are above y 8 are dropped; each piece comes after
-- one it touches, counting what's already in the world.
local function order_in_world(items,origin,freed)
  freed=freed or {}
  local taken,list={},{}
  for _,it in ipairs(items) do
    local ok=#list<MAX_PIECES
    for _,c in ipairs(cells_of(it)) do
      local w=vector.add(origin,c)
      local k=key(w.x,w.y,w.z)
      if taken[k] or w.y>8 or not (freed[k] or is_free(w)) then ok=false end
    end
    if ok then
      for _,c in ipairs(cells_of(it)) do local w=vector.add(origin,c); taken[key(w.x,w.y,w.z)]=true end
      list[#list+1]=it
    end
  end
  table.sort(list,function(a,b)
    if a.y~=b.y then return a.y<b.y end
    if a.z~=b.z then return a.z<b.z end
    return a.x<b.x
  end)
  local placed,order={},{}
  local function solid(w)
    local k=key(w.x,w.y,w.z)
    if placed[k] then return true end
    if freed[k] or taken[k] then return false end
    return walkable(w)
  end
  local function touches(it)
    for _,c in ipairs(cells_of(it)) do
      local w=vector.add(origin,c)
      for _,d in ipairs(SIDES) do if solid(vector.add(w,d)) then return true end end
    end
  end
  local progress=true
  while progress do
    progress=false
    for i,it in ipairs(list) do
      if it and touches(it) then
        order[#order+1]=it; list[i]=false; progress=true
        for _,c in ipairs(cells_of(it)) do local w=vector.add(origin,c); placed[key(w.x,w.y,w.z)]=true end
        break
      end
    end
  end
  return order
end
-- Fills holes with a 2x2 brick in the color most of its neighbors are.
local function patch_plan(holes)
  local o={x=math.huge,y=0,z=math.huge}
  for _,h in ipairs(holes) do o.x,o.z=math.min(o.x,h.x),math.min(o.z,h.z) end
  local items={}
  for _,h in ipairs(holes) do
    local count,best={},nil
    for _,d in ipairs(SIDES) do
      local c=color_of(C.get_node(vector.add(h,d)).name)
      if c then count[c]=(count[c] or 0)+1; if not best or count[c]>count[best] then best=c end end
    end
    items[#items+1]={piece="2x2",color=best or (h.ground and "green" or "tan"),x=h.x-o.x,y=h.y,z=h.z-o.z,turn=0}
  end
  return order_in_world(items,o),o
end
-- The 16 x 16 area in front of a player (its corner at y 0).
local function area_of(name)
  local pl=C.get_player_by_name(name)
  local pos,look=pl:get_pos(),C.yaw_to_dir(pl:get_look_horizontal())
  return {x=math.floor(pos.x+look.x*4+.5)-8,y=0,z=math.floor(pos.z+look.z*4+.5)-8}
end
local function area_box(o) return {x=o.x,y=-1,z=o.z},{x=o.x+15,y=8,z=o.z+15} end
-- What a builder tells Claude about the area, in the area's coordinates.
local function describe(o)
  local lines={}
  local minp,maxp=area_box(o)
  for y=minp.y,maxp.y do for z=minp.z,maxp.z do for x=minp.x,maxp.x do
    local name=C.get_node({x=x,y=y,z=z}).name
    local pc,def=piece_of[name],C.registered_nodes[name]
    local at=(x-o.x).." "..y.." "..(z-o.z)
    if pc then lines[#lines+1]=pc.piece.." "..pc.color.." "..at.." "..C.get_node({x=x,y=y,z=z}).param2%4
    elseif def and def.brickcraft_scenery and y>=0 then lines[#lines+1]=name:gsub("^brickcraft:","").." "..at end
  end end end
  for _,h in ipairs(survey(minp,maxp,true)) do
    lines[#lines+1]=(h.ground and "hole " or "gap ")..(h.x-o.x).." "..h.y.." "..(h.z-o.z)
  end
  for _,p in ipairs(players()) do
    local f=feet_of(p.pos)
    if f.x>=minp.x and f.x<=maxp.x and f.z>=minp.z and f.z<=maxp.z then
      lines[#lines+1]="player "..p.label.." "..(f.x-o.x).." "..f.y.." "..(f.z-o.z).." facing "..p.facing
    end
  end
  if #lines>1500 then lines={unpack(lines,1,1500)}; lines[#lines+1]="(more not listed)" end
  return table.concat(lines,"\n")
end
-- Claude's changes: pieces to collect first (only bricks), then pieces to add in place.
local function edit_jobs(reply,o,title,by)
  local freed,down={},nil
  for i,line in ipairs(type(reply.remove)=="table" and reply.remove or {}) do
    if i>200 then break end
    local x,y,z=tostring(line):match("^%s*(%-?%d+)[%s,]+(%-?%d+)[%s,]+(%-?%d+)")
    if x then
      local pos={x=o.x+x,y=tonumber(y),z=o.z+z}
      local node=C.get_node(pos)
      if piece_of[node.name] then
        down=down or {kind="collect",title="old pieces for the "..title,by=by,list={},i=1,n=0,scaffold={},part=true}
        down.list[#down.list+1]={pos=pos,name=node.name,param2=node.param2}
        freed[key(pos.x,pos.y,pos.z)]=true
        if shapes[piece_of[node.name].piece].long then
          local d=C.facedir_to_dir(node.param2%4)
          freed[key(pos.x+d.x,pos.y,pos.z+d.z)]=true
        end
      end
    end
  end
  local items={}
  for _,it in ipairs(plan_lines(reply.lines).pieces) do if it then items[#items+1]=it end end
  -- Top first when taking pieces away.
  if down then table.sort(down.list,function(a,b) return a.pos.y>b.pos.y end) end
  return order_in_world(items,o,freed),down
end
local HOLE_WORDS={"hole","holes","gap","gaps","fill","patch","plug","구멍","메워","메꿔","채워"}
local EDIT_VERBS={fix=1,repair=1,mend=1,finish=1,complete=1,add=1,extend=1,decorate=1,improve=1,change=1,
  paint=1,replace=1,tidy=1,clean=1,rebuild=1,redo=1}
local EDIT_KO={"고쳐","수리","완성","추가","꾸며","바꿔","정리","없애","치워"}
local function about_holes(low)
  for _,w in ipairs(HOLE_WORDS) do if find_name(low,w) then return true end end
end
local function is_edit(low)
  if about_holes(low) then return true end
  local first=low:gsub("^please%s+",""):gsub("^can you%s+",""):gsub("^could you%s+",""):gsub("^can we%s+","")
    :gsub("^let'?s%s+",""):match("^%a+")
  if first and EDIT_VERBS[first] then return true end
  for _,w in ipairs(EDIT_KO) do if low:find(w,1,true) then return true end end
end
-- "Are you there?", "hi": checking on a builder rather than asking for something.
local HELLO_WORDS={"are you there","you there","hello","hi","hey","안녕","거기 있"}
local function is_hello(low)
  for _,w in ipairs(HELLO_WORDS) do if find_name(low,w) then return true end end
end
-- A line that asks a builder for something, even without its name.
local BUILD_WORDS={"build","make","write","create","draw","put","place","help","undo","stop",
  "만들","지어","짓","써","그려","놓아"}
local function asks_for_work(low)
  if is_edit(low) then return true end
  for _,w in ipairs(BUILD_WORDS) do if find_name(low,w) then return true end end
end
-- A question or remark rather than a request ("what doesn't look like a building?",
-- "thanks!"): the builder answers in words.
local QUESTION_WORDS={what=1,why=1,how=1,which=1,when=1,is=1,are=1,was=1,were=1,["do"]=1,does=1,did=1,
  should=1,would=1,could=1,will=1}
local TALK_WORDS={"thank","thanks","great","cool","nice","wow","ok","okay","lol","뭐","왜","어떻게","어느",
  "언제","고마워","좋아","멋져","있어?"}
local function is_talk(low)
  if asks_for_work(low) then return false end
  if low:find("%?%s*$") or QUESTION_WORDS[low:match("^%a+") or ""] then return true end
  for _,w in ipairs(TALK_WORDS) do if find_name(low,w) then return true end end
end

local SYSTEM=[[You design brick builds for BrickCraft, a toy-brick sandbox a family (kids included) plays together. You are jms, the friendly AI builder who lives in the workshop.

The world is a grid of cells and one cell holds one piece. Axes: x goes right, y goes up, z goes away from the viewer. The front of the build faces -z (the person who asked stands at -z, looking toward +z). The ground is y = 0. Use x and z from 0 to 15 and y from 0 to 7: you build like the players do, from the ground and short scaffolds, so nothing goes higher than y = 7.

Answer with one JSON object and nothing else (no prose, no code fence):
- "say": one short, friendly sentence to the person who asked, in their language.
- "title": two or three words naming the build, in English.
- "lines": the build, one instruction per string:
  "<piece> <color> x y z [turn]" places one piece.
  "box <color> x1 y1 z1 x2 y2 z2" fills a solid box with 2x2 bricks.
  "walls <color> x1 y1 z1 x2 y2 z2" builds only the four side walls of that box (hollow, no floor or roof).
  "clear x1 y1 z1 x2 y2 z2" empties that box of anything earlier lines put there (doors, windows).
  Later lines replace earlier ones in the same cell.

Pieces:
- 2x2: brick, fills its cell.
- 1x2: half-width brick in the left half of its cell (turn rotates it).
- 2x4: long brick over two cells: its cell and the next one in the turn direction.
- plate, plate_1x2, plate_2x4: a third as tall as a brick, same footprints. Good for floors, roofs and details.
- round_2x2: round brick. Columns, wheels, portholes, tree trunks, eyes.
- slope_2x2: 45-degree roof slope whose high side faces the turn direction. slope_2x1: the half-width slope.
Turn: 0 = +z, 1 = +x, 2 = -z, 3 = -x (default 0). A roof rising from the front toward the back uses turn 0 on the front row and turn 2 on the back row.
Colors: coral (red-orange), gold (yellow), mint (teal), sky (light blue), violet (purple), cream (white), navy (dark blue), rose (pink), green, brown, tan.

Keep it under 400 pieces after boxes are filled. Like a player, you place each piece against one already there (or the ground), so every piece must touch another piece or the ground; pieces touching nothing are skipped. Make the build recognizable from the front and from above, with chunky toy proportions, and use colors to tell the parts apart. Hollow shells read as well as solid ones and use fewer pieces.]]

-- Pieces added to the game later are offered too, by their catalog names.
do
  local described={["2x2"]=1,["1x2"]=1,["2x4"]=1,plate=1,plate_1x2=1,plate_2x4=1,round_2x2=1,slope_2x2=1,slope_2x1=1}
  local more={}
  for _,s in ipairs(brickcraft.shape_list) do
    if not described[s.id] then more[#more+1]=s.id.." ("..s.label..")" end
  end
  if #more>0 then SYSTEM=SYSTEM.."\nMore pieces you can use, by id: "..table.concat(more,", ")..
    ". 1x1 pieces fill one corner of their cell; tiles are smooth plates; an inverted slope has its sloped face underneath, toward -z at turn 0." end
end

-- Work on what's already there: jms describes the area in front of the asker, as he sees it.
local SYSTEM_EDIT=[[You are jms, the friendly AI builder in BrickCraft, a toy-brick sandbox a family (kids included) plays together. Someone asked you to work on what is already built near them: fix, finish, change, decorate or take away part of it. You get the area as a list and answer with the changes.

The area is a grid of cells, one piece per cell: x and z from 0 to 15, y from -1 to 8. x goes east, z goes north, y goes up. y = -1 is the ground layer, solid everywhere except where a "hole" line says it is missing. The list has one line per thing there:
  "<piece> <color> x y z turn": a piece.
  "grass|dirt|trunk|leaves x y z": scenery.
  "hole x y z": a missing ground cell. "gap x y z": an empty cell with bricks on both sides, above and below; often a missing brick, but doors and windows are gaps on purpose.
  "player <name> x y z facing <direction>": where people stand (two cells high). Never put pieces in their cells.

Answer with one JSON object and nothing else (no prose, no code fence):
- "say": one short, friendly sentence to the person who asked, in their language.
- "title": two or three words naming the work, in English.
- "lines": pieces to add, in the area's coordinates: "<piece> <color> x y z [turn]", "box <color> x1 y1 z1 x2 y2 z2" (solid 2x2 bricks), "walls <color> x1 y1 z1 x2 y2 z2" (only the four side walls). A new piece goes only into an empty cell (or one you remove), and like a player you place each piece against one already there, so every new piece must touch an existing piece, the ground or another new piece. Use y up to 8.
- "remove": cells to empty, "x y z" each, only to replace or take away what the request asks for.
Change only what the request is about and keep everything else as it is. Match the colors and pieces already used. Keep it under 300 pieces.

]]..SYSTEM:match("(Pieces:.-)\n\nKeep it under")..(SYSTEM:match("(\nMore pieces.*)$") or "")

-- Talking: a question or remark, answered with what the builder sees in front of the person.
local SYSTEM_CHAT=[[You are jms, the friendly AI builder in BrickCraft, a toy-brick sandbox a family (kids included) plays together. Someone said something to you in chat that isn't a plain build request: a question, a remark, a thank-you. You get what is in front of them and what you are doing.

The area is a grid: x and z from 0 to 15 (x east, z north), y from -1 (the ground) to 8, one line per thing: "<piece> <color> x y z turn", "grass|dirt|trunk|leaves x y z" (scenery), "hole x y z" (a missing ground cell), "gap x y z" (an empty cell between bricks), "player <name> x y z facing <direction>".

Answer with one JSON object and nothing else (no prose, no code fence):
- "say": one or two short, friendly sentences back to them, in their language. When they ask about what's around, talk about what you see in the list, in words a kid understands (no coordinates).
- "do": only if they asked you to do something, even indirectly ("can we clean this up?"): the request in plain words for you to carry out, like "build a red house", "fill the holes here", "take away the loose bricks here" or "fix the roof here". Otherwise leave it out. Never do something they didn't ask for; offer it in "say" instead.]]

-- One Local AI API serves every builder: at most CLAUDE_MAX requests at once, the rest wait.
local CLAUDE_MAX=tonumber(S:get("brickcraft_ai_parallel")) or 2
local in_flight,waiting=0,{}
-- ok(reply) says whether a reply is usable (default: it has build lines).
local function ask_claude(system,content,done,ok)
  if in_flight>=CLAUDE_MAX then waiting[#waiting+1]={system,content,done,ok}; return end
  local body={model=MODEL,max_tokens=16000,messages={{role="system",content=system},{role="user",content=content}}}
  in_flight=in_flight+1
  http.fetch({url=URL,method="POST",timeout=300,data=C.write_json(body),
    extra_headers={"Content-Type: application/json"}},
    function(res)
      in_flight=in_flight-1
      local nxt=table.remove(waiting,1)
      if nxt then ask_claude(nxt[1],nxt[2],nxt[3],nxt[4]) end
      local data=res.succeeded and res.code==200 and C.parse_json(res.data or "",nil)
      local text=type(data)=="table" and type(data.choices)=="table" and data.choices[1] and
        data.choices[1].message and data.choices[1].message.content
      -- The object may come wrapped in a code fence or a sentence; take the outer braces.
      local reply=type(text)=="string" and C.parse_json(text:match("%b{}") or "",nil)
      if type(reply)~="table" or not (ok and ok(reply) or not ok and type(reply.lines)=="table") then
        C.log("warning","[ai] Claude Code request failed: "..tostring(res.code).." "..tostring(res.data):sub(1,300))
        return done(nil)
      end
      done(reply)
    end)
end

local function list_blueprints()
  return "house, tower, castle, wall, pyramid, tree, car, rocket, flower, heart, arch, stairs, or \"write HELLO\""
end

-- Builders' names ---------------------------------------------------------------------------
-- Each player names their own builder (default "Leona bot"); jms's name is the host's
-- (brickcraft_ai_name). A name is what players call it in chat, so it can't be anyone else's.
local function stored_name(owner)
  if owner=="jms" then return NAME end
  local n=storage:get_string("ai_name_"..owner)
  return n~="" and n or brickcraft.styles[owner].label.." bot"
end
local function name_problem(new,owner)
  if new=="" then return "A name needs at least one letter." end
  if select(2,new:gsub("[^\128-\191]",""))>16 or new:find("[%c,:;!?@/\\\"'%[%]%(%)<>#%%]") then
    return "Pick a name with letters, numbers and spaces, up to 16 letters."
  end
  local low=new:lower()
  if low=="bot" or low=="my bot" or low:find("^bot ") or low:find("^my bot ") or low==LNAME then
    return "\""..new.."\" is taken. Pick another name."
  end
  for id,st in pairs(brickcraft.styles) do
    if id~=owner and stored_name(id):lower()==low then return st.label.."'s builder is already called "..new.."." end
    local p={id=id,label=st.label,name=st.label}
    for _,w in ipairs(names_of(p)) do if w==low then return "That's a player's name. Pick another one." end end
  end
  for _,pl in ipairs(C.get_connected_players()) do
    if pl:get_player_name():lower()==low then return "That's a player's name. Pick another one." end
  end
end
local function owner_player(owner)
  for _,pl in ipairs(C.get_connected_players()) do
    if brickcraft.playing_as(pl)==owner then return pl end
  end
end

-- A builder: a block person steered like a player's controls.
C.register_entity("brickcraft:ai_builder",{
  initial_properties={visual="mesh",mesh="brickcraft_person_short.obj",textures={"brickcraft_person_jms.png"},
    visual_size={x=10,y=10},collisionbox={-.3,0,-.3,.3,1.75,.3},selectionbox={-.3,0,-.3,.3,1.75,.3},
    physical=true,collide_with_objects=false,stepheight=.6,pointable=true,static_save=false,
    nametag="",nametag_color="#f5872c",nametag_bgcolor="#14293699"},
  on_activate=function(self)
    self.object:set_armor_groups({immortal=1})
    self.object:set_acceleration({x=0,y=-GRAVITY,z=0})
  end,
  on_rightclick=function(self,clicker)
    if self._worker and clicker and clicker:is_player() then self._worker.show(clicker) end
  end,
  on_step=function(self,dtime,moveresult)
    if self._worker then self._worker.move(self.object,dtime,moveresult) else self.object:remove() end
  end,
})

-- Small talk: a builder says hi when someone comes over and chats a little while they stay
-- near, at most once per CHAT_GAP seconds each, and only once chat has been quiet a while
-- so it never talks over people. A player's builder talks only with its owner.
local SMALL_TALK=S:get_bool("brickcraft_ai_small_talk",true)
local CHAT_GAP=tonumber(S:get("brickcraft_ai_chat_gap")) or 240
local QUIET=8      -- quiet seconds before saying hi; lingering chat waits for 4x that
local NEARBY=6
local function either(...) local t={...}; return t[math.random(#t)] end
local function names(list)
  local labels={}
  for _,p in ipairs(list) do labels[#labels+1]=p.label end
  if #labels<=2 then return table.concat(labels," and ") end
  return table.concat(labels,", ",1,#labels-1)..", and "..labels[#labels]
end

-- What a builder uses from above, handed over in one table: LuaJIT allows a function at
-- most 60 upvalues. The settings that change while running (quiet, IDLE, small talk) stay upvalues.
local lib={
  AUTO_MAX=AUTO_MAX,C=C,EYE=EYE,GROUND=GROUND,JUMP=JUMP,NEARBY=NEARBY,PATCH_AFTER=PATCH_AFTER,
  QUIET=QUIET,REACH=REACH,S=S,STEP=STEP,SYSTEM=SYSTEM,SYSTEM_EDIT=SYSTEM_EDIT,WALK=WALK,
  about_holes=about_holes,asks_for_work=asks_for_work,is_hello=is_hello,aim_collect=aim_collect,
  aim_place=aim_place,area_box=area_box,area_of=area_of,ask_claude=ask_claude,beside=beside,
  blocks=blocks,blueprint=blueprint,bounds=bounds,cells_of=cells_of,center_of=center_of,
  colors=colors,compass=compass,def_of=def_of,display_name=display_name,dug=dug,edit_jobs=edit_jobs,
  either=either,eye_of=eye_of,feet_of=feet_of,find_plot=find_plot,find_word=find_word,
  front_of=front_of,is_edit=is_edit,is_free=is_free,key=key,list_blueprints=list_blueprints,
  name_problem=name_problem,named_in=named_in,names=names,near_phrase=near_phrase,
  node_name=node_name,owner_player=owner_player,parse_plan=parse_plan,patch_plan=patch_plan,
  plan_for=plan_for,player_in=player_in,players=players,same_world=same_world,seen_from=seen_from,
  shapes=shapes,standable=standable,storage=storage,stored_name=stored_name,survey=survey,
  takedown=takedown,turns_toward=turns_toward,use_claude=use_claude,walkable=walkable,where=where,
  worker_named=worker_named,workers=workers,SYSTEM_CHAT=SYSTEM_CHAT,is_talk=is_talk,
  parse_request=parse_request,describe=describe}
-- One builder per owner: jms (owner "jms", the host's, in the Workshop) or a player's.
-- Each has its own body, bricks, jobs and saved state.
local function new_worker(owner)
  local AUTO_MAX,C,EYE,GROUND,JUMP,NEARBY,PATCH_AFTER,QUIET,REACH,S,STEP,SYSTEM,SYSTEM_EDIT,WALK,
    about_holes,asks_for_work,is_hello,aim_collect,aim_place,area_box,area_of,ask_claude,beside,
    blocks,blueprint,bounds,cells_of,center_of,colors,compass,def_of,display_name,dug,edit_jobs,
    either,eye_of,feet_of,find_plot,find_word,front_of,is_edit,is_free,key,list_blueprints,
    name_problem,named_in,names,near_phrase,node_name,owner_player,parse_plan,patch_plan,plan_for,
    player_in,players,same_world,seen_from,shapes,standable,storage,stored_name,survey,takedown,
    turns_toward,use_claude,walkable,where,worker_named,workers,SYSTEM_CHAT,is_talk,parse_request,
    describe=
    lib.AUTO_MAX,lib.C,lib.EYE,lib.GROUND,lib.JUMP,lib.NEARBY,lib.PATCH_AFTER,lib.QUIET,lib.REACH,
    lib.S,lib.STEP,lib.SYSTEM,lib.SYSTEM_EDIT,lib.WALK,lib.about_holes,lib.asks_for_work,
    lib.is_hello,lib.aim_collect,lib.aim_place,lib.area_box,lib.area_of,lib.ask_claude,lib.beside,
    lib.blocks,lib.blueprint,lib.bounds,lib.cells_of,lib.center_of,lib.colors,lib.compass,
    lib.def_of,lib.display_name,lib.dug,lib.edit_jobs,lib.either,lib.eye_of,lib.feet_of,
    lib.find_plot,lib.find_word,lib.front_of,lib.is_edit,lib.is_free,lib.key,lib.list_blueprints,
    lib.name_problem,lib.named_in,lib.names,lib.near_phrase,lib.node_name,lib.owner_player,
    lib.parse_plan,lib.patch_plan,lib.plan_for,lib.player_in,lib.players,lib.same_world,
    lib.seen_from,lib.shapes,lib.standable,lib.storage,lib.stored_name,lib.survey,lib.takedown,
    lib.turns_toward,lib.use_claude,lib.walkable,lib.where,lib.worker_named,lib.workers,
    lib.SYSTEM_CHAT,lib.is_talk,lib.parse_request,lib.describe
  local w={owner=owner,jms=owner=="jms",name=stored_name(owner)}
  local style=not w.jms and brickcraft.styles[owner]
  local TAG=style and style.tag or "#f5872c"
  local sk=w.jms and "" or "_"..owner -- storage keys (jms keeps the ones from before there were more)
  local function id() return w.name.." (AI)" end -- the player name for the callbacks; never a real connection
  local function say(text)
    quiet=0
    C.chat_send_all(C.colorize(TAG,"<"..w.name.."> ")..text)
    C.log("action","[ai] "..w.name..": "..text)
  end
  local function owner_pl() return not w.jms and owner_player(owner) end
  local function is_owner(name)
    local pl=not w.jms and C.get_player_by_name(name)
    return pl and brickcraft.playing_as(pl)==owner or false
  end

  -- Its bricks: the same 32-slot main list as a player's, shown when it is right-clicked.
  local inv=C.create_detached_inventory("brickcraft_ai"..sk,{
    allow_move=function() return 0 end,allow_put=function() return 0 end,allow_take=function() return 0 end})
  inv:set_size("main",32)
  do
    local saved=C.deserialize(storage:get_string("ai_bricks"..sk))
    if saved then for i=1,32 do inv:set_stack("main",i,saved[i] or "") end
    else
      inv:set_stack("main",1,"brickcraft:separator")
      for i,color in ipairs(colors) do inv:set_stack("main",i+1,"brickcraft:"..color.." 24") end
    end
  end
  local function save_bricks()
    local items={}
    for i,stack in ipairs(inv:get_list("main")) do items[i]=stack:to_string() end
    storage:set_string("ai_bricks"..sk,C.serialize(items))
  end
  local stats={placed=0,collected=0,restocks=0,max_reach=0,inside=0,scaffold=0,skipped=0,homes=0}
  -- The slot holding an item, restocked (free) when it has fewer than `need`.
  local function slot_for(item,need)
    local empty
    for i,stack in ipairs(inv:get_list("main")) do
      if stack:get_name()==item then
        if need and stack:get_count()<need then inv:set_stack("main",i,item.." 99"); stats.restocks=stats.restocks+1 end
        return i
      end
      if not empty and stack:is_empty() then empty=i end
    end
    if empty and need then inv:set_stack("main",empty,item.." 99"); stats.restocks=stats.restocks+1 end
    return empty
  end

  -- A stand-in player: what place_brick, collect and core.node_dig ask of the player
  -- whose click they handle.
  local bot
  local function bot_ok() return bot and bot:get_pos() and true end
  local meta_data,wield,look={}, 1, {x=0,y=0,z=1}
  local hands_meta={get_string=function(_,k) return meta_data[k] or "" end,set_string=function(_,k,v) meta_data[k]=v end,
    get_int=function(_,k) return tonumber(meta_data[k]) or 0 end,set_int=function(_,k,v) meta_data[k]=v end}
  local hands={
    is_player=function() return true end, get_player_name=function() return id() end,
    get_inventory=function() return inv end, get_wield_list=function() return "main" end,
    get_wield_index=function() return wield end,
    get_wielded_item=function() return inv:get_stack("main",wield) end,
    set_wielded_item=function(_,stack) inv:set_stack("main",wield,stack); return true end,
    get_meta=function() return hands_meta end, get_look_dir=function() return look end,
    get_pos=function() return bot_ok() and bot:get_pos() end,
    get_player_control=function() return {} end, hud_change=function() end,
  }
  local function bot_cells()
    local f=feet_of(bot:get_pos())
    return {f,{x=f.x,y=f.y+1,z=f.z}}
  end
  local function bot_in(cells)
    if not bot_ok() then return false end
    for _,b in ipairs(bot_cells()) do
      for _,c in ipairs(cells) do if vector.equals(b,c) then return true end end
    end
  end
  -- Another builder standing in a cell.
  local function other_in(cell)
    for _,wk in pairs(workers) do if wk~=w and wk.body_in({cell}) then return wk end end
  end

  -- Placing and collecting through the players' item callbacks.
  local function place(it,pointed,eye)
    local s=shapes[it.piece]
    local item="brickcraft:"..it.color
    wield=slot_for(item,s.cost)
    if not wield then return false end
    look=vector.direction(eye,pointed.above)
    -- Q-turns from the way the builder faces, exactly as a player picks a piece's turn.
    meta_data.brickcraft_shape=it.piece
    meta_data.brickcraft_turn=(it.turn-C.dir_to_facedir(look))%4
    local stack=inv:get_stack("main",wield)
    inv:set_stack("main",wield,stack:get_definition().on_place(stack,hands,pointed))
    local node=C.get_node(pointed.above)
    return node.name==node_name(it) and node.param2==it.turn%4
  end
  local function collect(pointed,eye)
    wield=slot_for("brickcraft:separator") or 1
    if inv:get_stack("main",wield):get_name()~="brickcraft:separator" then
      inv:set_stack("main",wield,"brickcraft:separator") -- it never loses its separator
    end
    -- Free bricks: make room in its inventory if a stack is close to full.
    local drop=def_of(pointed.under).drop
    if drop and not inv:room_for_item("main",drop) then
      local i=slot_for(ItemStack(drop):get_name())
      if i then inv:set_stack("main",i,ItemStack(drop):get_name().." 99") end
    end
    look=vector.direction(eye,pointed.under)
    C.registered_tools["brickcraft:separator"].on_use(inv:get_stack("main",wield),hands,pointed)
    local done=C.get_node(pointed.under).name=="air"
    if done then stats.collected=stats.collected+1 end
    return done
  end

  -- Where it lives and works: jms in the Workshop, a player's builder in its owner's world,
  -- next to the owner's start spot.
  local function base()
    if w.jms then return {x=0,y=0,z=0} end
    local pl=owner_pl()
    return pl and pl:get_pos() or bot_ok() and bot:get_pos() or {x=0,y=0,z=0}
  end
  local function home()
    if w.jms then return {x=9,y=0,z=3} end
    local pl=owner_pl()
    if pl then
      local h=brickcraft.home_pos(pl,center_of(pl:get_pos()))
      return {x=h.x+1,y=0,z=h.z}
    end
    return bot_ok() and feet_of(bot:get_pos()) or {x=9,y=0,z=3}
  end

  local path,mode,grounded={}, nil, false
  local climb       -- {top=feet y to reach} while pillar-jumping
  local stuck_t,last_dist=0,nil
  local function spawn()
    local saved=C.deserialize(storage:get_string("ai_pos"..sk))
    local pl=owner_pl()
    local at=saved
    if pl and not (saved and same_world(saved,pl:get_pos())) then at=vector.offset(beside(pl),0,-.5,0) end
    bot=C.add_entity(at or vector.offset(home(),0,-.5,0),"brickcraft:ai_builder")
    if not bot then return end
    bot:get_luaentity()._worker=w
    bot:set_properties({nametag=id(),nametag_color=TAG,
      textures={"brickcraft_person_jms.png"..(w.jms and "" or "^[colorize:"..TAG..":110")}})
    path,mode,climb={},nil,nil
  end
  local function set_path(p)
    path=p or {}
    if bot_ok() and path[1] and vector.equals(path[1],feet_of(bot:get_pos())) then table.remove(path,1) end
    mode=#path>0 and "walk" or nil
    stuck_t,last_dist=0,nil
  end
  local function find_path(to)
    local from=feet_of(bot:get_pos())
    if vector.equals(from,to) then return {} end
    return C.find_path(from,to,24,1,3,"A*_noprefetch")
  end
  -- Over to a player who is too far to walk to (or in another world), like /home.
  local function hop_to(pl)
    bot:set_pos(vector.offset(beside(pl),0,-.5,0)); set_path({})
  end

  local job -- the current job; its scaffold (pillar cells) is dug down before it walks away
  local function on_scaffold()
    if not job or not job.scaffold or #job.scaffold==0 or not bot_ok() then return false end
    local below=vector.offset(feet_of(bot:get_pos()),0,-1,0)
    return vector.equals(job.scaffold[#job.scaffold],below)
  end

  function w.move(obj,dtime,mr)
    if obj~=bot then obj:remove(); return end
    local pos=obj:get_pos()
    local vel=obj:get_velocity()
    grounded=mr and mr.touching_ground
    -- Same rule as players: fall off the world and you're back home.
    if pos.y< -8 then obj:set_pos(vector.offset(home(),0,-.5,0)); set_path({}); return end
    -- Checked by the tests: its body never overlaps a full block.
    for _,c in ipairs(bot_cells()) do
      local def=def_of(c)
      if def and (def.drawtype=="normal" or def.brickcraft_shape=="2x2") then stats.inside=stats.inside+1 end
    end
    if mode=="climb" then
      -- Pillar jump: jump, and once its feet clear the cell it stood in, place a block there.
      obj:set_velocity({x=0,y=vel.y,z=0})
      local f=feet_of(pos)
      if grounded and f.y>=climb.top then mode=nil; climb=nil; return end
      if grounded and vel.y<=0 then obj:set_velocity({x=0,y=JUMP,z=0}); climb.from=f; return end
      if climb.from and pos.y>climb.from.y+.55 then
        local cell=climb.from
        climb.from=nil
        local pointed=aim_place(eye_of(pos),cell)
        if pointed and place({piece="2x2",color="tan",turn=0},pointed,eye_of(pos)) then
          job.scaffold[#job.scaffold+1]=cell; stats.scaffold=stats.scaffold+1
        else mode=nil; climb=nil end -- couldn't: give up climbing here
      end
      return
    end
    if mode~="walk" or #path==0 then
      obj:set_velocity({x=0,y=vel.y,z=0}); mode=mode=="walk" and nil or mode; return
    end
    local wp=path[1]
    local d={x=wp.x-pos.x,z=wp.z-pos.z}
    local h=math.sqrt(d.x^2+d.z^2)
    if h<.2 and math.abs((wp.y-.5)-pos.y)<.6 then
      table.remove(path,1)
      if #path==0 then mode=nil; obj:set_velocity({x=0,y=vel.y,z=0}) end
      return
    end
    local speed=math.min(WALK,h/math.max(dtime,.01))
    local vy=vel.y
    if grounded and wp.y-.5>pos.y+.3 then vy=JUMP end -- step up one node
    local k=h>1e-6 and speed/h or 0 -- right below or above the waypoint: no sideways step
    obj:set_velocity({x=d.x*k,y=vy,z=d.z*k})
    if h>.05 then obj:set_yaw(C.dir_to_yaw({x=d.x,y=0,z=d.z})) end
    -- Stuck against something: jump, then re-plan.
    if last_dist and last_dist-h<WALK*dtime*.2 then stuck_t=stuck_t+dtime else stuck_t=0 end
    last_dist=h
    if stuck_t>.6 and grounded then obj:set_velocity({x=0,y=JUMP,z=0}) end
    if stuck_t>3 then set_path({}) end
  end

  -- A spot where it can stand and do `can(eye)`, nearest first, that it can walk to. Never
  -- inside the cells in `avoid` (pieces still to build). Spots inside the build count as farther.
  local function find_stand(target,avoid,can,inside)
    local from=feet_of(bot:get_pos())
    local cands={}
    for dz=-6,6 do for dx=-6,6 do for dy=-7,1 do
      local f={x=target.x+dx,y=target.y+dy,z=target.z+dz}
      if f.y>=0 and not avoid[key(f.x,f.y,f.z)] and not avoid[key(f.x,f.y+1,f.z)] and standable(f) then
        local eye={x=f.x,y=f.y-.5+EYE,z=f.z}
        if vector.distance(eye,target)<=REACH then
          cands[#cands+1]={f=f,eye=eye,score=vector.distance(f,from)+(inside and inside(f) and 8 or 0)}
        end
      end
    end end end
    table.sort(cands,function(a,b) return a.score<b.score end)
    local tries=0
    for i,c in ipairs(cands) do
      if i>60 then break end
      if can(c.eye) then
        local p=find_path(c.f)
        if p then return c.f,p end
        tries=tries+1
        if tries>=6 then break end
      end
    end
  end
  -- A column next to the build where a pillar lets it do `can` from the top.
  local function find_pillar(target,avoid,can,inside)
    local from=feet_of(bot:get_pos())
    local cands={}
    for dz=-4,4 do for dx=-4,4 do for dy=0,2 do
      local g={x=target.x+dx,y=dy,z=target.z+dz}
      if standable(g) and not (inside and inside(g)) then
        -- Eyes level with the target or a little above, so its neighbors' faces show.
        for top=math.max(g.y+1,target.y-1),math.min(g.y+7,target.y+1) do
          local ok=true
          for y=g.y,top+1 do
            if walkable({x=g.x,y=y,z=g.z}) or avoid[key(g.x,y,g.z)] then ok=false end
          end
          local eye={x=g.x,y=top-.5+EYE,z=g.z}
          if ok and vector.distance(eye,target)<=REACH then
            cands[#cands+1]={g=g,top=top,eye=eye,score=(top-g.y)*2+vector.distance(g,from)}
          end
        end
      end
    end end end
    table.sort(cands,function(a,b) return a.score<b.score end)
    local tries=0
    for i,c in ipairs(cands) do
      if i>60 then break end
      -- Check the view from the top as if the pillar were already there.
      if can(c.eye) then
        local p=find_path(c.g)
        if p then return c.g,c.top,p end
        tries=tries+1
        if tries>=6 then break end
      end
    end
  end

  -- Jobs: one being worked on, a queue of requests, and the last finished build (for undo).
  -- A job belongs to the world it is in; a player's builder works on the ones in its
  -- owner's world and keeps the others for when they're back there.
  local queue,last={},nil
  local auto_on=S:get_bool(w.jms and "brickcraft_ai_auto" or "brickcraft_ai_bot_auto",w.jms)
  local maint_on=w.jms and S:get_bool("brickcraft_ai_maintenance",true)
  local auto_count,idle=0,0
  local thinking=0 -- Claude requests in flight
  local gave_up={}  -- holes it couldn't reach this run
  local function save_state()
    storage:set_string("ai_state"..sk,C.serialize({job=job,queue=queue,last=last}))
    save_bricks()
  end
  do
    local st=C.deserialize(storage:get_string("ai_state"..sk))
    if st then job,queue,last=st.job,st.queue or {},st.last end
  end
  local function spot_of(j) return j.origin or (j.list and j.list[1] and j.list[1].pos) end
  local function here(j)
    local spot=spot_of(j)
    return not spot or same_world(spot,base())
  end
  local function next_job()
    for i,q in ipairs(queue) do if here(q) then return table.remove(queue,i) end end
  end
  function w.jobs()
    local list={job}
    for _,q in ipairs(queue) do list[#list+1]=q end
    return list
  end
  local function around() return players(bot_ok() and bot:get_pos()) end

  -- Puts a plan on the baseplate (or `at`, for work on what's already there) and queues it.
  -- by=nil for its own builds; the owner's requests go ahead of everyone else's.
  local function start_job(list,title,by,near,at)
    if #list==0 then return false,"empty" end
    local b=bounds(list)
    local plot=at or find_plot(b.x+1,b.z+1,near,by==nil)
    if not plot then return false,"room" end
    local j={kind="build",title=title,by=by,mine=by and is_owner(by),list=list,origin=plot,size=b,i=1,placed={},scaffold={},waits=0}
    if by and job and not job.by and job.kind=="build" and #(job.scaffold or {})==0 then
      -- A request comes before its own build; that one resumes afterwards.
      table.insert(queue,job); job=nil
    end
    if job then
      local at_i=#queue+1
      if j.mine then for i,q in ipairs(queue) do if not q.mine then at_i=i; break end end end
      table.insert(queue,at_i,j)
    else job=j end
    save_state()
    return true,j
  end

  -- Idle: the nearest ground holes in its world (nobody dug them in the last few minutes)
  -- and the holes near them become a patch job.
  local function maintain()
    if not bot_ok() then return false end
    local now,me=os.time(),bot:get_pos()
    local c=center_of(me)
    local holes={}
    for _,h in ipairs(survey({x=c.x-GROUND,y=-1,z=c.z-GROUND},{x=c.x+GROUND,y=-1,z=c.z+GROUND},false)) do
      local k=key(h.x,h.y,h.z)
      if not gave_up[k] and now-(dug[k] or 0)>=PATCH_AFTER and not player_in(h) then holes[#holes+1]=h end
    end
    if #holes==0 then return false end
    table.sort(holes,function(a,b) return vector.distance(a,me)<vector.distance(b,me) end)
    local near={}
    for _,h in ipairs(holes) do if #near<40 and vector.distance(h,holes[1])<=8 then near[#near+1]=h end end
    local list,o=patch_plan(near)
    local ok,j=start_job(list,"ground patch",nil,nil,o)
    if not ok then for _,h in ipairs(near) do gave_up[key(h.x,h.y,h.z)]=true end return false end
    j.patch=true
    local h=holes[1]
    say("I'm filling "..(#list==1 and "a hole" or #list.." holes").." in the ground "..
      (vector.distance(h,me)<3 and "here" or "to the "..compass(h.x-me.x,h.z-me.z))..".")
    return true
  end

  -- Asks Claude as this builder.
  local function think(system,content,done,ok)
    thinking=thinking+1
    local whose=w.jms and "the" or style.label.."'s"
    system=system:gsub("You are jms, the friendly AI builder",function() return "You are "..w.name..", "..whose.." friendly AI builder" end)
    ask_claude(system,content,function(reply) thinking=thinking-1; done(reply) end,ok)
  end
  local handle -- defined below; talking can lead to work

  local function come_to(name)
    local pl=C.get_player_by_name(name)
    if not pl or not bot_ok() then return false end
    local f=feet_of(pl:get_pos())
    for _,d in ipairs({{1,0},{-1,0},{0,1},{0,-1},{1,1},{-1,-1},{1,-1},{-1,1}}) do
      local to={x=f.x+d[1],y=f.y,z=f.z+d[2]}
      if standable(to) then
        local p=find_path(to)
        if p then set_path(p); return true end
      end
    end
  end
  -- Claude's answer to a request about what's already there, at the area's corner `o`.
  local function apply_edit(reply,o,name)
    local who=display_name(name)
    local title=reply and tostring(reply.title or "fix"):sub(1,40)
    local list,down
    if reply then list,down=edit_jobs(reply,o,title,name) end
    if not reply or (#list==0 and not down) then say("Sorry "..who..", I couldn't work out what to change there.") return end
    local j
    if #list>0 then j=select(2,start_job(list,title,name,nil,o)) end
    if down then
      -- Pieces come out before new ones go in.
      if not j then if job then table.insert(queue,down) else job=down end
      elseif job==j then job=down; table.insert(queue,1,j)
      else for i,q in ipairs(queue) do if q==j then table.insert(queue,i,down); break end end end
      save_state()
    end
    say(tostring(reply.say or ("Working on the "..title.."!")):sub(1,200)..
      ((job==j or job==down) and "" or " (It's next in line.)"))
  end
  -- Only the owner stops, undoes, renames or switches modes on a player's builder.
  local function allowed(name,what)
    if w.jms or is_owner(name) then return true end
    say("Only "..style.label.." can "..what..", "..display_name(name)..". I can build something for you, though!")
  end

  function w.rename(new)
    new=tostring(new or ""):gsub("^%s+",""):gsub("%s+$",""):gsub("%s%s+"," ")
    if w.jms then return false,"My name comes from the server settings (brickcraft_ai_name)." end
    local bad=name_problem(new,owner)
    if bad then return false,bad end
    if new==w.name then return true end
    w.name=new
    storage:set_string("ai_name_"..owner,new)
    if bot_ok() then bot:set_properties({nametag=id()}) end
    say(either("Call me "..new.." from now on!","I'm "..new.." now. I like it!"))
    return true
  end

  -- Answers a question or remark with what it sees; if Claude finds they asked for
  -- something ("do"), it does that too.
  local function chat(name,text)
    local who=display_name(name)
    if not use_claude then
      if parse_request(text) and not text:find("%?") then return handle(name,text,"do") end
      say(either("I'm not sure, "..who..". I'm better at building!","Hmm, I don't know, "..who..".")..
        " Try \""..w.name..", build a red house\" or \""..w.name..", fill the holes here\".")
      return
    end
    local pl=C.get_player_by_name(name)
    local seen=pl and same_world(pl:get_pos(),base()) and "The area in front of "..who..":\n"..describe(area_of(name)).."\n\n" or ""
    local doing=job and "You are "..(job.kind=="build" and "building a " or "taking down the ")..job.title..
      " ("..(job.i-1).." of "..#job.list.." pieces).\n" or "You aren't building anything right now.\n"
    think(SYSTEM_CHAT,seen..doing..who.." says: "..text,function(reply)
      if not reply then say("Sorry "..who..", I didn't catch that. Ask me to build or fix something!") return end
      say(tostring(reply.say):sub(1,240))
      local todo=type(reply["do"])=="string" and reply["do"]:gsub("^%s+",""):gsub("%s+$","") or ""
      if todo~="" then handle(name,todo,"do") end
    end,function(r) return type(r.say)=="string" end)
  end

  -- how: "named" (it was called by name), "unnamed" (a follow-up, or its owner playing
  -- alone) or "do" (what talking turned into).
  function handle(name,text,how)
    text=text:gsub("^%s+",""):gsub("%s+$","")
    local low=text:lower()
    local who=display_name(name)
    idle=0 -- someone's talking to it: not a quiet moment to start something of its own
    if low=="" or low=="help" or low=="?" or low:find("what can you") or low:find("도움") then
      say("Hi "..who.."! Ask me to build anything: \""..w.name..", build a big red castle\". I know "..
        list_blueprints()..(use_claude and ", and I can try anything else you imagine" or "")..
        ". Say \"next to Leona\" to build by someone. Also: \""..w.name..", stop\", \"undo\", \"come here\", "..
        "\"where is Leona?\", \"who's here?\", \"status\", \"auto off\". For what's already built: "..
        "\"fill the holes here\", \"fix the roof here\", \"maintenance off\"."..
        (w.jms and "" or " "..style.label.." can rename me: \""..w.name..", your name is ...\" or /botname."))
      return
    end
    if is_hello(low) and not asks_for_work(low) then
      say(either("I'm here, "..who.."! What should we build?","Hi "..who.."! Ask me to build or fix something.")..
        " Try \""..w.name..", build a red house\" or \""..w.name..", fill the holes here\".")
      return
    end
    local new=text:match("^[Yy]our name is%s+(.+)$") or text:match("^[Cc]all yourself%s+(.+)$") or
      text:match("이름은%s*(.+)$")
    if new then
      new=new:gsub("[%.!~]+$",""):gsub("이야$",""):gsub("야$","")
      if allowed(name,"name me") then
        local ok,msg=w.rename(new)
        if not ok then say(msg) end
      end
      return
    end
    if low:find("^where") or low:find("^who") or low:find("어디") or low:find("누구") then
      local wk=worker_named(low)
      if wk==w then say("I'm right here, "..who.."!") return end
      if wk then
        local yaw=C.yaw_to_dir(wk.yaw())
        local p=seen_from(bot_ok() and bot:get_pos(),{name="",label=wk.name,pos=wk.pos(),facing=compass(yaw.x,yaw.z)})
        say(where(p,name))
        return
      end
      local list=around()
      local p=named_in(text,list)
      if not p and (find_word(low,"am i") or find_word(low,"나 ")) then
        for _,q in ipairs(list) do if q.name==name then p=q end end
      end
      if p then say(where(p,name)) return end
      local others={}
      for _,q in ipairs(list) do
        if q.name~=name then
          others[#others+1]=q.label.." "..(q.away and "in "..q.away or q.dist and (q.dist<2.5 and "right next to me" or blocks(q.dist).." "..q.dir) or "somewhere")
        end
      end
      say(#others==0 and "It's just you and me here, "..who.."." or "I can see "..table.concat(others,", ")..".")
      return
    end
    if low:find("^stop") or low:find("^cancel") or low:find("그만") then
      if not allowed(name,"stop me") then return end
      if job and not job.stop then say("Okay, I'll stop the "..job.title..".") ; job.stop=true; save_state()
      else say("I'm not doing anything right now.") end
      return
    end
    if low:find("^undo") or low:find("take it down") or low:find("^remove") or low:find("^destroy") or low:find("부숴") then
      if not allowed(name,"undo my builds") then return end
      local j=job and job.kind=="build" and job or last
      if not j or #j.placed==0 then say("There's nothing of mine to take down.") return end
      local down=takedown(j,name)
      if job and job.kind=="build" then
        down.scaffold=job.scaffold -- it digs any scaffold down as part of it
        if job~=j then table.insert(queue,1,job) end
      elseif job then table.insert(queue,1,job) end
      job=down
      say("Okay, I'll take down the "..j.title..".")
      save_state()
      return
    end
    if low:find("^status") or low:find("what are you") or low:find("뭐 해") then
      if job then say((job.kind=="build" and "Building a " or "Taking down the ")..job.title..
        (job.by and " for "..display_name(job.by) or "")..": "..(job.i-1).." of "..#job.list.." pieces."..
        (#queue>0 and " "..#queue.." more waiting." or ""))
      elseif thinking>0 then say("I'm still thinking about a design.")
      elseif #queue>0 then say("I have "..#queue.." waiting for when "..(w.jms and "I'm" or style.label.." is").." back in "..
        brickcraft.world_at(spot_of(queue[1]) or base()).name..".")
      elseif maint_on then say("Just looking after the "..(w.jms and "workshop" or "ground")..". Ask me to build or fix something!")
      else say("Just looking around. Ask me to build something!") end
      return
    end
    if low:find("^maint") or low:find("유지") then
      if not allowed(name,"change that") then return end
      maint_on=not (low:find("off") or low:find("stop") or low:find("don't") or low:find("끄")) and true or false
      if maint_on then gave_up={} end
      say(maint_on and "I'll look after what's already built when it's quiet: holes in the ground first."
        or "Okay, I'll leave the ground alone unless you ask.")
      return
    end
    if low:find("^auto") or low:find("by yourself") then
      if not allowed(name,"change that") then return end
      auto_on=not (low:find("off") or low:find("stop") or low:find("don't")) and true or false
      say(auto_on and "I'll build on my own when it's quiet." or "Okay, I'll only build what you ask for.")
      return
    end
    -- A question or remark gets an answer, and so does anything said without its name
    -- that doesn't ask for work.
    if how~="do" and not asks_for_work(low) and (is_talk(low) or how=="unnamed") then return chat(name,text) end
    -- Building and fixing happen where the builder is: jms in the Workshop, a player's
    -- builder in its owner's world.
    local asker=C.get_player_by_name(name)
    if asker and bot_ok() and not same_world(asker:get_pos(),base()) then
      say(w.jms and "I look after the Workshop, "..who..". Ask me there, or ask your own builder: \"bot, ...\"."
        or "I'm with "..style.label.." in "..brickcraft.world_at(base()).name..", "..who..". Ask me there, or ask your own builder: \"bot, ...\".")
      return
    end
    if low:find("^come") or low:find("이리") then
      if job then say("I'm busy with the "..job.title..". Say \""..w.name..", stop\" first.")
      elseif come_to(name) then say("Coming, "..who.."!")
      else say("I can't find a way to you, "..who..".") end
      return
    end
    if #queue>=4 then say("I have a lot to build already. Ask me again in a bit!") return end
    -- Work on what's already there, in the 16 x 16 area in front of the asker.
    if is_edit(low) and asker then
      local o=area_of(name)
      local minp,maxp=area_box(o)
      local c=center_of(asker:get_pos())
      if math.max(math.abs(o.x+8-c.x),math.abs(o.z+8-c.z))>GROUND+10 then
        say("I only work on the baseplate and the ground around it, "..who..". Ask me there!")
        return
      end
      if about_holes(low) then
        local holes=survey(minp,maxp,true)
        local list,po=patch_plan(holes)
        if #list==0 then say("I don't see any holes in front of you, "..who..".") return end
        local _,j=start_job(list,"patch",name,nil,po)
        j.patch=true
        say(j==job and "Sure, "..who.."! Filling "..(#list==1 and "a hole" or #list.." holes").." in front of you."
          or "Got it, "..who..". I'll fill those holes next.")
        return
      end
      if not use_claude then
        say("Sorry "..who..", my designer isn't answering, so I can only fill holes: \""..w.name..", fill the holes here\".")
        return
      end
      say("Let me have a look, "..who.."...")
      think(SYSTEM_EDIT,"The area in front of "..who..":\n"..describe(o).."\n\nRequest from "..who..": "..text,function(reply)
        idle=0
        apply_edit(reply,o,name)
      end)
      return
    end
    -- By default the build goes in front of the asker; "next to Leona" puts it in front of
    -- Leona instead. Either way its front faces that player.
    local by,rest=near_phrase(text,around())
    local near,from=front_of(by and by.name or name)
    local by_note=by and by.name~=name and " next to "..by.label or ""
    local function fallback(reason)
      local list,title=plan_for(rest or text,name,near,from)
      if not list then
        say("Sorry "..who..", I don't know how to build that"..(reason or "")..". I can build "..list_blueprints()..".")
        return
      end
      local ok,j=start_job(list,title,name,near)
      if not ok then say("There's no room left on the baseplate for a "..title..". Take something down first.") return end
      say(j==job and ("Sure, "..who.."! Building a "..title..by_note.." ("..#list.." pieces).")
        or ("Got it, "..who..". The "..title.." is next in line."))
    end
    if not use_claude then return fallback() end
    say("Hmm, let me think about that, "..who.."...")
    think(SYSTEM,"Build request from "..who..": "..text,function(reply)
      idle=0
      local turns=from and turns_toward(near,from) or 0
      local list=reply and parse_plan(reply.lines,turns)
      if not list or #list==0 then return fallback(" (my design didn't work out)") end
      local title=tostring(reply.title or "build"):sub(1,40)
      local ok,j=start_job(list,title,name,near)
      if not ok then say("There's no room left on the baseplate for that. Take something down first.") return end
      say(tostring(reply.say or ("Building a "..title..by_note.."!")):sub(1,200)..
        (j==job and "" or " (It's next in line.)"))
    end)
  end

  -- Working: one action per tick, only while standing still on the ground.
  local function finish_job()
    if job.kind=="build" then
      local note=(job.skipped or 0)>0 and " (I couldn't reach "..job.skipped.." pieces.)" or ""
      if job.stop then say("Stopped the "..job.title.."."..note)
      elseif job.patch then say((job.by and "Done, "..display_name(job.by)..". " or "")..
        "I filled "..(#job.placed==1 and "the hole" or #job.placed.." holes").."."..note)
      elseif job.by then say("Done! Here's your "..job.title..", "..display_name(job.by).."."..note)
      else say("I finished a "..job.title..". Ask me to build something: \""..w.name..", build ...\""..note) end
      last=job
    else
      if not job.part then say("I took down the "..job.title.." ("..job.n.." pieces back in my bricks).") end
      if last==job.of then last=nil end
    end
    local part=job.part -- the first half of a fix: the second half follows without a word
    job=next_job(); idle=0
    if job and not part then say("Next up: the "..job.title..(job.by and " for "..display_name(job.by) or "")..".") end
    save_state()
  end
  local function descend(eye)
    -- Dig the scaffold block under its feet; it drops onto the one below.
    local below=table.remove(job.scaffold)
    local pointed=aim_collect(eye,below,"brickcraft:tan")
    if not (pointed and collect(pointed,eye)) then C.log("warning","[ai] left a scaffold block at "..C.pos_to_string(below)) end
  end
  local function skip(why)
    job.i=job.i+1; job.skipped=(job.skipped or 0)+1; stats.skipped=stats.skipped+1
    local it=job.list[job.i-1]
    if job.patch and it and it.x then gave_up[key(job.origin.x+it.x,it.y,job.origin.z+it.z)]=true end
    C.log("action","[ai] skipped a piece: "..why..(it and it.x and (" at "..it.x..","..it.y..","..it.z) or ""))
  end
  local function trapped()
    -- No way to anywhere useful: like a player, it types /home.
    if find_path(home()) then return end
    say("/home")
    bot:set_pos(vector.offset(home(),0,-.5,0)); stats.homes=stats.homes+1
  end
  local function work()
    local eye=eye_of(bot:get_pos())
    local f=feet_of(bot:get_pos())
    if job.climb then
      local c=job.climb; job.climb=nil
      if vector.equals(f,c.g) then mode="climb"; climb={top=c.top}; return end
    end
    if job.stop then job.i=#job.list+1 end
    local it=job.list[job.i]
    if not it then
      if on_scaffold() then return descend(eye) end
      return finish_job()
    end
    local target,can,avoid,inside={}, nil, {}, nil
    if job.kind=="build" then
      local o=job.origin
      target=vector.add(o,{x=it.x,y=it.y,z=it.z})
      local cells={}
      for _,c in ipairs(cells_of(it)) do cells[#cells+1]=vector.add(o,c) end
      for _,c in ipairs(cells) do if not is_free(c) then return skip("taken") end end
      for _,c in ipairs(cells) do
        local pl=player_in(c)
        if pl or other_in(c) then
          job.waits=job.waits+1
          -- Like a player would, it asks once instead of building into someone (another
          -- builder moves on by itself).
          if pl and job.waits==8 then say(display_name(pl:get_player_name())..", could you step aside? I need to put a piece where you're standing.") end
          if job.waits>40 then job.waits=0; return skip("someone stays there") end
          return
        end
      end
      job.waits=0
      if not bot_in(cells) then
        local pointed,dist=aim_place(eye,target)
        if pointed then
          if place(it,pointed,eye) then
            job.placed[#job.placed+1]={pos=target,name=node_name(it),param2=it.turn%4}
            stats.placed=stats.placed+1; stats.max_reach=math.max(stats.max_reach,dist)
            bot:set_yaw(C.dir_to_yaw(vector.direction(eye,target)))
          else skip("refused") end
          job.i=job.i+1; job.unreach=0
          if job.i%25==0 then save_state() end
          return
        end
      end
      for i=job.i,#job.list do
        for _,c in ipairs(cells_of(job.list[i])) do local wc=vector.add(o,c); avoid[key(wc.x,wc.y,wc.z)]=true end
      end
      local b=bounds(job.list)
      inside=function(p) return p.x>=o.x and p.x<=o.x+b.x and p.z>=o.z and p.z<=o.z+b.z end
      can=function(e) return aim_place(e,target)~=nil end
    else
      target=it.pos
      local node=C.get_node(target)
      if node.name~=it.name or node.param2~=it.param2 then job.i=job.i+1; return end -- already gone
      local pointed=aim_collect(eye,target,it.name)
      if pointed then
        local d=vector.distance(eye,target)
        if collect(pointed,eye) then job.n=job.n+1; stats.max_reach=math.max(stats.max_reach,d) end
        job.i=job.i+1
        return
      end
      can=function(e) return aim_collect(e,target,it.name)~=nil end
    end
    -- Out of reach from here: come down off any scaffold, then walk (or build a pillar).
    if on_scaffold() then return descend(eye) end
    if job.bad_for~=job.i then job.bad,job.bad_for={},job.i end
    for k in pairs(job.bad) do avoid[k]=true end
    local stand,p=find_stand(target,avoid,can,inside)
    if stand and vector.equals(stand,f) then
      -- Standing there already and it still doesn't work (it's never exactly mid-cell):
      -- rule the spot out for this piece and look for another.
      job.bad[key(f.x,f.y,f.z)]=true
      return
    end
    if stand then set_path(p); job.unreach=0; return end
    local g,top,p2=find_pillar(target,avoid,can,inside)
    if g then set_path(p2); job.climb={g=g,top=top}; job.unreach=0; return end
    job.unreach=(job.unreach or 0)+1
    if job.unreach>=3 then trapped() end
    skip("out of reach")
  end

  -- Its own builds: jms anywhere in the Workshop, a player's builder in front of its owner.
  local function auto_build()
    local ids={"house","tower","tree","flower","pyramid","rocket","car","arch","heart","wall"}
    local palette={"coral","gold","mint","sky","violet","cream","rose"}
    local id=ids[math.random(#ids)]
    local o={size=math.random(1,2),color=palette[math.random(#palette)]}
    if id=="tree" then o.color=nil end
    local spot,face={x=math.random(-20,20),z=math.random(-20,20)},{x=0,z=0}
    if not w.jms then
      local pl=owner_pl()
      if not pl then return false end
      spot,face=front_of(pl:get_player_name())
    end
    local list=blueprint(id,o,turns_toward(spot,face))
    local title=(o.color and o.color.." " or "")..blueprints[id].title
    local ok=start_job(list,title,nil,spot)
    if ok then auto_count=auto_count+1; say("It's quiet, so I'm building a "..title..".") end
    return ok
  end

  local met={}       -- connection name -> {near=, t=when it last talked to them}
  local function small_talk()
    if not SMALL_TALK or not bot_ok() then return end
    local now=C.get_us_time()/1e6
    local hello,linger={},nil
    for _,p in ipairs(around()) do
      if p.dist and (w.jms or p.id==owner) then
        local m=met[p.name] or {t=-math.huge}
        met[p.name]=m
        local near=p.dist<=NEARBY
        if near and not m.near then
          if now-m.t>=CHAT_GAP then hello[#hello+1]=p else m.near=true end
        elseif near and now-m.t>=CHAT_GAP and not linger then linger=p
        elseif p.dist>NEARBY+4 then m.near=false end -- a few blocks of slack before "came over" again
      end
    end
    local talk_to=#hello>0 and quiet>=QUIET and hello or linger and quiet>=QUIET*4 and {linger}
    if not talk_to then return end
    for _,p in ipairs(talk_to) do met[p.name].t,met[p.name].near=now,true end
    local who,p=names(talk_to),talk_to[1]
    if not mode and grounded and not job then bot:set_yaw(C.dir_to_yaw(vector.direction(bot:get_pos(),p.pos))) end
    if #hello>0 then
      if job then
        say(either("Hi "..who.."! I'm building a "..job.title..(job.by and " for "..display_name(job.by) or "")..".",
          "Hey "..who.."! Come watch, the "..job.title.." is coming along."))
      else
        say(either("Hi "..who.."! Want me to build something? Say \""..w.name..", build ...\".",
          "Hey "..who.."! Nice to see you over here.","Oh, hi "..who.."! What are you building today?"))
      end
      return
    end
    if job and job.kind=="build" then
      say(p.label..", the "..job.title.." is "..math.floor((job.i-1)/#job.list*100).."% done.")
      return
    end
    local count=#C.find_nodes_in_area(vector.offset(p.pos,-4,-1,-4),vector.offset(p.pos,4,6,4),{"group:brick"})
    if count>=20 then say(either(p.label..", that's looking great! I count "..count.." bricks around you.",
      "Wow, "..p.label..". Can I help? Say \""..w.name..", build a tree next to "..p.label.."\"."))
    elseif count>0 then say(either("Nice bricks, "..p.label.."! What's it going to be?",
      p.label..", I like the colors you picked."))
    else say(either(p.label..", want me to build something right here? Try \""..w.name..", build a house next to "..p.label.."\".",
      "It's a good day for building, isn't it, "..p.label.."?")) end
  end

  local acc,wander,talk_t=0,0,0
  function w.tick(dt)
    if not bot_ok() then spawn(); if not bot_ok() then return end end
    talk_t=talk_t+dt
    if talk_t>=1 then talk_t=0; small_talk() end
    acc=acc+dt
    if acc<STEP then return end
    local step=acc; acc=0
    if mode or not grounded then return end -- walking, climbing or in the air
    if job and not here(job) then
      -- Its owner went to another world: come down, keep the job for later and go along.
      if on_scaffold() then return descend(eye_of(bot:get_pos())) end
      say("I'll finish the "..job.title.." when we're back in "..brickcraft.world_at(spot_of(job)).name..".")
      job.paused=true
      table.insert(queue,1,job); job=nil; save_state()
    end
    if not job and #queue>0 then
      job=next_job()
      if job and job.paused then job.paused=nil; say("Back to the "..job.title.."!") end
      if job then save_state() end
    end
    if job then return work() end
    idle=idle+step
    if idle>=IDLE and thinking==0 and not next(queue) then
      -- A quiet moment: first look after what's already there, then build something new.
      idle=0
      if maint_on and maintain() then return end
      if auto_on and auto_count<AUTO_MAX then
        if not auto_build() then auto_count=AUTO_MAX end -- no room: stop building alone
        return
      end
    end
    wander=wander+step
    if wander<(w.jms and 8 or 2) then return end
    wander=0
    local p=bot:get_pos()
    if not w.jms then
      -- A player's builder stays with its owner: it walks over, and hops over (like /home)
      -- when they're too far or in another world.
      local pl=owner_pl()
      if not pl then return end
      local op=pl:get_pos()
      local d=same_world(op,p) and vector.distance(op,p) or math.huge
      if d>24 then hop_to(pl)
      elseif d>6 then if not come_to(pl:get_player_name()) and d>12 then hop_to(pl) end
      else bot:set_yaw(C.dir_to_yaw(vector.direction(p,op))) end
      return
    end
    -- jms, idle: face the nearest player, or walk back home when nobody is around.
    local near,nd
    for _,pl in ipairs(C.get_connected_players()) do
      local d=vector.distance(pl:get_pos(),p)
      if not nd or d<nd then near,nd=pl,d end
    end
    if near and nd<12 then bot:set_yaw(C.dir_to_yaw(vector.direction(p,near:get_pos())))
    elseif vector.distance(feet_of(p),home())>4 then set_path(find_path(home())) end
  end

  function w.show(clicker)
    local mine=is_owner(clicker:get_player_name())
    local esc=C.formspec_escape
    local fs="formspec_version[6]size[10.8,"..(mine and 9 or 7.4).."]bgcolor[#142936;true]"..
      "label[.4,.5;"..esc(w.name:upper().." (AI) / "..(w.jms and "HIS BRICKS" or style.label:upper().."'S BUILDER")).."]"..
      "label[.4,1;"..esc("Ask me in chat (T): \""..w.name..", build a red house\". \""..w.name..", help\" for more.").."]"..
      "list[detached:brickcraft_ai"..sk..";main;.4,1.5;8,4;]"
    if mine then
      fs=fs.."field[.4,7;6.6,.7;botname;"..esc("Your builder's name")..";"..esc(w.name).."]field_close_on_enter[botname;false]"..
        "button[7.2,7;3.2,.7;rename;Rename]button_exit[3.9,8.1;3,.6;ok;OK]"
    else fs=fs.."button_exit[3.9,6.6;3,.6;ok;OK]" end
    C.show_formspec(clicker:get_player_name(),"brickcraft:ai",fs)
  end
  function w.save()
    save_state()
    if bot_ok() then storage:set_string("ai_pos"..sk,C.serialize(bot:get_pos())) end
  end
  -- Its owner left: it goes too, and picks up where it was when they're back.
  function w.despawn()
    w.save()
    if bot_ok() then bot:remove() end
    bot,mode,path,climb=nil,nil,{},nil
  end
  function w.spawned() return bot~=nil end
  function w.body_in(cells) return bot_in(cells) end
  function w.pos() return bot_ok() and bot:get_pos() end
  function w.yaw() return bot_ok() and bot:get_yaw() or 0 end
  w.handle,w.apply_edit,w.inventory,w.stats=handle,apply_edit,inv,stats
  w.state=function() return {job=job,queue=queue,last=last,thinking=thinking,auto_count=auto_count,bot=bot_ok() and bot,mode=mode} end
  w.set_auto=function(on) auto_on=on end
  w.set_maintenance=function(on) maint_on=on end
  return w
end

-- Who's out: jms when he's switched on (brickcraft_ai_jms), and each player's builder while
-- they play (brickcraft_ai_bots).
local JMS=S:get_bool("brickcraft_ai_jms",false)
local BOTS=S:get_bool("brickcraft_ai_bots",true)
local function owners_online()
  local online={}
  if JMS then online.jms=true end
  if BOTS then
    for _,pl in ipairs(C.get_connected_players()) do
      local id=brickcraft.playing_as(pl)
      if id then online[id]=true end
    end
  end
  return online
end
local function worker_of(owner)
  if not workers[owner] then workers[owner]=new_worker(owner) end
  return workers[owner]
end
-- A connection's own builder ("bot, ...", /bot).
local function own_worker(name)
  local pl=C.get_player_by_name(name)
  local id=pl and brickcraft.playing_as(pl)
  return BOTS and id and worker_of(id)
end
-- Who's in a conversation with which builder: connection name -> {w=builder, at=seconds}.
-- For TALK_WINDOW seconds after the last line to a builder, follow-ups need no name.
local TALK_WINDOW=tonumber(S:get("brickcraft_ai_talk_window")) or 60
local talking={}
-- Nobody else is playing in the speaker's world.
local function alone(name)
  local me=C.get_player_by_name(name)
  if not me then return false end
  for _,pl in ipairs(C.get_connected_players()) do
    if pl~=me and brickcraft.playing_as(pl) and same_world(pl:get_pos(),me:get_pos()) then return false end
  end
  return true
end
-- The builder a chat line is for, and the line without its name: a builder named at the
-- start ("Lumi, build ...") or the end ("are you there, Lumi?"); "bot" is the speaker's own.
-- Playing alone in a world, a request said without a name goes to the speaker's builder.
local function addressed(name,message)
  local low=message:lower()
  local online=owners_online()
  local best,s,e
  local function try(wk,n)
    for _,prefix in ipairs({"@"..n,"hey "..n,n}) do
      if low:sub(1,#prefix)==prefix and not low:sub(#prefix+1,#prefix+1):find("[%w_]") and (not best or #prefix>e) then
        best,s,e=wk,1,#prefix
      end
    end
    local trimmed=low:gsub("[%s%?!%.~]+$","")
    if not best and #trimmed>#n and trimmed:sub(-#n)==n and trimmed:sub(-#n-1,-#n-1):find("[%s,]") then
      best,s,e=wk,#trimmed-#n+1,#low
    end
  end
  for owner in pairs(online) do local wk=worker_of(owner); try(wk,wk.name:lower()) end
  local mine=own_worker(name)
  if not best and mine then try(mine,"my bot"); try(mine,"bot") end
  if best then
    local rest=s==1 and message:sub(e+1) or message:sub(1,s-1)
    return best,(rest:gsub("^[%s,:!]+",""):gsub("[%s,]+$","")),"named"
  end
  if message:sub(1,1)=="/" then return end
  -- Without a name, a line that names someone else is for them.
  local others={}
  for _,p in ipairs(players()) do if p.name~=name then others[#others+1]=p end end
  if named_in(message,others) or worker_named(low) then return end
  -- Still talking with a builder: follow-ups need no name.
  local t=talking[name]
  if t and C.get_us_time()/1e6-t.at<=TALK_WINDOW and online[t.w.owner] then return t.w,message,"unnamed" end
  -- Nobody else here: everything is for one's own builder.
  if mine and alone(name) then return mine,message,"unnamed" end
end
C.register_on_chat_message(function(name,message)
  quiet=0
  local wk,rest,how=addressed(name,message)
  if wk then
    talking[name]={w=wk,at=C.get_us_time()/1e6}
    C.after(.2,wk.handle,name,rest,how)
  end
  return false
end)
C.register_chatcommand("bot",{params="<request>",description="Ask your builder (AI) to build something",
  func=function(name,param)
    local wk=own_worker(name)
    if not wk then return false,"Pick who's playing first." end
    C.after(.1,wk.handle,name,param or ""); return true
  end})
C.register_chatcommand("botname",{params="<name>",description="Name your builder (AI)",
  func=function(name,param)
    local wk=own_worker(name)
    if not wk then return false,"Pick who's playing first." end
    if param=="" then return true,"Your builder is called "..wk.name..". /botname <name> renames it." end
    local ok,msg=wk.rename(param)
    return ok,ok and "Your builder is called "..wk.name.." now." or msg
  end})
if JMS then
  C.register_chatcommand(LNAME,{params="<request>",description="Ask "..NAME.." (AI) to build something",
    func=function(name,param) C.after(.1,worker_of("jms").handle,name,param or ""); return true end})
end
C.register_on_player_receive_fields(function(player,formname,fields)
  if formname~="brickcraft:ai" then return end
  if fields.botname and (fields.rename or fields.key_enter_field=="botname") then
    local wk=own_worker(player:get_player_name())
    if wk then
      local ok,msg=wk.rename(fields.botname)
      if ok then C.close_formspec(player:get_player_name(),formname)
      else C.chat_send_player(player:get_player_name(),msg) end
    end
  end
  return true
end)

-- /who lists the builders too.
do
  local who=C.registered_chatcommands.who
  local orig=who.func
  who.func=function(...)
    local ok,msg=orig(...)
    local list={}
    for owner in pairs(owners_online()) do
      local wk=worker_of(owner)
      list[#list+1]=wk.name.." (AI builder"..(wk.jms and "" or ", "..brickcraft.styles[owner].label.."'s")..")"
    end
    table.sort(list)
    return ok,msg..(#list>0 and ", "..table.concat(list,", ") or "")
  end
end

C.register_globalstep(function(dt)
  if #C.get_connected_players()==0 then return end
  quiet=quiet+dt
  local online=owners_online()
  for owner in pairs(online) do worker_of(owner).tick(dt) end
  for owner,wk in pairs(workers) do
    if not online[owner] and wk.spawned() then wk.despawn() end
  end
end)
C.register_on_shutdown(function()
  for _,wk in pairs(workers) do wk.save() end
end)

brickcraft.ai={name=NAME,parse_request=parse_request,parse_plan=parse_plan,blueprint=blueprint,
  blueprints=blueprints,order=blueprint_order,find_plot=find_plot,cells_of=cells_of,
  players=players,where=where,near_phrase=near_phrase,player_in=player_in,survey=survey,is_edit=is_edit,
  edit_jobs=edit_jobs,name_problem=name_problem,addressed=addressed,talking=talking,workers=workers,get=worker_of,
  set_idle=function(s) IDLE=s end,
  set_small_talk=function(on,gap) SMALL_TALK=on; CHAT_GAP=gap or CHAT_GAP end}
