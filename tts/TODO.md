# TTS thread — state & next steps

_Last updated 2026-06-16, before a reboot._

## Where we are

Local TTS for agent responses is **working** in cold-CLI mode:

- Engine: `kokoro-tts` CLI (nazdridoy/kokoro-tts, via `uv tool`); model+voices in
  `~/.local/share/kokoro/`.
- Core: `tts/agent-speak` — harness-agnostic; strips markdown, ducks other apps
  via PipeWire/`pactl`, one utterance at a time. Resolves `kokoro-tts` by
  absolute path (don't rely on PATH — hooks get a minimal PATH).
- Claude Code: `tts/hooks/claude-stop-tts.sh` wired as a `Stop` hook in
  `~/.claude/settings.json`. Logs each firing to
  `~/.local/state/agent-speak/hook.log`.
- Runtime toggle: `tts on|off|toggle|status|say TEXT` (mute flag at
  `~/.local/state/agent-speak/muted`). From a Claude Code prompt use `!tts off`.
- Deployed paths are symlinks into this repo:
  `~/.local/bin/agent-speak`, `~/.local/bin/tts`, `~/.claude/hooks/tts-speak.sh`.

Repo `tts/` is **not committed yet** (decide whether to commit).

## The open problem

Every utterance cold-loads the model + imports → ~5-7s before audio, even for
"hi". Synthesis itself is <0.5s. Fix = a **warm persistent server**.

## Decision made

Use an existing server (don't build/maintain our own):
**remsky/Kokoro-FastAPI** (~5k★, maintained, OpenAI-compatible
`/v1/audio/speech`, streaming, CPU images, port 8880). Deploy via **Docker**,
`--restart=always`, named volume for the model. Bonus: hermes can point its
native OpenAI TTS backend at the same `http://localhost:8880/v1`.

Blocker: disk was at 98% (11-14 GB free); PyTorch image is multi-GB.

## NEXT STEPS

1. ~~**Free disk**~~ ✅ DONE (2026-06-16). Now **54 GB free** (was ~11). User
   installed pacman PostTransaction hook `/etc/pacman.d/hooks/clean_cache.hook`
   (`paccache -rk3` on every transaction) and ran a one-time cleanup. The weekly
   `paccache.timer` is therefore optional (hook already covers ongoing cleanup);
   still `disabled`. Further reclaimable if ever needed: docker (~7.6 GB),
   `uv cache prune` (~5.9 GB).
2. **Deploy the warm server:** `docker run -d --restart=always -p 8880:8880`
   remsky CPU image; verify `curl localhost:8880/v1/audio/speech`.
3. **Rewrite `agent-speak`** into a thin client: POST to localhost:8880
   (streaming) → pipe audio to player with existing ducking; **fall back to the
   cold `kokoro-tts` CLI if the server is down**.
4. **hermes:** point its OpenAI TTS backend base_url at `http://localhost:8880/v1`,
   set a kokoro voice, `voice.auto_tts: true`.
5. Decide: commit `tts/`; optionally fold install + server into the dotfiles
   `claude_skills` Ansible role for cross-machine portability.

## Verify after reboot

- Stop hook still fires: open a session, then `cat ~/.local/state/agent-speak/hook.log`.
- `tts say "hi"` still works (cold path).
