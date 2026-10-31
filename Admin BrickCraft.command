#!/bin/zsh
# For the host Mac (jms): get the latest BrickCraft from GitHub, then start the shared
# server and join it here. Quitting the game stops the server for everyone.
# The braces make zsh read the whole script before running it, since the update may rewrite it.
{
set -eu
ROOT="${0:A:h}"
source "$ROOT/tools/update.zsh"
exec "$ROOT/Host BrickCraft.command"
exit
}
