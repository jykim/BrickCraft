# Play/Admin: fast-forward to the latest GitHub version without asking; keep playing if that fails.
# Runs before launcher-common.zsh so an update can fix the launchers themselves.
# BRICKCRAFT_UPDATE=0 or a --no-update argument skips it.
# Local edits are stashed around the pull.
# The launcher sets LAUNCHER to its own path; after an update that brought new commits it
# restarts once, because zsh already holds the old launcher in memory.
# Luanti used to rewrite brickcraft.conf on exit; it now gets user/brickcraft.conf
# (launcher-common.zsh). The first time, before that copy exists, this Mac's rewritten
# brickcraft.conf becomes the copy and brickcraft.conf goes back to the committed one.
if [[ ! -f "$ROOT/user/brickcraft.conf" ]]; then
  mkdir -p "$ROOT/user"
  cp "$ROOT/brickcraft.conf" "$ROOT/user/brickcraft.conf" &&
    git -C "$ROOT" checkout -- brickcraft.conf >/dev/null 2>&1 || true
fi
BRICKCRAFT_DO_UPDATE="${BRICKCRAFT_UPDATE:-1}"
[[ " $* " == *" --no-update "* ]] && BRICKCRAFT_DO_UPDATE=0
if [[ "$BRICKCRAFT_DO_UPDATE" == done ]]; then
  : # restarted after an update
elif [[ "$BRICKCRAFT_DO_UPDATE" == (0|no|n) ]]; then
  print "Skipping the update. Playing the version here."
else
  print "Checking GitHub for the latest BrickCraft..."
  BRICKCRAFT_BEFORE="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || true)"
  if git -C "$ROOT" pull --ff-only --autostash --quiet >/dev/null 2>&1; then
    print "Up to date: $(git -C "$ROOT" log -1 --format='%h %s')"
    if [[ "$(git -C "$ROOT" rev-parse HEAD)" != "$BRICKCRAFT_BEFORE" && -n "${LAUNCHER:-}" ]]; then
      print "Restarting with the new version..."
      BRICKCRAFT_UPDATE=done exec "$LAUNCHER" "$@"
    fi
  else
    print "Could not update (offline, or local changes in the way). Playing the version here."
  fi
fi
unset BRICKCRAFT_DO_UPDATE BRICKCRAFT_BEFORE
