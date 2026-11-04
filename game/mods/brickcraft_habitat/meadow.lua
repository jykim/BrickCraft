-- A habitat's floor: the workshop baseplate becomes a green meadow (plain grass and
-- flowery grass, like the baseplate it can't be dug), with wild food patches and ponds.
-- Only bare floor changes: anything built stays, and nothing goes where something stands.
-- A variant opts in with def.meadow = {ponds={{x,z,radius},...}, patches=n,
-- patch=<food source id>, pond=<water source id>}.
return function(H)
local C=core
for _,m in ipairs({{"meadow","Meadow","brickcraft_habitat_meadow.png"},{"meadow_flowers","Meadow with flowers","brickcraft_habitat_meadow_flowers.png"}}) do
  C.register_node("brickcraft_habitat:"..m[1],{description=m[2],
    tiles={m[3],"brickcraft_dirt.png","brickcraft_grass_side.png"},
    groups={not_in_creative_inventory=1},diggable=false,is_ground_content=false,drop=""})
end
local function noise(x,z,s) return (math.sin(x*12.9898+z*78.233+s)*43758.5453)%1 end
local FLOOR=12 -- the meadow on the baseplate, then the grass ring around it, ±24
function H.lay_meadow(w,v,done)
  local m=v.meadow
  local minp,maxp={x=w.x-24,y=-1,z=w.z-24},{x=w.x+24,y=2,z=w.z+24}
  C.emerge_area(minp,maxp,function(_,_,remaining)
    if remaining>0 then return end
    local vm=C.get_voxel_manip()
    local emin,emax=vm:read_from_map(minp,maxp)
    local area=VoxelArea:new({MinEdge=emin,MaxEdge=emax})
    local data=vm:get_data()
    local base=C.get_content_id("brickcraft:baseplate")
    local plain,flowers=C.get_content_id("brickcraft_habitat:meadow"),C.get_content_id("brickcraft_habitat:meadow_flowers")
    local air=C.get_content_id("air")
    for z=minp.z,maxp.z do for x=minp.x,maxp.x do
      local i=area:index(x,-1,z)
      if data[i]==base then
        -- Flowers in loose clumps.
        local f=noise(math.floor((x-w.x)/3),math.floor((z-w.z)/3),3)<.35 and noise(x,z,5)<.6
        data[i]=f and flowers or plain
      end
    end end
    vm:set_data(data); vm:write_to_map(true)
    local function bare(q) -- meadow floor with nothing on it
      local f=C.get_node(q).name
      return (f=="brickcraft_habitat:meadow" or f=="brickcraft_habitat:meadow_flowers") and
        C.get_node(vector.offset(q,0,1,0)).name=="air" and C.get_node(vector.offset(q,0,2,0)).name=="air"
    end
    -- Ponds: sunk into the floor.
    local ponds=0
    for _,pd in ipairs(m.ponds or {}) do
      for dz=-pd[3],pd[3] do for dx=-pd[3],pd[3] do
        if dx*dx+dz*dz<=pd[3]*pd[3]+.5 then
          local q={x=w.x+pd[1]+dx,y=-1,z=w.z+pd[2]+dz}
          if bare(q) then C.set_node(q,{name="brickcraft_habitat:"..m.pond}); ponds=ponds+1 end
        end
      end end
    end
    -- Wild food patches, scattered.
    local placed,tries=0,0
    while placed<(m.patches or 0) and tries<400 do
      tries=tries+1
      local x,z=math.floor(noise(tries,1,7)*44)-22,math.floor(noise(1,tries,9)*44)-22
      local q={x=w.x+x,y=-1,z=w.z+z}
      if math.max(math.abs(x),math.abs(z))>5 and bare(q) then
        C.set_node(vector.offset(q,0,1,0),{name="brickcraft_habitat:"..m.patch}); placed=placed+1
      end
    end
    C.log("action","BrickCraft habitat: meadow laid in "..w.name.." ("..ponds.." pond cells, "..placed.." "..m.patch.."s)")
    if done then done() end
  end)
end
end
