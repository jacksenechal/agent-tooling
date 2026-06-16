#!/usr/bin/env bash
# pi-research.sh — run ONE pi research worker non-interactively, robustly.
#
# Designed to be fanned out by an orchestrator (Claude) into many parallel
# background invocations. Each call runs an ENTIRE pi worker inside its own
# throwaway Docker container (`docker run --rm` of agent-sandbox:latest), does
# its task, prints its answer, and the container is removed on exit.
#
# Why run the whole worker in the container (not pi's built-in tool-sandbox):
#   pi's `--sandbox` extension keeps pi on the HOST and only proxies bash/read/
#   write/edit into the container — pi-webaio's `browser` tool is an in-process
#   extension, so it launched Chromium on the HOST against the host's Chrome,
#   completely outside the sandbox. Running pi itself inside the container makes
#   the browser (and everything else) actually sandboxed. The image bakes in pi,
#   pi-webaio, and a matching Playwright Chromium for exactly this.
#
# Hard-won robustness baked into this wrapper (see SKILL.md "Gotchas"):
#   * pi inside the container authenticates via OPENCODE_API_KEY. The user's
#     interactive shell aliases that key in; the alias does NOT apply to scripted
#     shells, so we resolve it here and forward it with `docker run -e`.
#   * stdin is redirected from /dev/null so a non-TTY pi never blocks on input.
#   * Two layers guard runtime instead of one blunt wall-clock kill:
#       - a STALL watchdog that kills only when the worker stops producing stream
#         output (a genuine hang) — "if it's making progress, don't kill it";
#       - a larger `timeout` ceiling as an absolute backstop.
#   * Output is captured as `--mode json` NDJSON events to a `.jsonl` stream
#     file, then the final answer text is extracted from it. A long run is
#     observable (`tail -f` the stream) and a timed-out worker still yields its
#     partial answer instead of an empty file.
#
# NETWORK NOTE: because the whole worker runs in the container, the model-gateway
# call also originates inside it — so `--network on` (the default) is required
# for any remote model (opencode-go). `--network off` is true full isolation (no
# model gateway either) and only makes sense with a model that needs no egress.
#
# Usage:
#   pi-research.sh [options] "PROMPT"
#   pi-research.sh [options] --prompt-file FILE
#
# Options:
#   -m, --model MODEL      provider/model (default: opencode-go/glm-5.1)
#   -t, --timeout SECS     hard wall-clock ceiling, an absolute backstop (default: 1800).
#                          Rarely the thing that fires — the stall watchdog usually ends a
#                          stuck worker first. Raise only for genuinely long single tasks.
#   -s, --stall-timeout S  inactivity watchdog: kill the worker if it emits NO new stream
#                          output for S seconds (default: 120; 0 disables). This is the real
#                          control. A worker making steady progress is never killed; a hung
#                          one dies ~S+poll seconds after it goes quiet instead of waiting -t.
#                          Size S above the slowest single tool step (a heavy page load can be
#                          30-60s of silence); 120 covers normal browser/search latency.
#       --thinking LEVEL   off|minimal|low|medium|high|xhigh (default: low)
#       --network on|off   container egress (default: on). on = bridge (model gateway + web);
#                          off = --network none, full isolation (no model gateway either).
#       --mount-cwd DIR    bind-mount DIR rw at /workspace (default: none)
#   -o, --out FILE         write agent output here (default: stdout)
#   -n, --name NAME        explicit container name (traceability; must be unique)
#       --image IMAGE      sandbox image to run (default: agent-sandbox:latest)
#       --check            run preflight checks and exit
#       --models           print the suggested cheap-model menu and exit
#   -h, --help             show this help
#
# Env:
#   OPENCODE_API_KEY        if set, used as-is
#   PI_OPENCODE_KEY_FILE    path to key file (default: ~/.config/keys/opencode.key)
#   PI_SANDBOX_IMAGE        default sandbox image (overridden by --image)
set -uo pipefail

MODEL="opencode-go/glm-5.1"
TIMEOUT=1800
STALL=120
POLL=5
THINKING="low"
NETWORK="on"
MOUNT_CWD=""
OUT=""
NAME=""
PROMPT=""
PROMPT_FILE=""
IMAGE="${PI_SANDBOX_IMAGE:-agent-sandbox:latest}"
MEMORY="4g"
CPUS="2"
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
    -s|--stall-timeout) STALL="$2"; shift 2;;
    --thinking)       THINKING="$2"; shift 2;;
    --network)        NETWORK="$2"; shift 2;;
    --mount-cwd)      MOUNT_CWD="$2"; shift 2;;
    -o|--out)         OUT="$2"; shift 2;;
    -n|--name)        NAME="$2"; shift 2;;
    --image)          IMAGE="$2"; shift 2;;
    --prompt-file)    PROMPT_FILE="$2"; shift 2;;
    --check)          MODE_CHECK=1; shift;;
    --models)         print_models; exit 0;;
    -h|--help)        sed -n '2,67p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    --)               shift; PROMPT="${PROMPT}$*"; break;;
    -*)               die "unknown option: $1";;
    *)                PROMPT="${PROMPT}${PROMPT:+ }$1"; shift;;
  esac
done

# ── key resolution ─────────────────────────────────────────────────────────
# Populate OPENCODE_API_KEY from the key file if unset; it is forwarded into the
# container with `docker run -e OPENCODE_API_KEY` (value not placed in argv).
if [ -z "${OPENCODE_API_KEY:-}" ] && [ -f "$KEY_FILE" ]; then
  OPENCODE_API_KEY="$(cat "$KEY_FILE")"
  export OPENCODE_API_KEY
fi

# ── preflight checks ───────────────────────────────────────────────────────
if [ "${MODE_CHECK:-0}" = "1" ]; then
  ok=0
  command -v docker >/dev/null 2>&1 && echo "ok   docker: $(docker --version 2>/dev/null)" || { echo "FAIL docker not on PATH"; ok=1; }
  if docker image inspect "$IMAGE" >/dev/null 2>&1; then
    echo "ok   sandbox image: $IMAGE present"
    if piv=$(docker run --rm --entrypoint pi "$IMAGE" --version 2>&1 | head -1); then
      echo "ok   pi in image: $piv"
    else
      echo "FAIL pi not runnable inside $IMAGE (rebuild it from ~/workspace/agent-sandbox)"; ok=1
    fi
  else
    echo "FAIL $IMAGE missing (build it: cd ~/workspace/agent-sandbox && docker build -t $IMAGE .)"; ok=1
  fi
  if [ -n "${OPENCODE_API_KEY:-}" ]; then echo "ok   opencode key: resolved (${#OPENCODE_API_KEY} chars)"; else echo "warn opencode key: not resolved (fine if using a non-opencode authed provider)"; fi
  exit $ok
fi

[ -n "$PROMPT_FILE" ] && { [ -f "$PROMPT_FILE" ] || die "prompt file not found: $PROMPT_FILE"; PROMPT="$(cat "$PROMPT_FILE")"; }
[ -n "$PROMPT" ] || die "no prompt given (pass a string, --prompt-file FILE, or --check/--models)"

# ── build docker run command ───────────────────────────────────────────────
# The whole pi worker runs inside the container. --mode json streams NDJSON
# events (session / turn / message_update with text_delta + thinking_delta /
# tool_use / agent_end) in real time to the container's stdout, which docker
# forwards to our capture file — so a run is observable live (`tail -f`) and a
# worker killed by a limit still leaves its partial answer + tool history.
CNAME="${NAME:-pi-research-$$-${RANDOM}}"
docker_args=( run --rm --name "$CNAME" --memory="$MEMORY" --cpus="$CPUS" -e OPENCODE_API_KEY )
if [ "$NETWORK" = "on" ]; then
  docker_args+=( --network bridge --add-host=host.docker.internal:host-gateway )
else
  docker_args+=( --network none )
fi
[ -n "$MOUNT_CWD" ] && docker_args+=( -v "$MOUNT_CWD":/workspace )
docker_args+=( "$IMAGE" pi -p --no-session --mode json --model "$MODEL" --thinking "$THINKING" "$PROMPT" )

# Raw NDJSON event stream (always written); errors go to a sibling .err log.
if [ -n "$OUT" ]; then STREAM="${OUT}.jsonl"; else STREAM="$(mktemp -t pi-research.XXXXXX.jsonl)"; fi
ERRLOG="${STREAM%.jsonl}.err"
echo "pi-research: container=$CNAME streaming events → $STREAM  (tail -f to watch live)" >&2

# Ensure the container is gone even if a hard kill skips docker's --rm cleanup.
cleanup_container() { docker rm -f "$CNAME" >/dev/null 2>&1 || true; }

# ── run with a stall-aware watchdog ────────────────────────────────────────
# Two independent limits guard the worker:
#   * STALL   — inactivity watchdog. Poll the NDJSON stream's byte size; if it
#               stops growing for STALL seconds the worker is genuinely hung (not
#               just slow), so SIGTERM `docker run`, which stops + removes the
#               --rm container. A worker still emitting tokens is never killed.
#   * TIMEOUT — absolute wall-clock ceiling enforced by `timeout`, an ultimate
#               backstop; rarely the limit that actually fires.
start=$(date +%s)
: >"$STREAM"   # ensure the stream exists before the watchdog first stats it
timeout --foreground -k 5 "$TIMEOUT" docker "${docker_args[@]}" </dev/null >"$STREAM" 2>"$ERRLOG" &
wd_pid=$!
STALLED=0
if [ "${STALL:-0}" -gt 0 ]; then
  last_size=-1
  last_change=$(date +%s)
  while kill -0 "$wd_pid" 2>/dev/null; do
    sleep "$POLL"
    cur_size=$(stat -c %s "$STREAM" 2>/dev/null || echo 0)
    now=$(date +%s)
    if [ "$cur_size" -ne "$last_size" ]; then
      last_size=$cur_size; last_change=$now
    elif [ $((now - last_change)) -ge "$STALL" ]; then
      STALLED=1
      kill -TERM "$wd_pid" 2>/dev/null
      # give docker a few seconds to stop + remove the container before hard kill
      for _ in 1 2 3 4 5; do kill -0 "$wd_pid" 2>/dev/null || break; sleep 1; done
      kill -KILL "$wd_pid" 2>/dev/null
      cleanup_container
      break
    fi
  done
fi
wait "$wd_pid"
ec=$?
end=$(date +%s)
# A stall kill surfaces to callers as a timeout (124); the partial answer is recovered below.
[ "$STALLED" -eq 1 ] && ec=124
# Belt-and-suspenders: never leak the named container, however we exited.
cleanup_container

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

# Classify the outcome for the caller (Claude reads `reason=` to decide retry strategy).
# 124 = killed by a limit; any partial answer was still recovered from the stream above.
reason=ok
if [ $ec -eq 124 ]; then
  if [ "$STALLED" -eq 1 ]; then
    reason=stall
    echo "pi-research: WORKER STALLED — no stream output for ${STALL}s (model=$MODEL) — recovered ${#ANSWER} chars partial${OUT:+ in $OUT}" >&2
  else
    reason=hardcap
    echo "pi-research: WORKER HIT HARD CAP after ${TIMEOUT}s (model=$MODEL) — recovered ${#ANSWER} chars partial${OUT:+ in $OUT}" >&2
  fi
fi
# Distinguish a true empty completion (no text at all) from a limit kill, and surface hidden errors.
if [ -z "$ANSWER" ]; then
  [ "$reason" = ok ] && reason=empty
  echo "pi-research: WARNING empty answer (gateway empty-completion or error) — stream: $STREAM" >&2
  [ -s "$ERRLOG" ] && { echo "pi-research: stderr tail:" >&2; tail -n 3 "$ERRLOG" >&2; }
fi
echo "pi-research: done model=$MODEL exit=$ec reason=$reason elapsed=$((end-start))s answer_chars=${#ANSWER}${NAME:+ name=$NAME}${OUT:+ out=$OUT} stream=$STREAM" >&2
exit $ec
