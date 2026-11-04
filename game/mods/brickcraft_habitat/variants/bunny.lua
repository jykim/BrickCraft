-- Bunnyland: bunnies to keep safe, a giant bunny statue, carrot patches and water troughs,
-- bunny skins. A world named "bunnyland" becomes it; /habitat set bunny makes any world one.
-- A new habitat copies this file: its creature, sources, skins, statue and variant.
return function(H)
H.register_creature("bunny",{label="Bunny",mesh="brickcraft_habitat_bunny.obj",
  textures={"brickcraft_habitat_bunny.png","brickcraft_habitat_bunny_brown.png","brickcraft_habitat_bunny_gray.png"},
  speed=1.8,run=3.2,jump=6.6,hop=3,hp=10,hunger=420,thirst=300,alert=9})

H.register_source("carrot_patch",{kind="food",label="Carrot patch",units=6,regrow=20,height=.3,
  tiles={"brickcraft_habitat_patch_top.png","brickcraft_habitat_patch_empty.png","brickcraft_habitat_patch_side.png"},
  empty_tiles={"brickcraft_habitat_patch_empty.png","brickcraft_habitat_patch_empty.png","brickcraft_habitat_patch_empty.png"},
  inventory_image="brickcraft_habitat_carrot.png"})
-- The meadow's own: clover tufts (wild food, grazed down, grows back) and ponds.
H.register_source("clover",{kind="food",label="Clover patch",units=3,regrow=40,height=.12,alpha=true,
  tiles={"brickcraft_habitat_clover.png","brickcraft_habitat_clover.png","brickcraft_habitat_clover.png"},
  empty_tiles={"brickcraft_habitat_clover_eaten.png","brickcraft_habitat_clover_eaten.png","brickcraft_habitat_clover_eaten.png"},
  inventory_image="brickcraft_habitat_clover.png"})
H.register_source("pond",{kind="water",label="Pond",height=.8,
  tiles={"brickcraft_habitat_water.png","brickcraft_dirt.png","brickcraft_dirt.png"},
  inventory_image="brickcraft_habitat_trough.png"})
H.register_source("water_trough",{kind="water",label="Water trough",height=.45,
  tiles={"brickcraft_habitat_water.png","brickcraft_habitat_trough_side.png","brickcraft_habitat_trough_side.png"},
  inventory_image="brickcraft_habitat_trough.png"})

-- Colony structures. A hutch is open at the front (-z, toward whoever placed it): bunnies
-- hop in, and inside no predator reaches them and nothing from the sky hits them. On low
-- ground a flood still gets in.
H.register_structure("hutch",{label="Bunny hutch",effect="home",capacity=4,hideout=true,walkable=false,
  about="Home for 4 bunnies, and a hiding place from predators and asteroids",
  node_box={{-.5,.25,-.5,.5,.5,.5},{-.5,-.5,.4,.5,.25,.5},{-.5,-.5,-.5,-.4,.25,.5},{.4,-.5,-.5,.5,.25,.5}},
  tiles={"brickcraft_habitat_hutch_roof.png","brickcraft_habitat_hutch_side.png","brickcraft_habitat_hutch_side.png",
    "brickcraft_habitat_hutch_side.png","brickcraft_habitat_hutch_side.png","brickcraft_habitat_hutch_front.png"},
  inventory_image="brickcraft_habitat_hutch.png"})
H.register_structure("nursery",{label="Nursery",effect="nursery",
  about="Babies come half again as fast (up to 2 nurseries count)",
  node_box={{-.5,-.5,-.5,.5,-.2,.5},{-.4,-.2,-.4,.4,-.1,.4}},
  tiles={"brickcraft_habitat_nursery_top.png","brickcraft_habitat_nursery_side.png","brickcraft_habitat_nursery_side.png"},
  inventory_image="brickcraft_habitat_nursery.png"})
H.register_structure("lookout",{label="Lookout",effect="lookout",
  about="Bunnies within 20 see predators from 20 away, and you're warned",
  node_box={{-.1,-.5,-.1,.1,.3,.1},{-.4,.3,-.4,.4,.5,.4}},
  tiles={"brickcraft_habitat_lookout_top.png","brickcraft_habitat_lookout_top.png","brickcraft_habitat_lookout.png"},
  inventory_image="brickcraft_habitat_lookout_icon.png"})

H.register_fence("fence",{label="Fence",gate=true,
  tiles={"brickcraft_habitat_hutch_side.png"},inventory_image="brickcraft_habitat_fence.png",
  gate_image="brickcraft_habitat_gate.png"})

for _,s in ipairs({{"snow","Snow Bunny"},{"cocoa","Cocoa Bunny"},{"gray","Gray Bunny"},{"rose","Rose Bunny"}}) do
  H.register_skin(s[1],{label=s[2],mesh="brickcraft_habitat_bunny_person.obj",texture="brickcraft_habitat_skin_"..s[1]..".png"})
end

-- A giant sitting bunny, 27 bricks to the ear tips, on a gold plinth, facing the baseplate.
-- Its front is toward -z (the world's middle); x is its left and right.
local function statue(put,S)
  S.box(put,-6,0,-6,6,1,6,"gold")
  S.ellipsoid(put,0,7,1,5,6,5,"cream")                 -- body
  S.ellipsoid(put,-4,5,2,2.5,3.2,4,"cream")            -- haunches
  S.ellipsoid(put,4,5,2,2.5,3.2,4,"cream")
  S.ellipsoid(put,-2,2.6,-4,1.3,1,2.2,"cream")         -- front paws
  S.ellipsoid(put,2,2.6,-4,1.3,1,2.2,"cream")
  S.ellipsoid(put,0,14,-2,4,4,4,"cream")               -- head
  S.ellipsoid(put,-1.7,21,-1,1.3,6.2,1,"cream")        -- ears
  S.ellipsoid(put,1.7,21,-1,1.3,6.2,1,"cream")
  for _,x in ipairs({-2,2}) do                         -- inner ears, facing front
    for y=17,25 do put(x,y,-2,"rose") end
  end
  for _,x in ipairs({-2,2}) do put(x,15,-5,"navy"); put(x,16,-5,"navy") end -- eyes
  put(0,13,-6,"rose")                                  -- nose
  put(-1,12,-6,"cream"); put(1,12,-6,"cream")          -- cheeks
  S.ellipsoid(put,0,5,6.2,1.8,1.8,1.6,"cream")         -- tail
  for x=-3,3 do put(x,1,-7+0,"rose") end               -- a rose stripe on the plinth's front
end

H.register_variant("bunny",{label="Bunnyland",plural="bunnies",creature="bunny",count=8,max=16,
  statue={x=0,z=37,radius=7,height=30,build=statue},
  sources={{"carrot_patch",-8,26},{"carrot_patch",8,26},{"carrot_patch",-16,26},
    {"water_trough",0,25},{"water_trough",16,26}},
  kit={carrot_patch=4,water_trough=2},
  predators={"wolf","lion","eagle"},
  skins={"snow","cocoa","gray","rose"},
  match_names={"bunnyland"},
  -- The baseplate becomes a meadow with ponds and clover patches (meadow.lua).
  meadow={ponds={{-12,-3,2},{14,6,2},{-9,15,1},{6,-14,1}},patches=16,patch="clover",pond="pond"},
  welcome="Bunnyland is the bunnies' home; the giant bunny statue on the north hill watches over them.",
  wave={110,205}, -- balance: tools/sim_habitat.py (README, Bunnyland)
  keep_in="Keep your colony in a closed ring of fence (you start with 32 pieces and a gate) with its hutches, carrots and water inside. "..
    "Bunnies stay near their hutches and can't hop a fence; close the gate behind you (separator right click), "..
    "and don't let a hill touch the fence: animals climb hills.",
  -- Each player's own colony (colony.lua). Balance from tools/sim_habitat.py.
  pack_per=12,
  colony={start=5,max=60,clovers=40,income=.1,birth=90,feeds=4,waters=6,happy=60,
    kit={hutch=2,carrot_patch=1,water_trough=1,fence=32,fence_gate=1},
    shop={{"fence",10,8},{"fence_gate",5},{"hutch",25},{"carrot_patch",15},{"water_trough",15},{"nursery",60},{"lookout",40}},
    levels={{0,"Burrow"},{10,"Warren",50},{20,"Village",100},{35,"Town",150},{50,"Bunny City",250}}},
  tip="Fences two bricks high stop wolves and lions. Roofs hide bunnies from eagles and asteroids. "..
    "Bunnies need carrots and water: keep them where predators and floods can't reach."})
end
