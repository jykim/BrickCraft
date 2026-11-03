-- Display models: builds made of real LEGO parts with BrickWright (validated there: no
-- collisions, nothing floating, all connected), shown in the world as one mesh each.
-- tools/import_brickwright.py writes the meshes, palette textures and catalog.lua.
--
-- Life-size: 1 cell = 2 studs = 16 mm on every axis, so a model keeps its real proportions
-- next to the game's bricks (a 37-stud bonsai is about 17 cells wide). /model <name> <scale>
-- shows it bigger or smaller.
--
-- A model is decoration, not pieces: it can't be taken apart, holds nothing up and isn't in
-- the parts list. In a strict LEGO world it has to stand on studs like any piece (the ground
-- or a piece with studs on top), since the real one would sit on them.
local C=core
local S=brickcraft.strict
local catalog=dofile(C.get_modpath("brickcraft_models").."/catalog.lua")
local by_slug={}
for i,m in ipairs(catalog) do m.i=i; by_slug[m.slug]=m end
local MIN_SCALE,MAX_SCALE=.1,3
-- The models' fronts face -z in their mesh (LDraw's front, toward the viewer), like the AI
-- builder's plans.

local function boxes(m,s)
  local hw,hd,h=m.w*s/2,m.d*s/2,m.h*s
  return {-hw,0,-hd,hw,h,hd}
end

local function apply(self)
  local m=by_slug[self._slug]
  if not m then return false end
  local s=self._scale or 1
  local box=boxes(m,s)
  self.object:set_properties({
    mesh="brickcraft_model_"..m.slug..".glb",textures={"brickcraft_model_"..m.slug..".png"},
    visual_size={x=s,y=s,z=s},selectionbox=box,collisionbox=box,
    use_texture_alpha=m.alpha,infotext=m.title.." ("..m.pieces.." real pieces)"})
  self.object:set_yaw((self._turn or 0)*math.pi/2)
  return true
end

C.register_entity(":brickcraft:display_model",{
  initial_properties={visual="mesh",mesh="brickcraft_model_cat.glb",textures={"brickcraft_model_cat.png"},
    physical=false,pointable=true,backface_culling=false,shaded=true,static_save=true,
    collisionbox={-.5,0,-.5,.5,1,.5},selectionbox={-.5,0,-.5,.5,1,.5}},
  on_activate=function(self,staticdata)
    local d=C.deserialize(staticdata or "") or {}
    self._slug,self._scale,self._turn=d.slug,d.scale or 1,d.turn or 0
    if not apply(self) then self.object:remove() end
    self.object:set_armor_groups({immortal=1})
  end,
  get_staticdata=function(self)
    return C.serialize({slug=self._slug,scale=self._scale,turn=self._turn})
  end,
  -- The separator turns it (right click) and takes it away (left click, brickcraft's
  -- separator passes objects here).
  on_rightclick=function(self,clicker)
    if not clicker or clicker:get_wielded_item():get_name()~="brickcraft:separator" then return end
    -- Turned to face the other way round its own middle: a non-square footprint swaps w/d.
    self._turn=((self._turn or 0)+1)%4
    self.object:set_yaw(self._turn*math.pi/2)
  end,
  on_punch=function() return true end,
  _brickcraft_collect=function(self,player)
    local m=by_slug[self._slug]
    self.object:remove()
    C.chat_send_player(player:get_player_name(),"Put away "..(m and m.title or "the model")..". /model brings it back.")
  end,
})

-- Where a model stands in front of the player: the first solid top below their eye level,
-- far enough out that the model doesn't land on them.
local function spot_for(player,m,s)
  local pos=player:get_pos()
  local dir=player:get_look_dir(); dir.y=0
  if vector.length(dir)<.01 then dir={x=0,y=0,z=1} end
  dir=vector.normalize(dir)
  local reach=math.max(m.w,m.d)*s/2+1.5
  local at=vector.round(vector.add(pos,vector.multiply(dir,reach)))
  for y=math.floor(pos.y+2),math.floor(pos.y-8),-1 do
    local below={x=at.x,y=y,z=at.z}
    local def=C.registered_nodes[C.get_node(below).name]
    if def and def.walkable then return {x=at.x,y=y+.5,z=at.z},below,dir end
  end
end

-- In a strict LEGO world: the cell under the model's middle must offer studs on top.
local function on_studs(below)
  local node=C.get_node(below)
  local d=S.describe(below,node)
  if not d then return true end -- the ground, the baseplate: studs all over
  for _,c in pairs(d.cells) do
    if c.top and vector.equals(c.cell,below) then return true end
  end
  return false
end

local function list_text()
  local rows={"Display models (real LEGO builds from BrickWright, life-size):"}
  for i,m in ipairs(catalog) do
    rows[#rows+1]=string.format("  %d. %s  %s: %d pieces, %.0f x %.0f cells, %.0f tall",
      i,m.slug,m.title,m.pieces,m.w,m.d,m.h)
  end
  rows[#rows+1]="/model <name> [scale] puts one in front of you (scale 1 = life-size). Separator: right click turns it, left click puts it away."
  return table.concat(rows,"\n")
end

local function place(name,param)
  local player=C.get_player_by_name(name)
  if not player then return false,"No player." end
  local which,scale=param:match("^%s*(%S+)%s*(%S*)%s*$")
  if not which then return true,list_text() end
  local m=by_slug[which] or catalog[tonumber(which) or 0]
  if not m then return false,"No model called "..which..".\n"..list_text() end
  local s=1
  if scale~="" then
    s=tonumber(scale)
    if not s or s<MIN_SCALE or s>MAX_SCALE then return false,"Scale is a number from "..MIN_SCALE.." to "..MAX_SCALE.." (1 = life-size)." end
  end
  local foot,below,dir=spot_for(player,m,s)
  if not foot then return false,"Nowhere to stand it in front of you." end
  if S.on(foot) and not on_studs(below) then
    return false,"Strict LEGO: a model has to stand on studs (the ground or the top of a brick), not on a plate, tile or slope."
  end
  -- Face the player: the model's front is -z, turned by quarters.
  local yaw=math.atan2(dir.x,-dir.z) -- 0 when looking toward +z
  local turn=math.floor(yaw/(math.pi/2)+.5)%4
  local obj=C.add_entity(foot,"brickcraft:display_model",C.serialize({slug=m.slug,scale=s,turn=(turn+2)%4}))
  if not obj then return false,"The model couldn't be placed here." end
  return true,string.format("%s: %d real pieces, %.0f cells tall%s.",m.title,m.pieces,m.h*s,s==1 and " (life-size)" or "")
end

C.register_chatcommand("model",{params="[name] [scale]",
  description="Put a real LEGO model (from BrickWright) in front of you; no name lists them",func=place})
C.register_chatcommand("models",{description="List the display models",func=function() return true,list_text() end})

for _,row in ipairs({
  {"/model","List the display models (real LEGO builds, life-size)"},
  {"/model bonsai [scale]","Put one in front of you; separator right click turns, left click puts away"},
}) do brickcraft.help[#brickcraft.help+1]=row end

-- The Model Gallery: a shared strict LEGO world, made once like the Kart Circuit, with one
-- of each model standing round the arrival spots (x -6..6, z 1..4, looking +z). Its
-- brick stacks and arch go to make room; the floor mosaic stays. A model added to the
-- catalog later gets its spot on the next start (w.gallery_models lists those placed).
-- x, z: the model's middle from the world's center; all face the arrival spots (-z).
local GALLERY={
  bonsai={x=0,z=15}, house={x=-16,z=14}, mech={x=16,z=14},
  cat={x=-14,z=4}, train={x=14,z=4}, car={x=-14,z=-8},
}
local R=24
local function gallery_world() for _,w in ipairs(brickcraft.worlds()) do if w.gallery then return w end end end

local function fill_gallery(w,fresh)
  if fresh then
    -- The stacks (z 10..12) and the arch (z -7): air above the baseplate.
    for x=-R,R do for z=-R,R do for y=0,4 do
      if (z>=10 and z<=12) or z==-7 then
        local pos={x=w.x+x,y=y,z=w.z+z}
        if C.get_node(pos).name~="air" then C.remove_node(pos) end
      end
    end end end
  end
  w.gallery_models=w.gallery_models or {}
  local placed={}
  for _,m in ipairs(catalog) do
    local at=GALLERY[m.slug]
    if at and not w.gallery_models[m.slug] then
      C.add_entity({x=w.x+at.x,y=-.5,z=w.z+at.z},"brickcraft:display_model",
        C.serialize({slug=m.slug,scale=1,turn=0}))
      w.gallery_models[m.slug]=true; placed[#placed+1]=m.slug
    end
  end
  brickcraft.save_worlds()
  if #placed>0 then C.log("action","BrickCraft Model Gallery: placed "..table.concat(placed,", ")) end
end

C.after(0,function()
  if brickcraft.testing and not C.settings:get_bool("brickcraft_models_test",false) then return end
  local w=gallery_world()
  local function load_and(fn)
    C.emerge_area({x=w.x-R,y=-2,z=w.z-R},{x=w.x+R,y=31,z=w.z+R},function(_,_,r) if r==0 then fn() end end)
  end
  if w then
    local missing=false
    for slug in pairs(GALLERY) do if by_slug[slug] and not (w.gallery_models or {})[slug] then missing=true end end
    if w.built and missing then load_and(function() fill_gallery(w,not w.gallery_models) end) end
    return
  end
  w=brickcraft.make_world("Model Gallery","BrickCraft",function(w) fill_gallery(w,true) end,{strict=true})
  C.log("action","BrickCraft Model Gallery "..(w and "being made at "..w.x..","..w.z or "has no room"))
  if w then w.gallery=true; brickcraft.save_worlds() end
end)

brickcraft.models={catalog=catalog,place=place,gallery=gallery_world,GALLERY=GALLERY}
