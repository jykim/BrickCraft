#!/bin/zsh
# Join a shared BrickCraft server (by default the one hosted on jms).
set -eu
ROOT="${0:A:h}"
source "$ROOT/tools/launcher-common.zsh"
read "HOST?Server address [jms.local]: "; HOST="${HOST:-jms.local}"
ask_name Leona; NAME="$REPLY"
print "Joining $HOST:$PORT as $NAME. The first time, press \"Register and Join\"."
exec "$LUANTI" --config "$CONF" --address "$HOST" --port "$PORT" --name "$NAME" --go --logfile "$ROOT/logs/client.log"
