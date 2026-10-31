#!/bin/zsh
# For players: get the latest BrickCraft from GitHub, then join the shared server.
# The server address is $BRICKCRAFT_SERVER, else user/server_address (one line), else jms.local.
# The braces make zsh read the whole script before running it, since the update may rewrite it.
{
set -eu
ROOT="${0:A:h}"
source "$ROOT/tools/update.zsh"
SERVER="${BRICKCRAFT_SERVER:-}"
[[ -z "$SERVER" && -f "$ROOT/user/server_address" ]] && SERVER="$(head -n 1 "$ROOT/user/server_address" | tr -d '[:space:]')"
BRICKCRAFT_SERVER="${SERVER:-jms.local}" exec "$ROOT/Join BrickCraft.command"
exit
}
