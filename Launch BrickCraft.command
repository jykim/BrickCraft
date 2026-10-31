#!/bin/zsh
set -eu
ROOT="${0:A:h}"
export LUANTI_USER_PATH="$ROOT/user"
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
exec "$ROOT/runtime/luanti.app/Contents/MacOS/luanti" --config "$ROOT/brickcraft.conf" --world "$ROOT/worlds/workshop" --gameid brickcraft --name Builder --go --logfile "$ROOT/logs/client.log"
