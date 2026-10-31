#!/bin/zsh
# Single-player: the workshop world on this Mac only.
set -eu
ROOT="${0:A:h}"
source "$ROOT/tools/launcher-common.zsh"
if server_running; then
  print "The shared BrickCraft server is running on this Mac."
  print "Join it with \"Play BrickCraft.command\" or stop it first."
  exit 1
fi
init_world
exec "$LUANTI" --config "$CONF" --world "$WORLD" --gameid brickcraft --name Builder --go --logfile "$ROOT/logs/client.log"
