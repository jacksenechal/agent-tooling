# pi-swarm troubleshooting & background

The debugging story behind this skill, so future-you can re-derive or re-fix things.

## Architecture: why the whole worker runs *inside* the container

Each worker is a `docker run --rm agent-sandbox:latest pi -p …` — the entire pi agent runs in
the container, not just its tools.

**Why, and the bug that forced it:** pi's own `--sandbox` extension (`pi-docker-sandbox`, in
`~/workspace/agent-sandbox`) keeps pi on the **host** and only proxies the built-in bash / read /
write / edit tools into the container via `docker exec`. But pi-webaio's `browser` and
search/fetch tools are an **in-process extension** — they call `import("playwright")` and
`chromium.launch({ channel: "chrome" })` directly in the host pi process. So with the
tool-sandbox approach the worker's browser ran **on the host against the host's Chrome**,
entirely outside the sandbox. pi-webaio exposes no remote-CDP knob to redirect it. The only way
to actually sandbox the browser is to run the whole pi process in the container, which is what
the image + wrapper now do.

**What the image bakes in** (see `~/workspace/agent-sandbox/Dockerfile`): pi (pinned to the host
version via the `PI_VERSION` build arg), the research extensions (`pi-webaio`, `pi-lens`,
`pi-textbrowser`, `pi-smart-fetch`) installed with `pi install`, and a Playwright Chromium
installed with the *same* Playwright pi-webaio bundles. pi-webaio still tries `channel:"chrome"`
first (no system Chrome in the image, so it fails fast) then falls back to that bundled Chromium.
The `pi-docker-sandbox` extension is **not** installed in the image — the swarm bypasses it, so
there's no docker-in-docker.

Quick proof the browser is in-container: run a browser task and watch the host —
`pgrep -af greedysearch-chrome-profile` count should not change, and the worker's `<-o>.jsonl`
stream should show `browser_navigate` tool calls.

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

**Fix:** `.unref()` the interval (or close the handle on `session_shutdown`). This landed
upstream (`apmantza/pi-webaio#36`) and ships in the pi-webaio version baked into the image, so
no local patch is needed anymore. It also matters less now: each worker is `docker run --rm`, so
even a lingering handle dies with the container and a true hang just trips the stall watchdog.
If you bump the image's pi-webaio and scripted runs start hanging again, re-run the bisection
above against the new version inside the image (`docker run --rm agent-sandbox:latest pi -p …`).

## Symptom: "No API key found for opencode-go"

The key is injected by an interactive **shell alias**:
`alias pi='OPENCODE_API_KEY=$(cat ~/.config/keys/opencode.key) pi'`. Aliases are NOT expanded
in non-interactive / scripted shells, so bare `pi` in a script runs unauthenticated and falls
back to an unkeyed provider.

**Fixes (best first):**
1. Rely on the wrapper: it resolves `OPENCODE_API_KEY` from
   `${PI_OPENCODE_KEY_FILE:-~/.config/keys/opencode.key}` and forwards it into the container with
   `docker run -e OPENCODE_API_KEY`. This is the path the swarm uses — the in-container pi reads
   the key from its environment.
2. For interactive host pi (not the swarm), store the key in `~/.pi/agent/auth.json` so every
   invocation is authed regardless of shell:
   ```json
   { "opencode-go": { "type": "api_key", "key": "<key>" } }
   ```

Note: the image does **not** bake the key (it would be a layer secret). Workers get it only at
`docker run` time via `-e`. If a worker reports no key, check that the host resolved one
(`pi-research.sh --check` prints `opencode key: resolved`). List usable models: `pi --list-models`.

## Symptom: worker returns empty output

There are a few distinct causes, distinguishable from the `reason=` field on the wrapper's
stderr `done` line:

1. **`exit=124 reason=stall` — the worker hung.** The stall watchdog killed it after `-s`
   seconds (default 120) with no new stream output. Usually a stuck tool call or a dead gateway
   turn. Re-dispatch; raise `-s` only if the task legitimately goes silent for long stretches
   (one very slow page load). Any text produced *before* the kill is recovered into the `-o`
   file, with the full tool history in the `<-o>.jsonl` stream — inspect it to see how far it got.
2. **`exit=124 reason=hardcap` — hit the `-t` ceiling.** Rare: the worker streamed continuously
   past the absolute wall-clock backstop (default 1800s). Either it's genuinely huge (raise `-t`)
   or it's looping (decompose the task). Partial answer is recovered the same way.
3. **`exit=0 reason=empty` (answer_chars=0) — a true gateway empty-completion.** The free
   opencode-go gateway intermittently returns nothing under load (especially tool-heavy turns).
   It's not the wrapper. Just retry.

Historically both looked identical (a 0-byte file) because the old text-mode wrapper only
emitted the answer at process exit, so a timeout produced an empty file with no clue why. The
`--mode json` stream fixed that.

Mitigations (both causes):

- **Validate** every worker's output (non-empty + expected marker like `SOURCES:`); re-dispatch
  failures, keyed on the `reason=` distinction above.
- **Spread** tasks across models (glm / qwen / deepseek) to decorrelate failures.
- **Throttle** concurrency to ~5–10 simultaneous workers.
- Retry on a different model, or fall back to `openai-codex/gpt-5.4-mini` for stubborn tasks.

## Latency notes

- Each worker is a cold `docker run` of the full pi agent: container create + pi startup +
  extension load ≈ a few seconds before the first model token. A real browser task in the test
  finished in ~25s end to end. Still, **model inference dominates**, not container overhead.
- `defaultThinkingLevel` applies to every call. The wrapper forces `--thinking low` by default;
  override per task with `--thinking`.
- Model latency varies wildly on the free gateway (a "flash" model occasionally took 80s). The
  wrapper's stall watchdog tolerates this (it only kills on *no* output, not on slowness), with
  the `-t` hard cap as a final backstop.

## Container hygiene

Each worker is its own `docker run --rm` named `-n NAME` (or an auto `pi-research-<pid>-<rand>`),
so parallel workers never collide. The wrapper force-removes the container on every exit path
(including stall/hardcap kills), so it shouldn't leak. Stray `pi-research-*` containers in
`docker ps -a` mean the wrapper process itself was killed mid-run — `docker rm -f <name>`.

## The pi-docker-sandbox extension (host pi, NOT the swarm)

`~/workspace/agent-sandbox` is a pi extension that gives **interactive host pi** a tool-sandbox:
it runs one `agent-sandbox` container and proxies bash/read/write/edit into it via `docker exec`,
with flags `--sandbox-network`, `--sandbox-mount-cwd`, `--sandbox-mount-skills`,
`--sandbox-mount-ssh`, `--sandbox-memory`, `--sandbox-cpus`, `--sandbox-name`, `--no-sandbox`.
The swarm does **not** use this path (it would leave the browser on the host — see the
architecture note up top). It shares the same Docker **image** but the wrapper drives
`docker run` itself and does not load this extension. Extension debug log: `/tmp/agent-sandbox.log`.
