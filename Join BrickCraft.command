#!/bin/zsh
# Join a shared BrickCraft server (by default the one hosted on jms).
set -eu
ROOT="${0:A:h}"
source "$ROOT/tools/launcher-common.zsh"
# Play BrickCraft.command passes the address in BRICKCRAFT_SERVER; otherwise ask.
HOST="${BRICKCRAFT_SERVER:-}"
if [[ -z "$HOST" ]]; then read "HOST?Server address [jms.local]: "; HOST="${HOST:-jms.local}"; fi
player_name Guest; NAME="$REPLY"
print "Joining $HOST:$PORT from $NAME. Pick who is playing in the game window."
print "The first time, press \"Register and Join\"."
exec "$LUANTI" --config "$CONF" --address "$HOST" --port "$PORT" --name "$NAME" --go --logfile "$ROOT/logs/client.log"
