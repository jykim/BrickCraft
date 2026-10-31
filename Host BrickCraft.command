#!/bin/zsh
# Run the workshop as a shared server on this Mac, then join it here.
# Others on the same network join with "Join BrickCraft.command".
set -eu
ROOT="${0:A:h}"
source "$ROOT/tools/launcher-common.zsh"
init_world
if pgrep -f -- "--world $WORLD" >/dev/null && ! server_running; then
  print "Single-player BrickCraft has the workshop open. Exit it first (Esc > Exit to OS)."
  exit 1
fi
player_name Builder; NAME="$REPLY"

LOG="$ROOT/logs/server.log"
SERVER_PID=""
if ! server_running; then
  touch "$LOG"; START=$(wc -l < "$LOG")
  "$LUANTI" --server --config "$ROOT/server.conf" --world "$WORLD" --gameid brickcraft \
    --port "$PORT" --logfile "$LOG" >/dev/null 2>&1 &
  SERVER_PID=$!
  # Closing the host's game (or this window) saves the world and stops the server.
  trap 'print "Stopping the server (saving the world)..."; kill $SERVER_PID 2>/dev/null; wait $SERVER_PID 2>/dev/null || true' EXIT INT TERM
  for i in {1..60}; do
    tail -n +$((START + 1)) "$LOG" 2>/dev/null | grep -q "listening on" && break
    kill -0 $SERVER_PID 2>/dev/null || { print "Server failed to start; see $LOG"; exit 1; }
    sleep 0.5
  done
fi

IP=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || print "?")
print ""
print "BrickCraft server is running. Friends on this network can join with:"
print "   Address: $(scutil --get LocalHostName 2>/dev/null || hostname -s).local   (or $IP)"
TS=$(command -v tailscale || print /Applications/Tailscale.app/Contents/MacOS/Tailscale)
TSIP=$("$TS" ip -4 2>/dev/null | head -1 || true)
TSNAME=$("$TS" status --self --json 2>/dev/null | grep -m1 '"HostName"' | cut -d'"' -f4 || true)
if [[ -n "$TSIP" ]]; then print "   Tailscale: ${TSNAME:-$TSIP}   (or $TSIP)"; fi
print "   Port:    $PORT"
print "Use the Luanti app or Join BrickCraft.command (not a web browser)."
print "Keep this window open. Quitting your game stops the server for everyone."
print ""
"$LUANTI" --config "$CONF" --address 127.0.0.1 --port "$PORT" --name "$NAME" --go --logfile "$ROOT/logs/client.log" || true
