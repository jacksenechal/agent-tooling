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
#
# Usage:
#   pi-research.sh [options] "PROMPT"
#   pi-research.sh [options] --prompt-file FILE
#
# Options:
#   -m, --model MODEL      provider/model (default: opencode-go/glm-5.1)
#   -t, --timeout SECS     hard wall-clock cap (default: 240)
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
TIMEOUT=240
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
args=( -p --no-session --model "$MODEL" --thinking "$THINKING" )
[ "$NETWORK" = "on" ] && args+=( --sandbox-network )
[ -n "$MOUNT_CWD" ]   && args+=( --sandbox-mount-cwd ) && cd "$MOUNT_CWD"
[ -n "$NAME" ]        && args+=( --sandbox-name "$NAME" )

start=$(date +%s)
if [ -n "$OUT" ]; then
  timeout "$TIMEOUT" pi "${args[@]}" "$PROMPT" </dev/null >"$OUT" 2>&1
  ec=$?
else
  timeout "$TIMEOUT" pi "${args[@]}" "$PROMPT" </dev/null 2>&1
  ec=$?
fi
end=$(date +%s)

# 124 = timed out (output still captured up to that point).
if [ $ec -eq 124 ]; then
  echo "pi-research: WORKER TIMED OUT after ${TIMEOUT}s (model=$MODEL)${OUT:+ — partial output in $OUT}" >&2
fi
echo "pi-research: done model=$MODEL exit=$ec elapsed=$((end-start))s${NAME:+ name=$NAME}${OUT:+ out=$OUT}" >&2
exit $ec
