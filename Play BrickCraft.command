#!/bin/zsh
# For players: get the latest BrickCraft from GitHub, then join the shared server.
# It joins jms over Tailscale, falling back to the local network (see the routes below).
# The braces make zsh read the whole script before running it, since the update may rewrite it.
{
set -eu
ROOT="${0:A:h}"
LAUNCHER="${0:A}"
source "$ROOT/tools/update.zsh"
source "$ROOT/tools/launcher-common.zsh"
# Routes to try, in order: an address you set ($BRICKCRAFT_SERVER or user/server_address),
# then jms over Tailscale, then jms on the local network.
CHOSEN="${BRICKCRAFT_SERVER:-}"
[[ -z "$CHOSEN" && -f "$ROOT/user/server_address" ]] && CHOSEN="$(head -n 1 "$ROOT/user/server_address" | tr -d '[:space:]')"
NAMES=(${(u)${=:-$CHOSEN jms jms.local}})
# A name can stand for several addresses (jms is on two networks plus Tailscale), and a
# reachable address is not proof the game server is up. So each IPv4 gets a tiny BrickCraft
# (Luanti) hello over UDP, and Play joins the first one the server answers.
PLAYLOG="$ROOT/logs/play.log"
print "\n$(date '+%F %T') Play: looking for the server (port $PORT)" >> "$PLAYLOG"
probe() { printf '\x4f\x45\x74\x03\x00\x00\x00\x03\xff\xdc\x01' | nc -u -w 1 "$1" "$PORT" 2>/dev/null | head -c 4 | grep -q 'OEt'; }
ipv4s() {
  if [[ "$1" =~ '^[0-9.]+$' ]]; then print "$1"; return; fi
  ping -c 1 -t 1 "$1" 2>/dev/null | sed -n '1s/.*(\([0-9.]*\)).*/\1/p'
  if [[ "$1" == *.local ]]; then
    dns-sd -G v4 "$1" > "$ROOT/logs/resolve.txt" 2>/dev/null & local pid=$!
    sleep 1.5; kill $pid 2>/dev/null || true
    awk '$(NF-1) ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ && $(NF-1) != "127.0.0.1" {print $(NF-1)}' "$ROOT/logs/resolve.txt"
  fi
}
HOST="" ADDR=""
for name in $NAMES; do
  ips=(${(u)$(ipv4s "$name")})
  if (( ! $#ips )); then print "  $name: no address (not on this network?)" | tee -a "$PLAYLOG"; continue; fi
  for ip in $ips; do
    if probe "$ip"; then
      print "  $name ($ip): server answered" | tee -a "$PLAYLOG"; HOST="$name"; ADDR="$ip"; break 2
    fi
    print "  $name ($ip): no answer" | tee -a "$PLAYLOG"
  done
done
if [[ -z "$ADDR" ]]; then
  print "No BrickCraft server answered (tried: ${(j:, :)NAMES}). Details: logs/play.log" | tee -a "$PLAYLOG"
  print "Check that Admin BrickCraft.command is running on jms and that Tailscale is on here."
  exit 1
fi
player_name Guest; NAME="$REPLY"
print "Joining $HOST ($ADDR):$PORT from $NAME. Pick who is playing in the game window." | tee -a "$PLAYLOG"
exec "$LUANTI" --config "$CONF" --address "$ADDR" --port "$PORT" --name "$NAME" --go --logfile "$ROOT/logs/client.log"
}
