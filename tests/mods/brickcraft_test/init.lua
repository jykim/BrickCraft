-- Opt-in checks that run actual engine callbacks in a disposable world. Not part of the
-- game: each tools/test_*.py links this mod into its test world and turns on its setting.
local C=core
local dir=C.get_modpath("brickcraft_test")
local checks={
  brickcraft_integration_test="integration.lua",
  brickcraft_multiplayer_test="multiplayer_test.lua",
  brickcraft_house_test="house_test.lua",
  brickcraft_strict_test="strict_test.lua",
  brickcraft_train_test="train_test.lua",
  brickcraft_technic_test="technic_test.lua",
  brickcraft_war_test="war_test.lua",
  brickcraft_siege_test="siege_test.lua",
  brickcraft_siege_sim="siege_sim.lua",
  brickcraft_ai_test="ai_test.lua", -- with brickcraft_ai_builder, which loads the builders
}
for setting,file in pairs(checks) do
  if C.settings:get_bool(setting,false) then dofile(dir.."/"..file) end
end
