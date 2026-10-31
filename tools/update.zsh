# Play/Admin: optionally fast-forward to the latest GitHub version; keep playing if that fails.
# Runs before launcher-common.zsh so an update can fix the launchers themselves.
# Asks (default yes after 5 s); BRICKCRAFT_UPDATE=1/0 or a --no-update argument skips the question.
# Luanti rewrites brickcraft.conf on exit, so local edits are stashed around the pull.
BRICKCRAFT_DO_UPDATE="${BRICKCRAFT_UPDATE:-}"
[[ " $* " == *" --no-update "* ]] && BRICKCRAFT_DO_UPDATE=0
if [[ -z "$BRICKCRAFT_DO_UPDATE" ]]; then
  BRICKCRAFT_DO_UPDATE=1
  if [[ -t 0 ]] && read -t 5 -k 1 "REPLY?Update BrickCraft from GitHub first? [Y/n] "; then
    print
    [[ "$REPLY" == [nN] ]] && BRICKCRAFT_DO_UPDATE=0
  else
    print
  fi
fi
if [[ "$BRICKCRAFT_DO_UPDATE" == (0|no|n) ]]; then
  print "Skipping the update. Playing the version here."
elif git -C "$ROOT" pull --ff-only --autostash --quiet 2>/dev/null; then
  print "Up to date: $(git -C "$ROOT" log -1 --format='%h %s')"
else
  print "Could not update (offline, or local changes in the way). Playing the version here."
fi
unset BRICKCRAFT_DO_UPDATE
