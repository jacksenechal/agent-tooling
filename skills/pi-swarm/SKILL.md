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

This verifies `pi`, `docker`, the `agent-sandbox:latest` image, and that an opencode key is
resolvable. All four must be green. If the sandbox image is missing, it's built from
`~/workspace/agent-sandbox` (`docker build -t agent-sandbox:latest .`).

**Auth is the #1 gotcha.** `pi`'s provider key is injected by a shell *alias*
(`OPENCODE_API_KEY=$(cat ~/.config/keys/opencode.key) pi`) that does NOT apply in scripted /
non-interactive shells. The helper script resolves the key explicitly, so always go through it
rather than calling bare `pi`. The portable fix is to store the key in `~/.pi/agent/auth.json`
(`"opencode-go": { "type": "api_key", "key": "..." }`) — then any `pi` invocation is authed.

## The worker contract

One worker = one `pi -p` run via the wrapper. The wrapper bakes in every hard-won robustness
fix (key resolution, `</dev/null` stdin, `timeout` safety net, sandbox flags):

```bash
skills/pi-swarm/scripts/pi-research.sh \
  -m opencode-go/glm-5.1 \   # model (see menu below)
  -t 300 \                   # hard timeout in seconds (safety net; default 300)
  --network on \             # web access (search/fetch + Playwright browser)
  -o results/task-07.txt \   # capture the agent's final answer here
  -n swarm-task-07 \         # container/session name (traceability)
  "PROMPT"                   # or: --prompt-file path/to/prompt.md
```

The agent's final answer text lands in the `-o` file (or stdout). The wrapper runs pi in
`--mode json` and writes the raw NDJSON event stream alongside it as `<-o file>.jsonl`, then
extracts the answer from that stream. Two consequences:

- **Live visibility**: `tail -f results/task-07.txt.jsonl` to watch the worker think, call the
  browser/search tools, and emit tokens in real time — no more black box until exit.
- **Timeouts aren't empty**: events flush incrementally, so exit `124` (timeout) still leaves
  the partial answer in the `-o` file plus the full tool history in the `.jsonl` stream.

It prints a `pi-research: done model=… exit=… elapsed=…s answer_chars=… stream=…` line to
**stderr**. `answer_chars=0` flags a genuinely empty result (see validation below).

## Orchestration pattern

1. **Decompose** the goal into independent, self-contained tasks. Each worker starts cold with
   zero shared context, so each prompt must carry everything it needs.
2. **Fan out** in parallel. Launch each worker as a background Bash task (`run_in_background:
   true`) or shell `&`, capturing each to its own `-o` file. Use a distinct `-n` name per task.
   Practical concurrency: ~5–10 at a time (the free gateway throttles under load).
3. **Collect** as workers finish. Read each `-o` file. **Validate**: an empty file or a missing
   expected marker (e.g. no `SOURCES:`) means a flaky/empty completion — re-dispatch that one
   task (optionally on a different model). Cheap gateways intermittently return empty; budget
   for a retry pass. To tell *why* a task failed, check the stderr `done` line: `exit=124` =
   timeout (raise `-t` or re-dispatch), while `exit=0 answer_chars=0` = a true gateway
   empty-completion (just retry). The `.jsonl` stream holds the partial work either way.
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

## Sandbox flags (passed through by the wrapper)

- `--network on` → outbound net + the `browser` tool (Playwright/Chromium) + pi-webaio
  search/fetch. Off = fully isolated (no web).
- `--mount-cwd DIR` → mounts `DIR` read-write at `/workspace` so the worker can persist files
  to the host. **Use for single-writer tasks only.** Parallel workers must NOT share one mount
  (race conditions) — prefer returning findings on stdout and writing them yourself.
- Each invocation gets its own auto-named `pi-agent-<random>` container (`--rm`), so parallel
  workers never collide and clean themselves up on exit.

## Gotchas

See `references/troubleshooting.md` for the full debugging story. The essentials:

- **Auth alias doesn't apply non-interactively** — go through the wrapper (or use `auth.json`).
- **`pi -p` must exit on its own.** A ref'd `setInterval` in the **pi-webaio** extension kept
  Node's event loop alive so every scripted `pi -p` "hung" after printing its answer. Fixed by
  `.unref()` (local patch applied to `~/.pi/agent/npm/node_modules/pi-webaio/index.ts`; upstream
  draft PR: apmantza/pi-webaio#36). **`pi update` will revert the local patch** — re-apply or
  confirm the PR landed if scripted runs start hanging again. Diagnose with: `pi -p -ne "hi"`
  (exits clean) vs `pi -p "hi"` (hangs) ⇒ an extension is holding the loop.
- **Empty completions** from the free gateway are normal under load — validate output, retry.
- **`timeout` is mandatory** on every worker so one bad task can't stall the swarm.
- **Don't leak containers** — workers use `--rm` and clean up on clean exit; if you see stray
  `pi-agent-*` containers (`docker ps`), a worker was SIGKILL'd. `docker rm -f` them, or
  `/sandbox prune` inside an interactive pi.
