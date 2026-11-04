#!/bin/zsh
# Posts the bug reports and ideas players gave their AI builders as GitHub issues on this
# repository. The game writes each into <world>/issues as <id>.md, <id>.label and <id>.title
# (written last); a posted report moves to issues/sent, next to <id>.url (the issue's link),
# which the builder reads back to the player. A report that fails stays queued for next time.
# Usage: tools/post_issues.zsh <world folder>. BRICKCRAFT_ISSUES_DRY=1 prints instead of posting.
set -u
ROOT="${0:A:h:h}"
QUEUE="$1/issues"
[[ -d "$QUEUE" ]] || exit 0
mkdir -p "$QUEUE/sent"
ORIGIN="$(git -C "$ROOT" remote get-url origin 2>/dev/null)"
REPO="${${ORIGIN#*github.com[:/]}%.git}"
COMMIT="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || print unknown)"
if [[ "${BRICKCRAFT_ISSUES_DRY:-0}" != 1 ]]; then
  # This label is the hand-off to improve_issues.zsh. --force also repairs its description
  # or color if it was created manually with different values.
  gh label create player-report -R "$REPO" --color 5319E7 \
    --description "Reported from inside BrickCraft; ready for the improvement worker" --force >/dev/null
fi
for title_file in "$QUEUE"/*.title(N); do
  id="${title_file:t:r}"
  title="$(<"$title_file")"
  label="$(cat "$QUEUE/$id.label" 2>/dev/null || print bug)"
  body="$(mktemp)"
  { cat "$QUEUE/$id.md" 2>/dev/null; print; print "_Game version: ${COMMIT}. Sent from inside BrickCraft by an AI builder._" } > "$body"
  if [[ "${BRICKCRAFT_ISSUES_DRY:-0}" == 1 ]]; then
    print -r -- "Would post to $REPO [$label]: $title"
    url="dry-run:$id"
  elif ! url="$(gh issue create -R "$REPO" --title "$title" --label "$label" --label player-report --body-file "$body" 2>&1)"; then
    print -r -- "$(date '+%F %T') Could not post $id: $url"
    rm -f "$body"
    continue
  else
    print -r -- "$(date '+%F %T') Posted $id: $url"
  fi
  rm -f "$body"
  mv "$QUEUE/$id".{md,label,title} "$QUEUE/sent/" 2>/dev/null
  print -r -- "$url" > "$QUEUE/sent/$id.url"
done
