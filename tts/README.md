# agent-speak — local TTS for agent harnesses

Speak agent responses aloud using a **local** TTS engine (Kokoro), with
**PipeWire audio ducking**, that works across **multiple agent harnesses**
(Claude Code, pi, hermes) from one small, harness-agnostic core.

No cloud, no API keys, no per-character billing.

## Why this design (vs. the off-the-shelf repos)

The popular `*/claude-code-tts` projects each hard-wire themselves to Claude
Code's hook system, so none help with pi or hermes; two default to cloud TTS
(OpenAI / Edge), and their audio ducking is macOS-only or absent. They're also
low-star, single-maintainer repos.

Instead we treat the **maintained, popular engine**
([`nazdridoy/kokoro-tts`](https://github.com/nazdridoy/kokoro-tts), ~1.6k★,
a plain CLI) as the TTS backend, and keep all the glue here as ~200 lines we
control. Upgrading the engine is just `uv tool upgrade kokoro-tts`. The core
(`agent-speak`) knows nothing about any harness; each harness gets a thin
adapter that pipes text into it.

## Components

| File | Role |
|------|------|
| `agent-speak` | Harness-agnostic core: stdin → strip markdown → duck other audio → Kokoro stream. One utterance at a time (new call interrupts the old). |
| `hooks/claude-stop-tts.sh` | Claude Code adapter (Stop hook): reads the transcript, extracts the last assistant text turn, pipes it to `agent-speak`. |
| `install.sh` | Installs the engine + model, symlinks the core and hook. |

Deployed locations (symlinks back to this repo, so edits here are live):
`~/.local/bin/agent-speak`, `~/.claude/hooks/tts-speak.sh`.

## Install (new machine)

```bash
./install.sh            # installs kokoro-tts, fetches the model, symlinks
# then add the Stop hook to ~/.claude/settings.json (install.sh prints it)
echo "hello from kokoro" | agent-speak   # smoke test
```

Requires `uv`, `wget`, `jq`, and a working audio device. Ducking needs
`pactl` (PipeWire-pulse or PulseAudio). Model + voices are ~336 MB.

## Configuration (env vars)

| Var | Default | Meaning |
|-----|---------|---------|
| `AGENT_SPEAK_VOICE` | `af_heart` | Kokoro voice or blend, e.g. `am_michael` or `af_sarah:60,am_adam:40`. `kokoro-tts --help-voices` lists all 54. |
| `AGENT_SPEAK_SPEED` | `1.1` | Speech rate. |
| `AGENT_SPEAK_LANG` | `en-us` | Language. |
| `AGENT_SPEAK_DUCK` | `1` | Duck other apps while speaking. |
| `AGENT_SPEAK_DUCK_LEVEL` | `0.25` | Other apps drop to this fraction of their volume. |
| `AGENT_SPEAK_MAXCHARS` | `1200` | Truncate long responses. |
| `AGENT_SPEAK_DISABLE` | `0` | `1` = no-op (launch-time kill switch, all harnesses). |
| `CLAUDE_TTS_DISABLE` | `0` | `1` = Claude Code adapter does nothing (launch-time). |
| `KOKORO_HOME` | `~/.local/share/kokoro` | Where the model + voices live. |

## Turning it on/off mid-session

Env vars are read at launch, so they can't toggle a running session. Use the
`tts` command instead — it flips a flag file that `agent-speak` checks on every
utterance, so it takes effect immediately. From a **Claude Code prompt**, run it
with the `!` bash prefix:

```
!tts off       # mute (Claude keeps working, just silent)
!tts on        # unmute
!tts toggle
!tts status
!tts say "build finished"   # speak something now, even while muted
```

Or just ask Claude ("mute TTS") and it runs `tts off`. The mute state is global
across harnesses (flag file at `~/.local/state/agent-speak/muted`).

## Audio ducking (PipeWire/PulseAudio)

Before speaking, `agent-speak` snapshots every other playback stream's volume
via `pactl`, lowers each to `DUCK_LEVEL` of its current level, then restores
the originals when speech ends (or is interrupted, or the process is killed —
handled in signal/`finally` cleanup). Because the snapshot is taken *before*
Kokoro's own stream exists, the TTS itself is never ducked. This is per-app
ducking (like CarPlay lowering music for navigation), not a master-volume
change, so your per-app levels are preserved.

## Per-harness integration

### Claude Code — automatic (Stop hook)
Wired via `~/.claude/settings.json`:
```json
"Stop": [
  { "matcher": "*",
    "hooks": [ { "type": "command", "command": "~/.claude/hooks/tts-speak.sh" } ] }
]
```

### pi — pipe its output
pi is used mostly non-interactively here, so just pipe:
```bash
pi -p "summarize this repo" | tee /dev/tty | agent-speak
```
(For interactive pi, a `~/.pi/agent/extensions/` extension could call
`agent-speak` on turn completion — pi's extension API, same place the
`sandbox` extension lives.)

### hermes — use its *native* TTS
hermes already ships TTS (`~/.hermes/config.yaml` has `tts:` backends and a
`voice.auto_tts` switch). Don't wrap it — enable its built-in local backend
(e.g. `neutts` or the bundled `piper` voice) and set `voice.auto_tts: true`.
`agent-speak` is the fallback for harnesses *without* native TTS.

## Portability across machines

Canonical scripts live in this repo (synced like the other owned skill repos),
and the deployed paths are symlinks into it, so a `git pull` updates every
machine. `install.sh` handles the per-host engine install + model download +
symlinks. Optionally fold those steps into the dotfiles `claude_skills` Ansible
role (mirroring `block-shai-hulud.sh`) for hands-off provisioning.

## Limitations / future

- **Cold-load latency:** each utterance reloads the 311 MB ONNX model (~2–3 s).
  Fine for end-of-turn narration. A persistent `kokoro` daemon would cut this
  but adds complexity; not built yet.
- CPU inference (Kokoro is 82 M params; the AMD 680M iGPU has no CUDA). Fast
  enough in practice.
