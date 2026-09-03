# Orchestrator Loop

A long-running background loop that keeps the pipeline fed and current without the user
driving it. Two scheduled jobs: **daily discovery** and **weekly liveness + sync**.

## Why systemd, not CronCreate or /loop

`CronCreate` and `/loop` are **session-scoped**: in-memory, gone when the Claude session
exits, and recurring cron jobs auto-expire after 7 days. Neither can back a loop that is
meant to run for months.

Cloud routines (the `schedule` skill) are also wrong here: they run in a remote environment
with **no access to the golden browser session**, and every saved-list source requires a
logged-in session on the user's own machine.

So the substrate is **systemd user timers** on the user's Linux box, each invoking headless
`claude -p`. This survives reboots, needs no open terminal, and runs where the logins live.

Caveat worth stating plainly: the machine has to be awake. `Persistent=true` makes a missed
timer fire on next boot, so a laptop that sleeps overnight runs the job when it wakes rather
than skipping the day.

## Source registry

Saved-list sources live in `~/workspace/jobs/sources.json` so new ones can be added without
touching the skill. Shape:

```json
{
  "sources": [
    {
      "name": "indeed",
      "enabled": true,
      "saved_list_url": "https://myjobs.indeed.com/saved",
      "job_url_pattern": "https://www.indeed.com/viewjob?jk={key}",
      "key_field": "jk",
      "writable": true,
      "notes": "Native status columns (Saved/Applied/Interviewing/Offer/Rejected)."
    },
    {
      "name": "linkedin",
      "enabled": true,
      "saved_list_url": "https://www.linkedin.com/my-items/saved-jobs/",
      "job_url_pattern": "https://www.linkedin.com/jobs/view/{key}/",
      "key_field": "currentJobId",
      "writable": true,
      "write_scope": "archive_unsave_only",
      "notes": "Subject to linkedin-safety.md. Max 10 writes/session, count double."
    }
  ]
}
```

**Identity**: a job is keyed by `(source, key)`, the site's own job id. This is the dedup key,
stored in the tracker `url` field and parsed back out. Never dedup on company+title alone;
the Glassdoor case in this repo (two distinct `jk` values, same title) shows why.

## Daily: discovery

Runs once a day at a randomized time (see Scheduling).

1. **Preflight.** Verify the golden browser is up; start it if not. Take a screenshot to
   confirm a normal logged-in state before touching any source (§9 session hygiene).
2. **Scrape each enabled source.** One subagent per source, using `mcp__playwright-golden__*`.
   `haiku` for Indeed, `sonnet` for LinkedIn (stateful safety protocol). Return the saved list
   verbatim: title, company, location, date saved, and the job URL with its key.
3. **Diff against the tracker** on `(source, key)`. Anything not already present is new.
4. **Auto-add and auto-research** each new job (the user's chosen autonomy level):
   - Append to `tracker.csv` at `stage=discovered`.
   - Run Stage 1 research: parallel `haiku` subagents for company background, and the
     authenticated browser for the posting itself and Glassdoor.
   - Synthesize `company-research.md` **on the main thread (Opus)**, including a fit
     assessment against `strategy/narrative.md` positioning. Per the model-selection rule,
     fit judgment never goes to a cheap subagent.
   - Advance to `stage=researched`.
5. **Commit and push** the jobs repo.
6. **Notify** with a one-screen summary: what was added, the fit read on each, and anything
   that looks like an obvious misfit worth pruning.

**Budget guard**: if a single run finds more than 8 new jobs, research the 8 with the
strongest surface-level fit, add the rest at `stage=discovered` without research, and say so
explicitly in the notification. Never silently truncate.

## Weekly: liveness + sync

### Liveness

Checks whether postings are still open. **Applies to rows at `discovered` through `applied`.**
Rows at `interviewing` or `offer` are never touched: once you are in an active process, the
posting coming down usually means the req was filled by the candidate in it, so it is reported
in the summary and the stage is left to the user. Terminal rows (`rejected`, `withdrawn`,
`closed`) are skipped.

**Detection is semantic, not HTTP.** A 404, a timeout, a redirect, or a network error is
**inconclusive**, never a closure. ATS platforms 404 and redirect for many reasons unrelated
to the job being filled. What counts as closed is explicit on-page text:

- "no longer accepting applications"
- "this job is no longer available"
- "this position has been filled"
- "this job posting has expired" / "has closed"
- LinkedIn: "No longer accepting applications"
- Greenhouse/Lever: the posting body replaced by a "job closed" notice

Outcomes:

| Finding | Action |
|---|---|
| Explicit closure text | `stage=closed`, note the phrase found and the date, archive the folder (`git mv applications/<id> applications/archived/<id>`) |
| Posting loads normally | No change; clear any prior inconclusive counter |
| 404 / error / redirect / unparseable | **Inconclusive.** Increment a counter in `notes`, leave `stage` alone, retry next week |

An inconclusive result that persists for **4 consecutive weeks** gets surfaced in the
notification for a human decision. It still does not auto-archive.

`closed` is a distinct stage from `rejected` (they said no) and `withdrawn` (the user pulled
out). Add it to the stage list as a terminal state.

### Sync

Reconciles each writable source's saved list with the tracker. Tracker is authoritative.

| Tracker stage | Indeed status | LinkedIn saved list |
|---|---|---|
| `discovered` … `ready_to_apply` | Saved | keep saved |
| `applied` | Applied | keep saved |
| `interviewing` | Interviewing | keep saved |
| `offer` | Offer | keep saved |
| `rejected` / `withdrawn` / `closed` | Rejected / archive | **archive** |

"Archive" here means the external site's own archive/un-save state. These rows are also
archived locally by this point (folder under `applications/archived/`, per SKILL.md's
"Archiving" section) — the two are separate and both should already be true.

LinkedIn writes are governed by `linkedin-safety.md` §7: archive/un-save only, max 10 per
session counting double against the page budget, full delay-and-breather treatment on each,
abort to read-only on any anomaly. If more than 10 need syncing, do 10 and leave the rest for
next week. Indeed writes are less constrained but still get natural pacing.

## Scheduling

Two systemd user timers. Both use `RandomizedDelaySec` so the loop does not hit these sites
at the same wall-clock minute every day, which is itself a bot signal.

| Timer | Cadence | Randomization |
|---|---|---|
| `job-search-discover.timer` | daily, ~09:00 | `RandomizedDelaySec=5400` (±90 min) |
| `job-search-liveness.timer` | weekly, Sun ~10:00 | `RandomizedDelaySec=10800` (±3 h) |

Additionally, the discovery run **skips at random roughly one day in seven**. Perfect daily
regularity is more machine-like than occasional absence, and missing a day costs nothing
since bookmarks persist.

## Concurrency and safety

- **Lockfile** at `~/workspace/jobs/.orchestrator.lock`. If held, exit immediately. Prevents
  a long discovery run from colliding with the weekly sweep, and prevents self-overlap.
- **Page budget is per run**, not per day. The 25-load LinkedIn ceiling applies to each
  invocation, and LinkedIn writes count double.
- **CAPTCHA aborts everything.** Any challenge on any source: stop all browser work, write
  what has been learned so far, notify the user, and exit non-zero. Do not retry that day.
- **Never submit an application.** The loop's authority ends at discovery, research, tracker
  state, and saved-list bookkeeping. Applying is always a human action.
- **Every run is idempotent.** Re-running after a crash must not double-add rows. The
  `(source, key)` dedup makes this safe.
- **Audit.** Append one line per run to `~/workspace/jobs/orchestrator.log`: timestamp, mode,
  sources scraped, jobs added, stages changed, writes performed, page-load count.

## Permissions (read this before the first scheduled run)

The loop invokes `claude -p ... --permission-mode acceptEdits`. In headless mode there is no
human to answer a permission prompt, so **any tool call that is not pre-approved fails rather
than waiting**. Before enabling the timers, allowlist what the loop actually needs in
`~/workspace/jobs/.claude/settings.json`:

- the `mcp__playwright-golden__*` browser tools
- `Bash(git add:*)`, `Bash(git commit:*)`, `Bash(git push:*)`, `Bash(python3:*)`
- `Read`, `Write`, `Edit` on the jobs repo

`--dangerously-skip-permissions` is deliberately NOT used. An unattended loop with a browser
session and push access to two repos is exactly the thing that should keep its guardrails.

Verify with a manual foreground run before trusting the schedule:

```bash
~/workspace/agent-tools/skills/job-search/scripts/orchestrator.sh discover --force --dry-run
~/workspace/agent-tools/skills/job-search/scripts/orchestrator.sh discover --force
```

## Failure handling

The loop runs unattended, so failures must be loud in the log and quiet on the machine.

- Any source that fails to scrape is **skipped, not fatal**. Other sources still run.
- A failed research pass leaves the job at `stage=discovered` for the next run to retry.
- Three consecutive failed runs of the same timer should notify the user that the loop is
  broken rather than silently continuing to fail.
- The loop never deletes a tracker row. Terminal states are reversible by editing the CSV.
