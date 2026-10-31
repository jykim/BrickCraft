# Play/Admin: fast-forward to the latest GitHub version; keep playing if that fails.
# Runs before launcher-common.zsh so an update can fix the launchers themselves.
# Luanti rewrites brickcraft.conf on exit, so local edits are stashed around the pull.
print "Checking GitHub for the latest BrickCraft..."
if git -C "$ROOT" pull --ff-only --autostash --quiet 2>/dev/null; then
  print "Up to date: $(git -C "$ROOT" log -1 --format='%h %s')"
else
  print "Could not update (offline, or local changes in the way). Playing the version here."
fi
