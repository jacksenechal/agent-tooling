#!/usr/bin/env bash
# pi-swarm-collect.sh — summarize a pi-swarm results dir into a parseable status table.
#
# For every <name>.txt (+ its <name>.txt.jsonl stream) produced by pi-research.sh in DIR,
# print one row: name, best-effort reason, answer chars, whether a SOURCES: block is present,
# and a suggested orchestrator action. This is the feed the orchestrator (Claude) maps onto
# TaskUpdate calls when driving the swarm through the Task ledger — read one table instead of
# grepping every file.
#
# NOTE on `reason`: the authoritative reason= is on the wrapper's stderr `done` line (it also
# knows the exit code, so it can report stall/hardcap). This collector only has the result files,
# so it derives reason from the stream itself: a provider error in the stream -> autherror|error,
# else no answer text -> empty, else -> ok. Prefer the live `done` line's reason when you have it;
# use this for a dir-level snapshot (e.g. across retry waves or in a fresh session). A worker that
# was killed mid-run (stall/hardcap) shows here as ok/empty with no `agent_end` — flagged as
# `truncated?` so you don't mistake a partial for a clean finish.
#
# Usage: pi-swarm-collect.sh RESULTS_DIR
set -euo pipefail

DIR="${1:?usage: pi-swarm-collect.sh RESULTS_DIR}"
[ -d "$DIR" ] || { echo "pi-swarm-collect: not a directory: $DIR" >&2; exit 2; }
shopt -s nullglob

printf '%-22s %-11s %7s %7s %-10s %s\n' NAME REASON CHARS SOURCES STREAM ACTION
found=0
for txt in "$DIR"/*.txt; do
  [ -e "$txt" ] || continue
  found=1
  name="$(basename "$txt" .txt)"
  jsonl="$txt.jsonl"

  chars="$(wc -c < "$txt" 2>/dev/null | tr -d ' ')"; chars="${chars:-0}"
  grep -q '^SOURCES:' "$txt" 2>/dev/null && sources=yes || sources=no

  err=""; stream=ok
  if [ -f "$jsonl" ]; then
    read -r err stream < <(python3 - "$jsonl" <<'PY'
import json, sys
err, seen_end = "", False
with open(sys.argv[1], "r", errors="replace") as fh:
    for line in fh:
        line = line.strip()
        if not line:
            continue
        try:
            ev = json.loads(line)
        except Exception:
            continue
        if ev.get("type") == "agent_end":
            seen_end = True
        m = ev.get("message") or {}
        if m.get("stopReason") == "error" and m.get("errorMessage"):
            err = m["errorMessage"].replace("\n", " ").strip()
# field 1: error (or '-'); field 2: stream completeness
print((err or "-").replace(" ", " "), "ok" if seen_end else "truncated?")
PY
)
    err="${err//$' '/ }"; [ "$err" = "-" ] && err=""
  else
    stream="no-jsonl"
  fi

  # classify reason (mirror of pi-research.sh's logic, minus exit-code-dependent stall/hardcap)
  if [ -n "$err" ]; then
    case "$err" in
      *[Bb]alance*|*[Bb]illing*|401*|*[Uu]nauthorized*|403*|*[Ff]orbidden*|*[Ii]nsufficient*|*[Pp]ayment*|*[Qq]uota*) reason=autherror ;;
      *) reason=error ;;
    esac
  elif [ "$chars" -eq 0 ]; then
    reason=empty
  else
    reason=ok
  fi

  # suggested action for the orchestrator
  case "$reason" in
    ok)        [ "$sources" = yes ] && action=complete || action="retry(no-sources)" ;;
    empty)     action="retry" ;;
    error)     action="retry(backoff/other-model)" ;;
    autherror) action="HALT(fix-account)" ;;
  esac
  [ "$stream" = "truncated?" ] && [ "$reason" = ok ] && action="$action(partial?)"

  printf '%-22s %-11s %7s %7s %-10s %s\n' "$name" "$reason" "$chars" "$sources" "$stream" "$action"
done

[ "$found" -eq 1 ] || { echo "pi-swarm-collect: no *.txt result files in $DIR" >&2; exit 1; }
