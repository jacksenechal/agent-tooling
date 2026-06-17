#!/usr/bin/env bash
# Claude Code -> TTS adapter (Stop hook).
#
# Claude Code calls this on the Stop event with a JSON payload on stdin that
# contains `transcript_path` (a JSONL file). We pull the last assistant text
# message and hand it to the harness-agnostic `agent-speak` for playback.
#
# All harness-specific knowledge lives here; agent-speak stays generic.
# Fails open: any error exits 0 so it never blocks the session.

set -uo pipefail

# Master off switch without editing settings.json.
[ "${CLAUDE_TTS_DISABLE:-0}" = "1" ] && exit 0

payload="$(cat)"
transcript="$(printf '%s' "$payload" | jq -r '.transcript_path // empty' 2>/dev/null)"
[ -z "$transcript" ] || [ ! -f "$transcript" ] && exit 0

# Last assistant turn's text. Assistant content is an array of blocks; keep the
# text blocks, join them, take the final assistant message in the transcript.
text="$(jq -rs '
  [ .[]
    | select(.type == "assistant")
    | .message.content
    | if type == "array"
      then ([ .[] | select(.type == "text") | .text ] | join(" "))
      else (. // "")
      end
  ]
  | map(select(. != ""))
  | last // empty
' "$transcript" 2>/dev/null)"

# Lightweight firing log (confirms the hook runs on new sessions / debug
# silence). Disable with CLAUDE_TTS_LOG=0.
if [ "${CLAUDE_TTS_LOG:-1}" != "0" ]; then
  logdir="${XDG_STATE_HOME:-$HOME/.local/state}/agent-speak"
  mkdir -p "$logdir"
  printf '%s fired chars=%s\n' "$(date +%H:%M:%S)" "${#text}" >> "$logdir/hook.log"
fi

[ -z "$text" ] && exit 0

# Detach so playback never delays the prompt returning to the user.
printf '%s' "$text" | setsid "$HOME/.local/bin/agent-speak" >/dev/null 2>&1 &
exit 0
