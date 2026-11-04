-- Predators any habitat can use. Gravity is twice Earth's (like the knights), so a jump of
-- 6.6 (1.1 bricks, plus a 0.3 step) clears one brick and nothing on four legs gets over a wall two bricks high.
-- A fence piece stands 1.5 high: only the lion (leaps, jump 8: 1.6) clears it.
return function(H)
H.register_predator("wolf",{label="Wolf",mesh="brickcraft_habitat_wolf.obj",texture="brickcraft_habitat_wolf.png",
  hp=6,speed=3.9,damage=4,bite=1.2,jump=6.6,appetite=2,stay=150,sight=40,
  box={-.48,0,-.48,.48,1,.48}, -- wide enough that the long body doesn't poke through a fence
  tip="Fences two bricks high keep wolves out (but not where a hill reaches the fence)."})
H.register_predator("lion",{label="Lion",mesh="brickcraft_habitat_lion.obj",texture="brickcraft_habitat_lion.png",
  hp=12,speed=3.5,damage=10,bite=1.5,jump=8,leaps=true,appetite=2,stay=120,sight=40,reach=1.4,
  box={-.6,0,-.6,.6,1.3,.6},
  tip="Lions leap fences! Chase it off together, or keep the bunnies behind a brick wall two high."})
H.register_predator("eagle",{label="Eagle",mesh="brickcraft_habitat_eagle.obj",texture="brickcraft_habitat_eagle.png",
  flies=true,hp=4,speed=8,dive=11,damage=10,bite=1,appetite=2,stay=100,sight=45,altitude=14,
  box={-.6,0,-.6,.6,.6,.6},warning="An eagle is circling in",
  tip="Bunnies under a roof are hidden from eagles."})
end
