#!/bin/zsh
# For players: get the latest BrickCraft from GitHub, then join the shared server.
# The server address is $BRICKCRAFT_SERVER, else user/server_address (one line), else jms.local.
# The braces make zsh read the whole script before running it, since the update may rewrite it.
{
set -eu
ROOT="${0:A:h}"
source "$ROOT/tools/update.zsh"
source "$ROOT/tools/launcher-common.zsh"
HOST="${BRICKCRAFT_SERVER:-}"
[[ -z "$HOST" && -f "$ROOT/user/server_address" ]] && HOST="$(head -n 1 "$ROOT/user/server_address" | tr -d '[:space:]')"
HOST="${HOST:-jms.local}"
player_name Guest; NAME="$REPLY"
print "Joining $HOST:$PORT from $NAME. Pick who is playing in the game window."
print "The first time, press \"Register and Join\"."
exec "$LUANTI" --config "$CONF" --address "$HOST" --port "$PORT" --name "$NAME" --go --logfile "$ROOT/logs/client.log"
}
