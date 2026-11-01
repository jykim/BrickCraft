#!/bin/zsh
# For the host Mac (jms): get the latest BrickCraft from GitHub, run the workshop as a
# shared server, and join it here. Other Macs join with "Play BrickCraft.command".
# --headless (or BRICKCRAFT_HEADLESS=1): no game window here; the server just waits for
# players until Ctrl-C (or this window closes), then saves and stops.
# The braces make zsh read the whole script before running it, since the update may rewrite it.
{
set -eu
ROOT="${0:A:h}"
LAUNCHER="${0:A}"
source "$ROOT/tools/update.zsh"
source "$ROOT/tools/launcher-common.zsh"
init_world
HEADLESS=${BRICKCRAFT_HEADLESS:-0}
[[ " $* " == *" --headless "* ]] && HEADLESS=1
if pgrep -f -- "--world $WORLD" >/dev/null && ! server_running; then
  print "Single-player BrickCraft has the workshop open. Exit it first (Esc > Exit to OS)."
  exit 1
fi
[[ $HEADLESS == 1 ]] || { player_name Builder; NAME="$REPLY"; }

LOG="$ROOT/logs/server.log"
SERVER_PID=""
POST_PID=""
if [[ $HEADLESS == 1 ]] && server_running; then
  print "A BrickCraft server is already running for this world. Stop it first (quit the host's game)."
  exit 1
fi
if ! server_running; then
  touch "$LOG"; START=$(wc -l < "$LOG")
  "$LUANTI" --server --config "$ROOT/server.conf" --world "$WORLD" --gameid brickcraft \
    --port "$PORT" --logfile "$LOG" >/dev/null 2>&1 &
  SERVER_PID=$!
  # Closing the host's game (or this window) saves the world and stops the server.
  trap 'kill $POST_PID 2>/dev/null; print "Stopping the server (saving the world)..."; kill $SERVER_PID 2>/dev/null; wait $SERVER_PID 2>/dev/null || true' EXIT INT TERM
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
print "Use Play BrickCraft.command or the Luanti app (not a web browser)."
# The AI builders design requests with Claude Code through the Local AI API.
if curl -s -m 2 http://127.0.0.1:8099/health >/dev/null 2>&1; then
  print "AI builders are on: Claude Code via the Local AI API (127.0.0.1:8099)."
else
  print "AI builders use built-in blueprints: the Local AI API (127.0.0.1:8099) is not running."
fi
# Bug reports players give their AI builders become GitHub issues while this server runs.
if [[ -n "$SERVER_PID" && "${BRICKCRAFT_ISSUES:-1}" != 0 ]] && command -v gh >/dev/null && gh auth status -h github.com >/dev/null 2>&1; then
  ( while kill -0 $SERVER_PID 2>/dev/null; do "$ROOT/tools/post_issues.zsh" "$WORLD" >> "$ROOT/logs/issues.log" 2>&1; sleep 15; done ) &
  POST_PID=$!
  print "Bug reports to AI builders (\"report ...\") go to GitHub issues; see logs/issues.log."
elif [[ -n "$SERVER_PID" ]]; then
  print "Bug reports to AI builders stay in $WORLD/issues: sign in with \"gh auth login\" to post them to GitHub."
fi
if [[ $HEADLESS == 1 ]]; then
  print "Headless: no game window here. Waiting for players; Ctrl-C saves the world and stops the server."
  print ""
  # Who comes and goes, from the server log.
  tail -n 0 -f "$LOG" | grep --line-buffered -E "joins game|leaves game|timed out" | sed -u 's/^.*ACTION\[Server\]: //' &
  TAIL_PID=$!
  trap 'kill $TAIL_PID $POST_PID 2>/dev/null; print "Stopping the server (saving the world)..."; kill $SERVER_PID 2>/dev/null; wait $SERVER_PID 2>/dev/null || true' EXIT INT TERM
  wait $SERVER_PID || true
  exit
fi
print "Keep this window open. Quitting your game stops the server for everyone."
print ""
"$LUANTI" --config "$CONF" --address 127.0.0.1 --port "$PORT" --name "$NAME" --go --logfile "$ROOT/logs/client.log" || true
exit
}
