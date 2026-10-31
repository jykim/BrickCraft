#!/bin/zsh
set -eu
ROOT="${0:A:h}"
export LUANTI_USER_PATH="$ROOT/user"
# Control+click acts as a right click (standard macOS secondary click); SDL handles it.
export SDL_MAC_CTRL_CLICK_EMULATE_RIGHT_CLICK=1
mkdir -p "$ROOT/user/games" "$ROOT/worlds/workshop" "$ROOT/logs"
if [[ ! -e "$ROOT/user/games/brickcraft" ]]; then
  ln -s "$ROOT/game" "$ROOT/user/games/brickcraft"
fi
if [[ ! -f "$ROOT/worlds/workshop/world.mt" ]]; then
  cat > "$ROOT/worlds/workshop/world.mt" <<'WORLD'
gameid = brickcraft
backend = sqlite3
player_backend = sqlite3
auth_backend = sqlite3
mod_storage_backend = sqlite3
creative_mode = false
enable_damage = false
WORLD
fi
# Luanti rewrites the config on exit, so restore key bindings that went missing.
CONF="$ROOT/brickcraft.conf"
ensure() { grep -q "^$1 = " "$CONF" || print -r -- "$1 = $2" >> "$CONF"; }
ensure keymap_forward "SYSTEM_SCANCODE_26|SYSTEM_SCANCODE_82|GAMEPAD_AXIS_MINUS_1"
ensure keymap_backward "SYSTEM_SCANCODE_22|SYSTEM_SCANCODE_81|GAMEPAD_AXIS_PLUS_1"
ensure keymap_left "SYSTEM_SCANCODE_4|SYSTEM_SCANCODE_80|GAMEPAD_AXIS_MINUS_0"
ensure keymap_right "SYSTEM_SCANCODE_7|SYSTEM_SCANCODE_79|GAMEPAD_AXIS_PLUS_0"
ensure keymap_zoom "SYSTEM_SCANCODE_56"
ensure keymap_cmd "SYSTEM_SCANCODE_104"
# F places too, for trackpads without a secondary click.
ensure keymap_place "KEY_RBUTTON|SYSTEM_SCANCODE_9|GAMEPAD_AXIS_PLUS_4"
exec "$ROOT/runtime/luanti.app/Contents/MacOS/luanti" --config "$ROOT/brickcraft.conf" --world "$ROOT/worlds/workshop" --gameid brickcraft --name Builder --go --logfile "$ROOT/logs/client.log"
