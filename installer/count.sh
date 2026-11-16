# agency-count [--once] EVENT [KEY=VALUE ...]
#
# Sends one anonymous event to PostHog, so we can count how many setups
# start, how many installs finish, and how many machines then start. Every
# event carries the computer's maker and model and the agency commit, plus
# the KEY=VALUE pairs given. No names, keys or addresses.
#
# The ID is random, made once per boot of the stick and kept in
# $AGENCY_COUNT_DIR, so the events of one install line up. `--once` sends an
# event at most once per boot. DO_NOT_TRACK=1 turns it all off.
#
# It never fails and never waits more than five seconds.

once=0
if [ "${1:-}" = --once ]; then
  once=1
  shift
fi
event=${1:?usage: agency-count [--once] EVENT [KEY=VALUE ...]}
shift

if [ -n "${DO_NOT_TRACK:-}" ] && [ "$DO_NOT_TRACK" != 0 ]; then exit 0; fi

state=${AGENCY_COUNT_DIR:-/run/agency-count}
mkdir -p "$state" 2>/dev/null || exit 0
[ -s "$state/id" ] || cat /proc/sys/kernel/random/uuid >"$state/id"
if [ "$once" = 1 ]; then
  [ ! -e "$state/$event" ] || exit 0
  : >"$state/$event"
fi

dmi() {
  if [ -r "/sys/class/dmi/id/$1" ]; then
    tr -s '[:space:]' ' ' <"/sys/class/dmi/id/$1" | sed 's/ $//'
  fi
}

pairs=()
for pair in "$@"; do pairs+=(--arg "${pair%%=*}" "${pair#*=}"); done

# "true" and "false" are sent as booleans, everything else as text.
body=$(jq -cn \
  --arg agency_event "$event" \
  --arg agency_id "$(cat "$state/id")" \
  --arg vendor "$(dmi sys_vendor)" \
  --arg model "$(dmi product_name)" \
  --arg rev "$AGENCY_COUNT_REV" \
  "${pairs[@]}" \
  '{
    api_key: "phc_yBGvjZW4wAfvVSufdysvJxTWdoyQAtP7fcxrg4khcif4",
    event: $agency_event,
    distinct_id: $agency_id,
    properties: (
      $ARGS.named
      | del(.agency_event, .agency_id)
      | map_values(if . == "true" then true elif . == "false" then false else . end)
      | . + {"$process_person_profile": false}
    )
  }') || exit 0

curl -fsS --max-time 5 -o /dev/null -H 'Content-Type: application/json' \
  -d "$body" https://us.i.posthog.com/i/v0/e/ 2>/dev/null || true
