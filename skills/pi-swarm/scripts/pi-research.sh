#!/usr/bin/env bash
# pi-research.sh — run ONE pi research worker non-interactively, robustly.
#
# Designed to be fanned out by an orchestrator (Claude) into many parallel
# background invocations. Each call runs in its own Docker sandbox container
# (auto-named, so parallel calls never collide), does its task, prints its
# answer, and exits cleanly.
#
# Why this wrapper exists (hard-won lessons — see SKILL.md "Gotchas"):
#   * pi must be authenticated. The user's interactive shell aliases
#     OPENCODE_API_KEY in; that alias does NOT apply to scripted/non-login
#     shells, so we resolve the key here explicitly.
#   * `pi -p` reads stdin; with a non-TTY stdin that never EOFs it can block.
#     We always redirect stdin from /dev/null.
#   * A `timeout` wrapper is a safety net so a misbehaving worker can never
#     hang the swarm forever (returns partial output instead).
#   * Output is captured as `--mode json` NDJSON events to a `.jsonl` stream file, then the
#     final answer text is extracted from it. This makes a long run observable (`tail -f` the
#     stream) and means a timed-out worker still yields its partial answer instead of an empty
#     file. (Plain text mode only emits at process exit, so any early kill = empty output —
#     the historical "empty on timeout" failure.)
#
# Usage:
#   pi-research.sh [options] "PROMPT"
#   pi-research.sh [options] --prompt-file FILE
#
# Options:
#   -m, --model MODEL      provider/model (default: opencode-go/glm-5.1)
#   -t, --timeout SECS     hard wall-clock cap (default: 300; free-gateway first-token
#                          latency alone is ~7-10s, so tool-heavy research needs headroom)
#       --thinking LEVEL   off|minimal|low|medium|high|xhigh (default: low)
#       --network on|off   outbound net + browser/search tools (default: on)
#       --mount-cwd DIR    mount DIR rw at /workspace (default: none)
#   -o, --out FILE         write agent output here (default: stdout)
#   -n, --name NAME        explicit container/session name (traceability)
#       --check            run preflight checks and exit
#       --models           print the suggested cheap-model menu and exit
#   -h, --help             show this help
#
# Env:
#   OPENCODE_API_KEY        if set, used as-is
#   PI_OPENCODE_KEY_FILE    path to key file (default: ~/.config/keys/opencode.key)
set -uo pipefail

MODEL="opencode-go/glm-5.1"
TIMEOUT=300
THINKING="low"
NETWORK="on"
MOUNT_CWD=""
OUT=""
NAME=""
PROMPT=""
PROMPT_FILE=""
KEY_FILE="${PI_OPENCODE_KEY_FILE:-$HOME/.config/keys/opencode.key}"

die() { echo "pi-research: $*" >&2; exit 2; }

print_models() {
  cat <<'EOF'
Suggested cheap OSS models on opencode-go (verify live with: pi --list-models):
  opencode-go/glm-5.1          fast, solid general research (default)
  opencode-go/qwen3.6-plus     strong reasoning, vision-capable
  opencode-go/kimi-k2.6        long-context, vision-capable
  opencode-go/deepseek-v4-flash  cheapest/fastest, 1M ctx, no vision
  opencode-go/minimax-m2.7     long max-output
Capable fallback (ChatGPT Plus OAuth, costs subscription quota):
  openai-codex/gpt-5.4-mini
Tip: keep --thinking low/off for fan-out speed; raise to medium for hard synthesis.
EOF
}

# ── arg parse ──────────────────────────────────────────────────────────────
while [ $# -gt 0 ]; do
  case "$1" in
    -m|--model)       MODEL="$2"; shift 2;;
    -t|--timeout)     TIMEOUT="$2"; shift 2;;
    --thinking)       THINKING="$2"; shift 2;;
    --network)        NETWORK="$2"; shift 2;;
    --mount-cwd)      MOUNT_CWD="$2"; shift 2;;
    -o|--out)         OUT="$2"; shift 2;;
    -n|--name)        NAME="$2"; shift 2;;
    --prompt-file)    PROMPT_FILE="$2"; shift 2;;
    --check)          MODE_CHECK=1; shift;;
    --models)         print_models; exit 0;;
    -h|--help)        sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    --)               shift; PROMPT="${PROMPT}$*"; break;;
    -*)               die "unknown option: $1";;
    *)                PROMPT="${PROMPT}${PROMPT:+ }$1"; shift;;
  esac
done

# ── key resolution ─────────────────────────────────────────────────────────
# Populate OPENCODE_API_KEY from the key file if unset (harmless for other
# providers; required for opencode / opencode-go models unless stored in
# ~/.pi/agent/auth.json).
if [ -z "${OPENCODE_API_KEY:-}" ] && [ -f "$KEY_FILE" ]; then
  OPENCODE_API_KEY="$(cat "$KEY_FILE")"
  export OPENCODE_API_KEY
fi

# ── preflight checks ───────────────────────────────────────────────────────
if [ "${MODE_CHECK:-0}" = "1" ]; then
  ok=0
  command -v pi >/dev/null 2>&1     && echo "ok   pi: $(pi --version 2>&1 | head -1)" || { echo "FAIL pi not on PATH"; ok=1; }
  command -v docker >/dev/null 2>&1 && echo "ok   docker: $(docker --version 2>/dev/null)" || { echo "FAIL docker not on PATH"; ok=1; }
  docker image inspect agent-sandbox:latest >/dev/null 2>&1 \
    && echo "ok   sandbox image: agent-sandbox:latest present" \
    || { echo "FAIL agent-sandbox:latest missing (build it in ~/workspace/agent-sandbox)"; ok=1; }
  if [ -n "${OPENCODE_API_KEY:-}" ]; then echo "ok   opencode key: resolved (${#OPENCODE_API_KEY} chars)"; else echo "warn opencode key: not resolved (fine if using a non-opencode authed provider)"; fi
  # pi-webaio unref patch: scripted pi must exit on its own.
  echo "ok   note: verify 'pi -p' exits (pi-webaio interval must be .unref()'d)"
  exit $ok
fi

[ -n "$PROMPT_FILE" ] && { [ -f "$PROMPT_FILE" ] || die "prompt file not found: $PROMPT_FILE"; PROMPT="$(cat "$PROMPT_FILE")"; }
[ -n "$PROMPT" ] || die "no prompt given (pass a string, --prompt-file FILE, or --check/--models)"

# ── build pi command ───────────────────────────────────────────────────────
# --mode json streams newline-delimited JSON events (session / turn / message_update with
# text_delta + thinking_delta / tool_use / agent_end) in real time. We capture that stream to
# a .jsonl file and extract the final answer from it, so: (a) a run is observable live via
# `tail -f`, and (b) a worker killed by the timeout still leaves its partial answer + tool
# history on disk instead of an empty file.
args=( -p --no-session --mode json --model "$MODEL" --thinking "$THINKING" )
[ "$NETWORK" = "on" ] && args+=( --sandbox-network )
[ -n "$MOUNT_CWD" ]   && args+=( --sandbox-mount-cwd ) && cd "$MOUNT_CWD"
[ -n "$NAME" ]        && args+=( --sandbox-name "$NAME" )

# Raw NDJSON event stream (always written); errors go to a sibling .err log.
if [ -n "$OUT" ]; then STREAM="${OUT}.jsonl"; else STREAM="$(mktemp -t pi-research.XXXXXX.jsonl)"; fi
ERRLOG="${STREAM%.jsonl}.err"
echo "pi-research: streaming events → $STREAM  (tail -f to watch live)" >&2

start=$(date +%s)
timeout "$TIMEOUT" pi "${args[@]}" "$PROMPT" </dev/null >"$STREAM" 2>"$ERRLOG"
ec=$?
end=$(date +%s)

# Extract the final (or partial, if killed mid-stream) answer text from the NDJSON.
ANSWER="$(python3 - "$STREAM" <<'PY'
import json, sys
deltas, fallback = [], None
def texts(content):
    return "".join(c.get("text", "") for c in (content or []) if c.get("type") == "text")
with open(sys.argv[1], "r", errors="replace") as fh:
    for line in fh:
        line = line.strip()
        if not line:
            continue
        try:
            ev = json.loads(line)
        except Exception:
            continue  # tolerate a truncated final line from a hard kill
        t = ev.get("type")
        if t == "message_update":
            ame = ev.get("assistantMessageEvent") or {}
            if ame.get("type") == "text_delta":
                deltas.append(ame.get("delta", ""))
        elif t == "message_end":
            m = ev.get("message") or {}
            if m.get("role") == "assistant":
                fallback = texts(m.get("content")) or fallback
        elif t == "agent_end":
            for m in reversed(ev.get("messages") or []):
                if m.get("role") == "assistant":
                    fallback = texts(m.get("content")) or fallback
                    break
# Prefer streamed deltas (works for partial too); fall back to whole-message text if a
# provider returned no deltas.
sys.stdout.write(("".join(deltas).strip()) or ((fallback or "").strip()))
PY
)"

# Write the extracted answer (empty stays a true 0-byte file so callers' empty-check still works).
if [ -n "$OUT" ]; then
  if [ -n "$ANSWER" ]; then printf '%s\n' "$ANSWER" >"$OUT"; else : >"$OUT"; fi
else
  [ -n "$ANSWER" ] && printf '%s\n' "$ANSWER"
fi

# 124 = timed out: any partial answer was still recovered from the stream above.
if [ $ec -eq 124 ]; then
  echo "pi-research: WORKER TIMED OUT after ${TIMEOUT}s (model=$MODEL) — recovered ${#ANSWER} chars partial${OUT:+ in $OUT}" >&2
fi
# Distinguish a true empty completion (no text at all) from a timeout, and surface hidden errors.
if [ -z "$ANSWER" ]; then
  echo "pi-research: WARNING empty answer (gateway empty-completion or error) — stream: $STREAM" >&2
  [ -s "$ERRLOG" ] && { echo "pi-research: stderr tail:" >&2; tail -n 3 "$ERRLOG" >&2; }
fi
echo "pi-research: done model=$MODEL exit=$ec elapsed=$((end-start))s answer_chars=${#ANSWER}${NAME:+ name=$NAME}${OUT:+ out=$OUT} stream=$STREAM" >&2
exit $ec
