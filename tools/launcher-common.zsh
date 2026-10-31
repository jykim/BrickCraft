# Shared setup for the BrickCraft launchers. Expects ROOT to be the project folder.
export LUANTI_USER_PATH="$ROOT/user"
# Control+click acts as a right click (standard macOS secondary click); SDL handles it.
export SDL_MAC_CTRL_CLICK_EMULATE_RIGHT_CLICK=1
mkdir -p "$ROOT/user/games" "$ROOT/logs"
if [[ ! -e "$ROOT/user/games/brickcraft" ]]; then
  ln -s "$ROOT/game" "$ROOT/user/games/brickcraft"
fi
WORLD="${BRICKCRAFT_WORLD:-$ROOT/worlds/workshop}"
PORT="${BRICKCRAFT_PORT:-30000}"

LUANTI=""
for app in "$ROOT/runtime/luanti.app" /Applications/Luanti.app /Applications/luanti.app; do
  if [[ -x "$app/Contents/MacOS/luanti" ]]; then LUANTI="$app/Contents/MacOS/luanti"; break; fi
done
if [[ -z "$LUANTI" ]]; then
  print "Luanti 5.17 was not found. Install it from https://www.luanti.org/en/downloads/"
  print "or place it at $ROOT/runtime/luanti.app (see docs/THIRD_PARTY.md)."
  exit 1
fi

init_world() {
  mkdir -p "$WORLD"
  if [[ ! -f "$WORLD/world.mt" ]]; then
    cat > "$WORLD/world.mt" <<'WORLDMT'
gameid = brickcraft
backend = sqlite3
player_backend = sqlite3
auth_backend = sqlite3
mod_storage_backend = sqlite3
creative_mode = false
enable_damage = false
WORLDMT
  fi
}

# A world must only be open in one process: the shared server or single-player.
server_running() { pgrep -f -- "--server .*--world $WORLD" >/dev/null; }

# Luanti rewrites the config on exit, so restore key bindings that went missing.
CONF="$ROOT/brickcraft.conf"
ensure() { grep -q "^$1 = " "$CONF" || print -r -- "$1 = $2" >> "$CONF"; }
ensure keymap_forward "SYSTEM_SCANCODE_26|SYSTEM_SCANCODE_82|GAMEPAD_AXIS_MINUS_1"
ensure keymap_backward "SYSTEM_SCANCODE_22|SYSTEM_SCANCODE_81|GAMEPAD_AXIS_PLUS_1"
ensure keymap_left "SYSTEM_SCANCODE_4|SYSTEM_SCANCODE_80|GAMEPAD_AXIS_MINUS_0"
ensure keymap_right "SYSTEM_SCANCODE_7|SYSTEM_SCANCODE_79|GAMEPAD_AXIS_PLUS_0"
# Tab picks the next piece too (same control as E).
ensure keymap_aux1 "SYSTEM_SCANCODE_8|SYSTEM_SCANCODE_43|GAMEPAD_BUTTON_2"
ensure keymap_zoom "SYSTEM_SCANCODE_56"
ensure keymap_cmd "SYSTEM_SCANCODE_104"
# F places too, for trackpads without a secondary click.
ensure keymap_place "KEY_RBUTTON|SYSTEM_SCANCODE_9|GAMEPAD_AXIS_PLUS_4"
ensure keymap_sneak "SYSTEM_SCANCODE_24"

# Ask for a player name (letters, digits, - and _; Luanti allows up to 20).
ask_name() {
  local name
  while true; do
    read "name?Your name [$1]: "
    name="${name:-$1}"
    if [[ "$name" =~ '^[A-Za-z0-9_-]{1,20}$' ]]; then REPLY="$name"; return; fi
    print "Use 1-20 letters, digits, - or _ (no spaces)."
  done
}
