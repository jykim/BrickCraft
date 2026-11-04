# Print the timestamp only when the server has a fresh, empty-player heartbeat.
# The caller must observe it advance before restarting.
idle_heartbeat() {
  jq -er --argjson now "$(date +%s)" '
    select(.running == true and .players == 0 and
      (.updated | type) == "number" and .updated <= $now and $now - .updated <= 6)
    | .updated' "$1" 2>/dev/null
}
