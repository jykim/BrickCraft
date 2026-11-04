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
    --description "Reported from inside BrickCraft; ready for the improvement worker" --force >/dev/null || exit 1
fi
for title_file in "$QUEUE"/*.title(N); do
  id="${title_file:t:r}"
  title="$(<"$title_file")"
  label="$(cat "$QUEUE/$id.label" 2>/dev/null || print bug)"
  image_markdown=""
  if [[ -f "$QUEUE/$id.view.json" && "${BRICKCRAFT_ISSUES_DRY:-0}" != 1 ]]; then
    if ! image_markdown="$(python3 "$ROOT/tools/prepare_report_screenshot.py" "$QUEUE" "$id" "$REPO")"; then
      print -u2 "Could not prepare screenshot for $id; report remains queued for retry."
      continue
    fi
  fi
  body="$(mktemp)"
  { cat "$QUEUE/$id.md" 2>/dev/null; print -r -- "$image_markdown"; print; print "_Game version: ${COMMIT}. Sent from inside BrickCraft by an AI builder._" } > "$body"
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
  for extra in "$QUEUE/$id".{jpg,image.md,recipient.json}(N); do
    mv "$extra" "$QUEUE/sent/"
  done
  rm -f "$QUEUE/$id.view.json" "$QUEUE/$id.view.mts"
  print -r -- "$url" > "$QUEUE/sent/$id.url"
done
