#!/bin/zsh
# For players: get the latest BrickCraft from GitHub, then join the shared server.
# The server address is $BRICKCRAFT_SERVER, else user/server_address (one line), else jms.local.
# The braces make zsh read the whole script before running it, since the update may rewrite it.
{
set -eu
ROOT="${0:A:h}"
LAUNCHER="${0:A}"
source "$ROOT/tools/update.zsh"
source "$ROOT/tools/launcher-common.zsh"
HOST="${BRICKCRAFT_SERVER:-}"
[[ -z "$HOST" && -f "$ROOT/user/server_address" ]] && HOST="$(head -n 1 "$ROOT/user/server_address" | tr -d '[:space:]')"
HOST="${HOST:-jms.local}"
# jms is on two networks and advertises jms.local with several IPv4/IPv6 addresses, so the
# name alone can resolve to one this Mac cannot reach. Join the first IPv4 that answers.
ADDR="$HOST"
if [[ ! "$HOST" =~ '^[0-9.]+$' ]]; then
  dns-sd -G v4 "$HOST" > "$ROOT/logs/resolve.txt" 2>/dev/null & DNSSD=$!
  sleep 1.5; kill $DNSSD 2>/dev/null || true
  for ip in $(awk '$(NF-1) ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ && $(NF-1) != "127.0.0.1" {print $(NF-1)}' "$ROOT/logs/resolve.txt" | sort -u) \
            $(ping -c 1 -t 1 "$HOST" 2>/dev/null | sed -n '1s/.*(\([0-9.]*\)).*/\1/p'); do
    if ping -c 1 -t 1 "$ip" >/dev/null 2>&1; then ADDR="$ip"; break; fi
  done
fi
player_name Guest; NAME="$REPLY"
print "Joining $HOST ($ADDR):$PORT from $NAME. Pick who is playing in the game window."
print "The first time, press \"Register and Join\"."
exec "$LUANTI" --config "$CONF" --address "$ADDR" --port "$PORT" --name "$NAME" --go --logfile "$ROOT/logs/client.log"
}
