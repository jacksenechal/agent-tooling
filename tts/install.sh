#!/usr/bin/env bash
# Install local TTS (Kokoro) + the agent-speak wrapper on a new machine.
# Idempotent. Safe to re-run. Linux/PipeWire assumed for ducking; speech works
# anywhere kokoro-tts can open an audio device.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KOKORO_HOME="${KOKORO_HOME:-$HOME/.local/share/kokoro}"
BIN_DIR="$HOME/.local/bin"
HOOK_DIR="$HOME/.claude/hooks"

echo "==> Installing kokoro-tts CLI (via uv tool)"
if ! command -v kokoro-tts >/dev/null 2>&1; then
  command -v uv >/dev/null 2>&1 || { echo "ERROR: install 'uv' first"; exit 1; }
  # kokoro-tts is a pure-Python CLI from PyPI (nazdridoy/kokoro-tts, ~1.6k stars,
  # well past any release-age window). No npm lifecycle-script vector here.
  uv tool install kokoro-tts
else
  echo "    kokoro-tts already on PATH; skipping."
fi

echo "==> Fetching Kokoro model + voices into $KOKORO_HOME"
mkdir -p "$KOKORO_HOME"
base="https://github.com/nazdridoy/kokoro-tts/releases/download/v1.0.0"
[ -f "$KOKORO_HOME/kokoro-v1.0.onnx" ] || wget -q --show-progress -O "$KOKORO_HOME/kokoro-v1.0.onnx" "$base/kokoro-v1.0.onnx"
[ -f "$KOKORO_HOME/voices-v1.0.bin" ]  || wget -q --show-progress -O "$KOKORO_HOME/voices-v1.0.bin"  "$base/voices-v1.0.bin"

echo "==> Symlinking agent-speak + tts -> $BIN_DIR"
mkdir -p "$BIN_DIR"
ln -sf "$REPO_DIR/agent-speak" "$BIN_DIR/agent-speak"
ln -sf "$REPO_DIR/tts" "$BIN_DIR/tts"

echo "==> Symlinking Claude Code Stop hook -> $HOOK_DIR"
mkdir -p "$HOOK_DIR"
ln -sf "$REPO_DIR/hooks/claude-stop-tts.sh" "$HOOK_DIR/tts-speak.sh"

cat <<'EOF'

==> Done. Final manual step (Claude Code only):
    Add this to the "hooks" object in ~/.claude/settings.json:

      "Stop": [
        { "matcher": "*",
          "hooks": [ { "type": "command", "command": "~/.claude/hooks/tts-speak.sh" } ] }
      ]

    Toggle off anytime:  export CLAUDE_TTS_DISABLE=1   (Claude Code adapter)
                         export AGENT_SPEAK_DISABLE=1  (all harnesses)
    Test:  echo "hello from kokoro" | agent-speak
EOF
