# pi-swarm troubleshooting & background

The debugging story behind this skill, so future-you can re-derive or re-fix things.

## Symptom: every `pi -p` call "hangs" regardless of model

**What's really happening:** the agent finishes and prints its answer in a few seconds, then
the **process never exits** and lingers until something kills it (a `timeout` wrapper, Ctrl-C).
It looks like slow/hanging inference, but inference was fast — exit is what's broken.

**Root cause:** an extension registered a recurring `setInterval(...)` that was never
`.unref()`'d. A ref'd timer keeps Node's event loop alive on its own, so a one-shot `pi -p`
can't exit. Interactive mode hides this (it stays alive anyway); only non-interactive `-p`
exposes it. The specific offender was **pi-webaio** (`index.ts`, session-cache cleanup timer).

**Diagnosis recipe (extension bisection):**

```bash
pi -p -ne "say hi"          # -ne disables ALL extensions → exits clean ⇒ an extension is at fault
pi -p --no-lens "say hi"    # rule out pi-lens
SB=$(readlink -f ~/.pi/agent/extensions/sandbox)
pi -p -ne -e "$SB" "say hi" # load ONLY one extension at a time to find the culprit
# then add suspects one by one with extra -e <package_dir>
```

When `pi -p "say hi"` produces output but `EXIT=124` (timeout) while `pi -p -ne "say hi"`
exits `0` fast, an extension is holding the loop. Grep the suspect for un-unref'd timers /
open handles:

```bash
grep -rn "setInterval\|\.listen(\|createServer\|new Agent" <pkg>/index.ts <pkg>/src
```

**Fix:** `.unref()` the interval (or close the handle on `session_shutdown`). Local patch lives
in `~/.pi/agent/npm/node_modules/pi-webaio/index.ts`; upstream draft PR is
`apmantza/pi-webaio#36`. **`pi update` reverts node_modules patches** — if scripted runs start
hanging again after an update, re-apply or confirm the PR merged.

## Symptom: "No API key found for opencode-go"

The key is injected by an interactive **shell alias**:
`alias pi='OPENCODE_API_KEY=$(cat ~/.config/keys/opencode.key) pi'`. Aliases are NOT expanded
in non-interactive / scripted shells, so bare `pi` in a script runs unauthenticated and falls
back to an unkeyed provider.

**Fixes (best first):**
1. Store the key in `~/.pi/agent/auth.json` so every invocation is authed regardless of shell:
   ```json
   { "opencode-go": { "type": "api_key", "key": "<key>" } }
   ```
   (Use `/login` interactively, or write the file directly. This is the portable fix.)
2. Or rely on the wrapper, which resolves `OPENCODE_API_KEY` from
   `${PI_OPENCODE_KEY_FILE:-~/.config/keys/opencode.key}`.

Check which providers are authed: keys in `~/.pi/agent/auth.json`. List usable models:
`pi --list-models`.

## Symptom: worker returns empty output (exit 0, 0 bytes, very fast)

The free opencode-go gateway intermittently returns **empty completions** under load
(especially when hammered or on tool-heavy turns). It's not the wrapper. Mitigations:

- **Validate** every worker's output (non-empty + expected marker like `SOURCES:`); re-dispatch
  failures.
- **Spread** tasks across models (glm / qwen / deepseek) to decorrelate failures.
- **Throttle** concurrency to ~5–10 simultaneous workers.
- Retry on a different model, or fall back to `openai-codex/gpt-5.4-mini` for stubborn tasks.

## Latency notes

- Container lifecycle (`docker run -d --rm … sleep infinity` + exec + cleanup) ≈ 1s. `pi`
  startup ≈ 0.7s. Neither is the bottleneck — **model inference is**.
- `defaultThinkingLevel` in `~/.pi/agent/settings.json` applies to every call. It was set to
  `high`, which makes even trivial prompts slow. The wrapper forces `--thinking low` by default;
  override per task with `--thinking`.
- Model latency varies wildly on the free gateway (a "flash" model occasionally took 80s).
  Always wrap in `timeout`.

## Container hygiene

Workers run with `--rm` and self-remove on clean exit. Each `pi -p` process derives a unique
`pi-agent-<random8>` name (keyed off PID), so parallel workers never collide. Stray
`pi-agent-*` containers in `docker ps` mean a worker was SIGKILL'd before cleanup — remove with
`docker rm -f <name>`, or `/sandbox prune` from an interactive pi session.

## Useful sandbox internals (from ~/workspace/agent-sandbox)

- Flags: `--sandbox-network` (outbound + `browser` tool), `--sandbox-mount-cwd` (rw `/workspace`),
  `--sandbox-mount-skills` (ro), `--sandbox-mount-ssh`, `--sandbox-memory`, `--sandbox-cpus`,
  `--sandbox-name`, `--no-sandbox`.
- The `browser` tool (registered only when network is on) executes a Playwright Node script
  inside the container — an alternative to pi-webaio for direct page interaction.
- Extension debug log: `/tmp/agent-sandbox.log`.
