-- Keep the stock Luanti main menu, but recover from a BrickCraft server restart without
-- making a player find and click Reconnect. This script is selected only by BrickCraft's
-- private config copy; it does not modify the Luanti app.
dofile(core.get_mainmenu_path() .. DIR_DELIM .. "init.lua")

local stock_update = ui.update
local stock_button_handler = core.button_handler
local retry_pending = false
local retry_cancelled = false
local retry_count = 0
local MAX_RETRIES = 30

local function transient_disconnect()
  if not gamedata then return false end
  if gamedata.reconnect_requested then return true end
  local message = (gamedata.errormessage or ""):lower()
  return message:find("connection timed out",1,true)
      or message:find("server shutting down",1,true)
      or message:find("connection reset",1,true)
      or message:find("connection closed",1,true)
      or message:find("failed to connect",1,true)
end

local function reconnect_after_delay()
  retry_pending = true
  retry_count = retry_count + 1
  gamedata.reconnect_requested = false
  gamedata.errormessage = nil
  ui.overridden = true
  core.update_formspec(table.concat({
    "size[10,4]real_coordinates[true]",
    "label[0.7,1.0;BrickCraft lost the server. Waiting for it to restart...]",
    ("label[0.7,1.6;Reconnect attempt %d of %d]"):format(retry_count,MAX_RETRIES),
    "button[3.5,2.6;3,0.8;brickcraft_cancel_retry;Stop retrying]"
  }))
  core.handle_async(function(seconds)
    os.execute("/bin/sleep " .. tonumber(seconds))
    return true
  end, 2, function()
    retry_pending = false
    if retry_cancelled then return end
    gamedata.do_reconnect = true
    core.start()
  end)
end

function ui.update()
  if not retry_pending and not retry_cancelled and retry_count < MAX_RETRIES
      and transient_disconnect() then
    reconnect_after_delay()
    return
  end
  stock_update()
end

core.button_handler = function(fields)
  if fields.brickcraft_cancel_retry then
    retry_cancelled = true
    retry_pending = false
    gamedata.reconnect_requested = false
    gamedata.errormessage = nil
    stock_update()
    return
  end
  stock_button_handler(fields)
end
