---
name: pi-swarm
description: >
  Delegate research to a swarm of cheap, sandboxed `pi` agents while Claude acts as the
  orchestrator. Each worker is a non-interactive `pi -p` run in its own isolated Docker
  container (Chromium + Playwright + web search/fetch), driven by a cheap open-source model
  (glm, qwen, kimi, deepseek via opencode-go). Claude fans tasks out in parallel, collects
  the results, and synthesizes them.

  Use when the user wants to parallelize research, "spin up agents", "delegate to pi",
  run many lookups/investigations at once, or do broad fan-out web research cheaply without
  burning Claude's own context. Trigger on: "pi swarm", "research swarm", "delegate research",
  "delegate to pi", "spin up research agents", "parallel research", "fan out", "use the pi
  agent", "have pi research", "swarm of agents", "send this to pi", "research these in
  parallel", "cheap model research". Also trigger when the user has a batch of similar
  research items (companies, jobs, URLs, questions) and wants them processed concurrently.
---

# pi-swarm: orchestrate a swarm of cheap sandboxed research agents

**Claude is the brain; `pi` workers are the hands.** You decompose the goal into independent
tasks, fan them out as parallel `pi -p` invocations (each in its own throwaway Docker sandbox
with web access), collect their structured outputs, verify, and synthesize. Workers run cheap
open-source models, so you can run many at once for the cost of one Claude turn.

## When to use / not use

**Use it** for breadth: N similar lookups (companies, jobs, repos, URLs, questions), broad
web reconnaissance, or anything where independent subtasks can run concurrently and you only
need their conclusions back.

**Don't use it** for a single quick lookup (just do it yourself), for tasks needing your full
reasoning/context, or for work requiring shared mutable state across workers (they're isolated
by design — see "cwd mounts" gotcha).

## Preflight (run once per session)

```bash
skills/pi-swarm/scripts/pi-research.sh --check
```

This verifies `docker`, the `agent-sandbox:latest` image, that `pi` is runnable *inside* it,
and that an opencode key is resolvable. All must be green. If the image is missing or stale,
rebuild it from `~/workspace/agent-sandbox` (`docker build -t agent-sandbox:latest .`).

**The whole worker runs inside the container.** Each worker is a `docker run --rm` of
`agent-sandbox:latest` whose command *is* `pi -p …`. The image bakes in pi, the research
extensions (pi-webaio etc.), and a matching Playwright Chromium — so pi-webaio's `browser` tool
launches headless Chromium *in the container*, not on the host. (This is deliberate: pi's own
`--sandbox` only proxies bash/read/write into the container while pi stays on the host, so the
in-process `browser` tool used to drive the **host's** Chrome. Running the whole worker inside
fixes that.) Don't call bare `pi` for workers — always go through the wrapper.

**Auth.** `pi`'s provider key is normally injected by a shell *alias*
(`OPENCODE_API_KEY=$(cat ~/.config/keys/opencode.key) pi`) that does NOT apply in scripted
shells. The wrapper resolves the key explicitly and forwards it into the container with
`docker run -e OPENCODE_API_KEY`, so just go through the wrapper. Because the model call now
originates *inside* the container, a remote model (opencode-go) needs `--network on` (default).

## The worker contract

One worker = one `pi -p` run via the wrapper. The wrapper bakes in every hard-won robustness
fix (key resolution, `</dev/null` stdin, stall watchdog + hard-cap safety net, sandbox flags):

```bash
skills/pi-swarm/scripts/pi-research.sh \
  -m opencode-go/glm-5.1 \   # model (see menu below)
  -s 120 \                   # stall watchdog: kill only after 120s of NO new output (default 120)
  -t 1800 \                  # hard wall-clock ceiling, absolute backstop (default 1800)
  --network on \             # container egress: model gateway + search/fetch + browser (default)
  -o results/task-07.txt \   # capture the agent's final answer here
  -n swarm-task-07 \         # container/session name (traceability)
  "PROMPT"                   # or: --prompt-file path/to/prompt.md
```

**Runtime is guarded by a stall watchdog, not a blunt clock.** The wrapper polls the worker's
NDJSON stream and only kills it after `-s` seconds with *no new output* (a genuine hang). A
worker that keeps thinking, calling tools, and emitting tokens is never killed for being slow —
so long, healthy research runs finish instead of getting chopped at a fixed cap. The `-t`
ceiling is just an ultimate backstop for a worker that streams junk forever; it rarely fires.
Raise `-s` (not `-t`) if a task legitimately goes quiet for long stretches (e.g. one very slow
page load); 120s already covers normal browser/search latency.

The agent's final answer text lands in the `-o` file (or stdout). The wrapper runs pi in
`--mode json` and writes the raw NDJSON event stream alongside it as `<-o file>.jsonl`, then
extracts the answer from that stream. Two consequences:

- **Live visibility**: `tail -f results/task-07.txt.jsonl` to watch the worker think, call the
  browser/search tools, and emit tokens in real time — no more black box until exit.
- **Timeouts aren't empty**: events flush incrementally, so exit `124` (timeout) still leaves
  the partial answer in the `-o` file plus the full tool history in the `.jsonl` stream.

It prints a `pi-research: done model=… exit=… reason=… elapsed=…s answer_chars=… stream=…` line
to **stderr**. `reason=` classifies the outcome so you can pick a retry strategy:
`ok` (clean), `stall` (watchdog killed a hung worker), `hardcap` (hit the `-t` ceiling), or
`empty` (gateway returned no text). `answer_chars=0` flags a genuinely empty result (see
validation below). A partial answer is recovered from the stream on both `stall` and `hardcap`.

## Orchestration pattern

1. **Decompose** the goal into independent, self-contained tasks. Each worker starts cold with
   zero shared context, so each prompt must carry everything it needs.
2. **Fan out** in parallel. Launch each worker as a background Bash task (`run_in_background:
   true`) or shell `&`, capturing each to its own `-o` file. Use a distinct `-n` name per task.
   Practical concurrency: ~5–10 at a time (the free gateway throttles under load).
3. **Collect** as workers finish. Read each `-o` file. **Validate**: an empty file or a missing
   expected marker (e.g. no `SOURCES:`) means a flaky/empty completion — re-dispatch that one
   task (optionally on a different model). Cheap gateways intermittently return empty; budget
   for a retry pass. To tell *why* a task failed, check the `reason=` field on the stderr `done`
   line: `reason=stall` = worker hung (re-dispatch, or raise `-s` if it was a legitimately slow
   step), `reason=hardcap` = hit the `-t` ceiling (rare; raise `-t` only for a genuinely huge
   task), `reason=empty` = a true gateway empty-completion (just retry). The `.jsonl` stream
   holds the partial work in every case.
4. **Synthesize** the verified worker outputs into the final answer yourself. Treat worker
   findings as research notes from junior agents: cross-check sources, resolve conflicts, and
   own the conclusion.

Keep a simple task ledger (a dir of `-o` files, or a TaskCreate/TaskUpdate list) so you know
which tasks are pending / done / need retry.

## Writing worker prompts

Workers run small models — be explicit and constrain the output:

- **Self-contained**: include all context; never assume the worker knows the broader goal.
- **Bounded**: "in one line", "max 5 bullets" — small models ramble and waste tokens/time.
- **Structured + verifiable**: demand a parseable shape and a `SOURCES:` block of URLs so you
  can validate completeness and trust. Example: *"… End with a line `SOURCES:` listing every
  URL you opened."*
- **Tool-directing**: "Use web search to verify" nudges it to actually use the browser/search
  tools rather than answer from stale memory.

## Model menu (cheap OSS via opencode-go)

Verify live with `pi --list-models`. Keep `--thinking low` (or `off`) for fan-out speed; raise
to `medium` only for genuinely hard synthesis.

| Model | Use for |
|-------|---------|
| `opencode-go/glm-5.1` | default; fast, solid general research |
| `opencode-go/qwen3.6-plus` | stronger reasoning; vision-capable |
| `opencode-go/kimi-k2.6` | long context; vision-capable |
| `opencode-go/deepseek-v4-flash` | cheapest, 1M context, no vision (latency varies) |
| `opencode-go/minimax-m2.7` | long max-output tasks |
| `openai-codex/gpt-5.4-mini` | capable fallback; uses ChatGPT Plus quota, not free |

Spreading tasks across models also spreads gateway load and reduces correlated empty-completion
failures.

## Container flags (the wrapper maps these to `docker run`)

- `--network on` (default) → container egress via the bridge: the model gateway, pi-webaio
  search/fetch, and the in-container `browser` tool (Playwright/Chromium) all work. `--network
  off` → `--network none`, **full isolation including the model gateway** — only usable with a
  model that needs no egress (not the remote opencode-go models), so it's rarely what you want.
- `--mount-cwd DIR` → bind-mounts `DIR` read-write at `/workspace` so the worker can persist
  files to the host. **Use for single-writer tasks only.** Parallel workers must NOT share one
  mount (race conditions) — prefer returning findings on stdout and writing them yourself.
- `--image IMAGE` → override the sandbox image (default `agent-sandbox:latest`).
- Each invocation is its own `docker run --rm` container, named `-n NAME` (or an auto
  `pi-research-<pid>-<rand>`), capped at 4g/2 CPU. Parallel workers never collide and the
  wrapper force-removes the container on any exit, so nothing leaks.

## Gotchas

See `references/troubleshooting.md` for the full debugging story. The essentials:

- **Auth alias doesn't apply non-interactively** — go through the wrapper; it forwards the key
  into the container via `docker run -e OPENCODE_API_KEY`.
- **`pi -p` must exit on its own.** A ref'd `setInterval` in **pi-webaio** once kept Node's event
  loop alive so every scripted `pi -p` "hung" after printing its answer; fixed upstream by
  `.unref()` (apmantza/pi-webaio#36) and baked into the image's pinned pi-webaio. Less critical
  now anyway: the worker runs in `docker run --rm`, so the container is destroyed on exit and a
  genuine hang just trips the stall watchdog. If you bump the image's pi-webaio and runs start
  hanging, re-check the timer with `pi -p -ne "hi"` (exits clean) vs `pi -p "hi"` (hangs).
- **`--network off` also kills the model gateway** now that pi runs in-container — keep network
  on (default) for opencode-go workers.
- **Empty completions** from the free gateway are normal under load — validate output, retry.
- **The stall watchdog + hard cap are built into the wrapper** so one hung task can't stall the
  swarm. A worker is killed only after `-s` seconds of *no output* (genuine hang), not for being
  slow; the `-t` ceiling is the ultimate backstop. Always go through the wrapper to get them.
- **Don't leak containers** — each worker is `docker run --rm` and the wrapper force-removes its
  named container on any exit. Stray `pi-research-*` containers (`docker ps -a`) mean the wrapper
  itself was killed mid-run; `docker rm -f` them.
- **Image drift** — the image pins pi to the host version (`PI_VERSION` build arg). After a host
  `pi update`, rebuild the image so brain and hands stay in sync.
