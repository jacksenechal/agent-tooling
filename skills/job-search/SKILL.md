---
name: job-search
description: >
  Job application pipeline: process LinkedIn job URLs, tailor resumes, rank referral
  connections by warmth from an ArcadeDB knowledge graph, track application status, and
  run a scheduled orchestrator over saved-job lists. Trigger on job URLs, "apply to",
  "tailor resume for", "find connections at", "job tracker", or "job search". Full trigger
  list under "When To Use This".
---

# Job Search Pipeline Skill

You are managing the user's job application pipeline. This skill orchestrates the full
workflow from LinkedIn job URL to ready-to-apply state.

**Run the entire pipeline end-to-end without stopping for user confirmation.** The user
will review artifacts after the run completes.

## When To Use This

Any job-pipeline task. Beyond the phrases in the description, this also covers:
"application status", "knowledge graph", "warmth score", "ingest linkedin", "saved jobs",
"scan bookmarks", "still open", "orchestrator loop", "scout", "vet", "coherence read", and
"find high-coherence companies".

The orchestrator runs on timers rather than on request: a daily scan of saved-job lists
(`discover`) and a weekly posting-liveness sweep plus saved-list sync (`liveness`). See
those sub-commands below, and `watch setup` to install the timers.

## Project Locations

- **Job search repo**: `~/workspace/jobs/` (private GitHub repo)
- **Tracker**: `~/workspace/jobs/tracker.csv`
- **Job research**: `~/workspace/jobs/applications/<id>/`
- **Resume repo**: `~/workspace/resume/` (separate git repo)
- **LinkedIn safety rules**: See `references/linkedin-safety.md` — READ THIS before any LinkedIn browsing

## Browser Automation

This skill requires an MCP server providing Playwright-style browser tools
(`browser_navigate`, `browser_snapshot`, `browser_click`, `browser_type`, etc.).

**Default**: Dockerized Playwright via the `/playwright-docker` skill — persistent sessions,
file uploads, real-time noVNC monitoring. Run `/playwright-docker setup` if not yet configured.

**Fallback**: browsermcp — controls your real desktop browser. No Docker required, but cannot
do file uploads. See `references/browser-setup.md` for fallback setup instructions.

## Research Routing

Research is mechanical work that consumes context and doesn't benefit from expensive models.
Offload it to subagents; keep the main thread for synthesis, resume tailoring, response
drafting, and decisions.

**All research runs as Claude subagents via the Agent tool.** Spawn them in parallel — several
Agent calls in a single message — and synthesize their returns on the main thread.

### Model selection

Match the model to the *kind* of thinking the task needs, not its length:

| Model | Use for | Examples in this pipeline |
|---|---|---|
| `haiku` | Mechanical extraction. One page, known fields, return verbatim. | Job posting scrape, Glassdoor capture, application form enumeration |
| `sonnet` | Multi-step execution and clean prose. Follows a protocol carefully, writes well. | LinkedIn connection search, drafting a section from supplied facts |
| `opus` | Real thinking: strategy, judgment, tradeoffs, anything where being *wrong* is worse than being *slow*. | Fit assessment, outreach strategy, resume tailoring decisions, cover-letter angle |

The distinction that matters: **Sonnet writes well but does not reason deeply.** Give it
facts and a shape and it produces good prose. Do not give it a decision that requires weighing
competing considerations, reading between the lines of a job description, or judging whether a
role is actually a good fit — that work goes to Opus, or stays on the main thread.

Default to keeping strategic work on the main thread (already Opus). Spawn an explicit `opus`
subagent only when the analysis needs its own large context, e.g. reading a full application
history before drafting.

### Public web research (no login required)

Company background, news, funding, products, engineering blog/culture, tech stack, salary
benchmarks, public interview-process intel, and any batch of similar lookups. Give each
subagent one topic, `WebSearch`/`WebFetch`, and a requirement to end with a `SOURCES:` block
listing every URL it opened. Validate each return (non-empty + has `SOURCES:`) and
re-dispatch anything that came back thin.

### Authenticated / ban-prone browsing (`playwright-docker`)

Anything that needs a logged-in session or aggressively bans automation: **LinkedIn** (job
postings, connection search), **Glassdoor**, **Indeed**, and **application form discovery +
filling** (the persistent session and file uploads live here).

**Pattern**: spawn a `haiku` subagent (or `sonnet` for multi-step LinkedIn work) via the
Agent tool, instructing it to use the `mcp__playwright-golden__*` tools. Give it: the URL(s),
exact fields to extract, and a requirement to return verbatim text — no summarization.
CAPTCHA = STOP. The main thread does all writing.

Never point a fresh, unauthenticated browser at these sites — it trips bot detection and
risks the user's accounts. Use the golden (persistent-login) session.

Stages needing the authenticated browser: **1** (job posting + Glassdoor), **3** (form
discovery), **5** (LinkedIn connection search). Stage **1** also includes broad public
company research, which needs no browser session.

## Knowledge Graph

A local ArcadeDB graph of LinkedIn connections ranked by warmth. Used in Stage 5 to
prioritize outreach. Run `/job-search kg setup` to initialize.
See `references/knowledge-graph.md` for setup, schema, warmth algorithm, and query patterns.

## Sub-Commands

### `add <linkedin-url>` — Process a new job

Walk through the full pipeline for a new job posting end-to-end.

**Stage 1: Discover & Research**

1. Generate an `id` slug (e.g., `stripe-infra-eng`, `aircall-ai-eng`). Short, semantic, unique. Do NOT ask the user.
2. Create `~/workspace/jobs/applications/<id>/`
3. Add row to `tracker.csv`: `stage=discovered`, `date_found=today`
4. Scrape the job posting via a **haiku subagent**:
   - Spawn an Agent (model: haiku) with the task: "Navigate to `<linkedin-url>` following the LinkedIn safety protocol (see `references/linkedin-safety.md`). Use `browser_snapshot` to capture the full accessibility tree. CAPTCHA RULE: if any snapshot shows a CAPTCHA or security challenge, STOP, navigate to google.com, and return 'CAPTCHA_DETECTED'. Otherwise, return the verbatim snapshot text — company, role, full description, application URL, location, requirements, hiring team (names, titles, connection degree). Do not summarize."
   - `WebFetch` is a fallback if browser tools are unavailable — it summarizes and misses application URLs.
   - The subagent returns raw extracted text; the main thread parses and structures it.
5. Save to `applications/<id>/job-posting.md`:
   ```markdown
   # <Company> — <Role>

   **URL**: <linkedin-url>
   **Application URL**: <external-url-if-found>
   **Location**: <location>
   **Date Found**: <today>

   ## Hiring Team
   - <name> — <title> (<connection degree>)

   ## Job Description
   <full description — verbatim from snapshot>

   ## Key Requirements
   <bulleted list>

   ## Notes
   <initial observations on fit, concerns>
   ```
5b. **Geographic filter and liveness.** Read the posting's own location line from the snapshot.
   If it is not Remote (United States) or San Francisco Bay Area, set `stage=closed` with the
   note `geo: <location line>` and stop here. If the page redirected to a board index or says
   the role is filled, `stage=closed`, note `dead at add`, stop.
5c. **Coherence read.** If no row for this company has a `coh_verdict`, run `vet <company>`
   now (one `sonnet` subagent, tier-1 section of
   `~/workspace/jobs/strategy/coherence-instrument.md`) and write `coh_cell`,
   `coh_derivative`, `coh_verdict`, `coh_date` on the row. `Pass` → `stage=withdrawn`, note
   `coherence Pass`, stop. `Price` → continue, but carry the why-line into `job-posting.md`
   "Notes" so the loop questions and the seat shape are visible from the first artifact.
   `Advance` and `Unknown` → continue. A company vetted in the last 90 days is not re-vetted.
6. Research company on Glassdoor via a **haiku subagent**:
   - Spawn an Agent (model: haiku) with the task: "Navigate to `https://www.glassdoor.com/Search/results.htm?keyword=<URL-encoded-company-name>`. Snapshot results, click through to the company's Reviews page, snapshot the overview. Scroll and snapshot to capture more highlights. CAPTCHA RULE: if any snapshot shows a CAPTCHA or security challenge, STOP, navigate to google.com, and return 'CAPTCHA_DETECTED'. Otherwise, return verbatim: overall rating, CEO approval %, recommend-to-friend %, pros/cons summary, and 2-3 notable review snippets. Do not summarize."
   - The subagent returns raw text; the main thread writes `glassdoor.md` and synthesizes takeaways.
   - If the company isn't found on Glassdoor, the subagent notes that and returns.
   - Save to `applications/<id>/glassdoor.md`. Add a "Coherence read" line at the top with the
     verdict and why-line from 5c, and put the negative-tail themes under "Takeaways" as loop
     questions (how expectations are written before a review, how comp changed, what happened
     the last time someone pushed back, how often teams re-form).
     ```markdown
     # Glassdoor — <Company>

     **URL**: <glassdoor-reviews-url>
     **Overall Rating**: <X.X/5>
     **Recommend to a Friend**: <X%>
     **CEO Approval**: <X%>

     ## Pros (common themes)
     - <theme>

     ## Cons (common themes)
     - <theme>

     ## Notable Reviews
     <2-3 particularly insightful snippets relevant to the role/team>

     ## Takeaways for Application
     <What to emphasize in cover letter/interviews based on what employees value;
      what concerns to probe during interviews>
     ```
   (Glassdoor bans fresh automated browsers, so it stays on the authenticated
   playwright-golden session.)
7. **Broad company research via parallel subagents** (public sources, no browser session
   needed). Fan out several `haiku` subagents at once to enrich the application. Good angles
   (skip any already covered by Glassdoor):
   - recent company news, funding, and trajectory
   - what the team/product does and the tech stack (from the company site, eng blog, GitHub)
   - engineering culture and values (the company's own sources, not Glassdoor)
   - role-specific context worth knowing for the cover letter and interviews
   Spawn them as multiple Agent calls in a single message so they run concurrently. Give each
   one angle, `WebSearch`/`WebFetch`, and a requirement to end with a `SOURCES:` block listing
   every URL it opened. Validate each return (non-empty + has `SOURCES:`), re-dispatch anything
   thin, then synthesize into `applications/<id>/company-research.md` (sections per angle + a
   "Takeaways for Application" block). Prefer this over burning main-thread context on public
   web research.
8. Update tracker: `company`, `role`, `application_url`, `stage=researched`

**Stage 2: Tailor Resume**

1. `cd ~/workspace/resume && git fetch --all --prune`
2. List remote branches (`git branch -r`), find the closest `role/` archetype. Do not ask the user.
3. Create branch: `git checkout -b job/<id> origin/<base-branch>`
4. Read `CONTEXT.md` — respect all factual constraints
5. Read `resume.md` and the saved job description
6. Tailor `resume.md`: adjust Summary, reorder/emphasize bullets, update Skills, compress less-relevant experience. Keep ATS-friendly formatting (see `resume/AGENTS.md`)
7. Run `./_publish` to generate HTML and PDF
8. Copy the PDF into the job directory with a descriptive filename:
   ```bash
   cp ~/workspace/resume/resume.pdf \
      ~/workspace/jobs/applications/<id>/"Resume - Jack Senechal - <role>.pdf"
   ```
   Use the actual job title for `<role>` (e.g. `Platform Engineer`, `Staff Software Engineer`).
9. `git add -A && git commit -m "Tailor resume for <company> <role>"`
10. `git push -u origin job/<id>`
11. `xdg-open ~/workspace/jobs/applications/<id>/"Resume - Jack Senechal - <role>.pdf"`
12. Update tracker: `resume_branch=job/<id>`, `role_branch=<base>`, `stage=resume_tailored`

**Stage 3: Prep Application**

1. Discover and enumerate the application form via a **haiku subagent**:
   - Spawn an Agent (model: haiku) with the task: "Navigate to `<application_url>` (or if unknown, to the job posting page and find the Apply button). Snapshot the full application form. CAPTCHA RULE: if any snapshot shows a CAPTCHA or security challenge, STOP, navigate to google.com, and return 'CAPTCHA_DETECTED'. Otherwise, return verbatim: every field name, type, whether required or optional, all essay/written questions, and what file uploads are required. Identify the platform (Greenhouse/Lever/Workday/etc). Do not summarize."
   - If no `application_url` is known, have the subagent navigate the job posting and capture the Apply URL first.
2. Main thread uses the subagent's output to write `applications/<id>/application-form.md`.
3. Save to `applications/<id>/application-form.md`:
   ```markdown
   # Application Form — <Company> <Role>

   **Application URL**: <url>
   **Platform**: <Greenhouse/Lever/Workday/Custom/LinkedIn Easy Apply>

   ## Required Fields
   - <field name>: <type> — <notes>

   ## Optional Fields
   ...

   ## Questions / Essays
   - <question text>

   ## Uploads Required
   - Resume (PDF)
   - Cover letter? (yes/no)
   ```
4. Update tracker: `application_url` if newly found, `stage=application_prepped`

**Stage 4: Draft Application Responses**

Do this on the main thread (Opus) or an explicit `opus` subagent — never sonnet. Choosing what
to claim, which narrative to lead with, and how to handle a weak spot honestly is judgment
work, and a fluent wrong answer here is worse than no draft. Sonnet may be handed a settled
angle to polish, but not the decision of what the angle is.

**Any text the user will send verbatim must be immediately copy-pasteable.** This covers
application answers, cover letters, outreach messages, and recruiter replies. Two hard rules:

- **No blockquote (`>`) indentation on the draft itself.** Quoting it into a markdown blockquote
  makes the user strip a `> ` from every line before sending. Put the draft in a plain section
  under a heading, or in a fenced code block. Commentary about the draft goes outside it.
- **No hard-wrapped lines inside the draft.** Let sentences and paragraphs run long on one line.
  Hard wraps at 80-100 chars survive the paste into Gmail/LinkedIn as ragged line breaks.
  (Hard wrapping is still correct for the surrounding prose in these docs, just not the draft.)

For any written questions or essays identified in Stage 3:

1. Read `applications/<id>/application-form.md`, `applications/<id>/job-posting.md`, `applications/<id>/glassdoor.md`, tailored `resume.md`, and `~/workspace/resume/CONTEXT.md`
2. Draft responses: specific to the user's experience, tailored to role and company, concise, honest per CONTEXT.md constraints
3. Save to `applications/<id>/application-responses.md` with each question clearly labeled. If no written questions, note that.

**Cover letters**: when a posting wants a cover letter (or it strengthens the app), draft it to
`applications/<id>/cover-letter.md` (plain markdown; a leading `# ...` title line is treated as
an internal doc title and dropped from the PDF). Render a styled, one-page PDF with the shared
template script — do NOT hand-roll pandoc/Chrome styling each time:

```bash
# Name is supplied at runtime (no PII in this repo — see AGENTS.md). Source it from the private
# profile, e.g.: NAME=$(awk -F'|' '/Full name/{gsub(/ /,"",$3);print $3}' ~/workspace/jobs/profile.md)
~/workspace/agent-tools/skills/job-search/scripts/make_cover_letter_pdf.sh \
  applications/<id>/cover-letter.md \
  "applications/<id>/Cover Letter - <Your Name> - <Role>.pdf" \
  --name "<Your Name>" \
  --subtitle "<tagline matching the tailored resume title>"
```
The script gives true 1in side / 0.5in top-bottom margins and roomy line spacing (it overrides
pandoc's default `max-width`/padding, which otherwise reads as ~2in margins). Use a middle dot
`·` (not a dash) in `--subtitle` to match the tailored resume title. `--name` is required (flag
or `$JOB_SEARCH_APPLICANT_NAME`); the script bakes in no personal default.

**Stage 5: Find Connections & Outreach Strategy**

**READ `references/linkedin-safety.md` BEFORE THIS STAGE.**

#### Step 1: Search connections via a **sonnet subagent**

Use `sonnet` (not haiku) for LinkedIn — the safety protocol is multi-step and stateful (page
budgets, randomized waits, breather navigations, CAPTCHA bailout) and haiku follows it
unreliably. This is careful protocol execution, not strategy: the subagent only gathers the
person list. All ranking and outreach strategy happens in Step 4 on the main thread.

Spawn an Agent (model: sonnet) with the task:
> "Search LinkedIn for connections at `<Company>`. Read `references/linkedin-safety.md` first and follow the protocol exactly. Use this URL:
> `https://www.linkedin.com/search/results/people/?keywords=my%20connections%20who%20currently%20work%20at%20<URL-ENCODED-COMPANY>&origin=FACETED_SEARCH&network=%5B%22F%22%2C%22S%22%5D`
> Page through ALL results (max 8 LinkedIn page loads total, use google.com as breather between pages). For each person found, return: name, title, connection degree, mutual connections. NEVER click individual profiles. CAPTCHA RULE: if any snapshot shows a CAPTCHA or security challenge, STOP, navigate to google.com, and return 'CAPTCHA_DETECTED'. End by navigating to google.com. Return the full list verbatim."

The subagent returns the raw person list; the main thread does all cross-referencing and strategic analysis.

#### Step 2: Pull warmth scores from Knowledge Graph

```bash
python3 ~/workspace/agent-tools/skills/job-search/scripts/query_connections.py "<Company Name>"
```

Returns 1st-degree connections at the company ranked by warmth score. See `references/knowledge-graph.md` for score interpretation and setup. If the KG hasn't been set up, skip this step and note it in the output.

#### Step 3: Cross-reference with hiring team

Pull hiring team from `applications/<id>/job-posting.md`. Note which members appeared in search results and at what degree.

#### Step 4: Strategic analysis

For every person found, assess relevance, seniority, connection strength, and outreach value. Categorize into tiers and rank all of them — not just top 2-3:

**Tier 1 — Warm 1st-degree**: Best path. Ask them to intro or submit a referral. Higher warmth score = higher confidence.
**Tier 2 — Peer ICs on same/adjacent team**: Best direct outreach. Peer-to-peer feels natural; most companies give referral bonuses.
**Tier 3 — Hiring manager**: High value, handle carefully. Lead with genuine curiosity about what they're building — not "I applied." Only recommend if there's a credible angle (shared background, specific technical question).
**Tier 4 — Adjacent department**: Intel only. Low referral conversion.

Outreach principles:
- 1st-degree: ask casually about the role and whether they'd make an intro or submit a referral
- 2nd-degree: conversational opener only — never ask for a referral in the first message
- Hiring manager: research anything they've published or spoken about first
- Always recommend applying regardless — referral is a booster, not a gate

#### Step 5: Save and update tracker

Save to `applications/<id>/connections.md` using the template in `references/knowledge-graph.md`.
Update tracker: `referral_contact` with top recommendation, `referral_status=identified`, `stage=connections_found`.

**Stage 6: Finalize & Push**

1. Verify all artifacts exist: `job-posting.md`, `glassdoor.md`, `company-research.md`, `application-form.md`, `application-responses.md`, `connections.md`, `Resume - Jack Senechal - <role>.pdf` in `applications/<id>/` (plus `cover-letter.md` and its rendered PDF when a cover letter applies)
2. Update tracker: `stage=ready_to_apply`
3. Commit and push job-search repo:
   ```bash
   cd ~/workspace/job-search
   git add -A
   git commit -m "Add <company> <role> application package"
   git push
   ```
4. Verify resume branch was pushed: `cd ~/workspace/resume && git push -u origin job/<id>`
5. Print summary:
   ```
   Ready to apply: <Company> — <Role>

   Resume: branch job/<id> (pushed to origin)
   Application: <application_url>
   Referral: <referral_contact> (<referral_status>)
   Research: jobs/applications/<id>/

   Files to review before applying:
   - applications/<id>/application-responses.md              (edit your written answers)
   - jobs/<id>/Resume - <Your Name> - <role>.pdf   (ready to upload)

   Both repos pushed to GitHub — resume from any device with /job-search sync
   ```

### `discover` — Daily saved-list scan (orchestrator)

Read `references/orchestrator-loop.md` first. Normally invoked by a systemd timer, not by hand.

1. Read `~/workspace/jobs/sources.json`. For each `enabled` source, spawn a subagent to scrape
   the saved-jobs list via `mcp__playwright-golden__*` (`haiku` for Indeed, `sonnet` for
   LinkedIn per its safety protocol). Return the list verbatim with each job's site key.
2. Diff against `tracker.csv` on `(source, key)` parsed from the `url` column. Never dedup on
   company + title: two distinct postings can share a title.
3. For each new job: apply the geographic filter (see `scout`), append at `stage=discovered`,
   run `vet` on the company if it has no `coh_verdict`, then run Stage 1 research and advance
   to `stage=researched`. Synthesize the fit assessment **on the main thread (Opus)**.
4. If more than 8 new jobs appear in one run, research the 8 with the strongest surface fit,
   leave the rest at `discovered`, and **say so explicitly** in the summary. Never silently cap.
5. Commit and push the jobs repo. Append a run line to `orchestrator.log`.
6. Print a one-screen summary: jobs added, fit read on each, obvious misfits worth pruning.

### `scout [--minutes N] [--max M]` — Coherence-driven discovery

Find open roles at high-coherence, high-ceiling companies by searching for the **companies
first and the roles second**. Method and calibration live in the private repo:
`~/workspace/jobs/strategy/coherence-instrument.md` ("Tier 1 inverted") and
`references/coherence-pipeline.md` here. Default time box 10 minutes, ~25 tool calls, max 15
hits. Runs as one `sonnet` subagent with `WebSearch`/`WebFetch`; no browser.

1. Read the target role profile (`~/workspace/jobs/strategy/leadership-search.md`, "Target Role
   Profile") and the **geographic filter** below.
2. Build a candidate list of 10-15 companies from the five inversion signals: public handbook /
   RFC / postmortem archive; founder-led 7+ years, no PE event, revenue coupled to output;
   Glassdoor CEO approval ≥ 90% at n ≥ 100; inverse-Conway language on the engineering blog;
   Westrum/DORA vocabulary with a mechanism attached. Exclude every company already in
   `tracker.csv` (any stage) and any company with a 2025-26 layoff on layoffs.fyi.
3. For each candidate, one ATS-restricted search (`site:greenhouse.io OR site:ashbyhq.com OR
   site:lever.co "<company>" "engineering manager" OR "director of engineering" OR "head of
   engineering"`) or one careers-page fetch. Open the posting and read the **location line**.
4. **Geographic filter, hard.** Keep only roles that are Remote (United States) or located in
   the San Francisco Bay Area (hybrid is fine). Discard, without adding to the tracker, any role
   whose location line names another country or time zone, another US metro as in-office, or
   "Remote (Canada/UK/EU)" twins. Greenhouse often posts one role per country: pick the US one.
   If the location is ambiguous, keep it and flag it; the vet step reads the posting again.
5. Add each surviving role to `tracker.csv` at `stage=discovered` with the id pattern
   `<company>-<role-slug>`, `date_found=today`, and a note `Found by scout <date>: <signals hit>`.
   Then run `vet` on each new company (below). Never silently cap: if the time box ended with
   candidates unchecked, say which.
6. Print: hits table (company, signals, role, location, URL, vet verdict), candidates checked
   with no matching role, and a two-line method note (what found the hits, what was noise).

### `vet <company | id | --all-unvetted>` — Tier-1 coherence read

Score a company on the organizational-coherence instrument from summary pages only, and write
the result to the tracker's `coh_cell`, `coh_derivative`, `coh_verdict`, `coh_date` columns.
The instrument is in the private repo, `~/workspace/jobs/strategy/coherence-instrument.md`
(the "Tier 1: the fast filter" section); scored cases and calibration in `coherence-cases.md`.

1. Spawn one `sonnet` subagent per company, in parallel, at most **12-15 per session** (the
   WebSearch quota is per session and shared). Each reads the Tier 1 section, uses
   `WebSearch`/`WebFetch` only, caps at ~20 calls, records every number with its n, and returns
   the tier-1 report block. If WebSearch is quota-refused, the agent falls back to a playwright
   browser driving `https://duckduckgo.com/html/?q=` (two servers, so two agents at a time).
   No LinkedIn, no review scraping.
2. The main thread re-derives the verdict under the instrument's rules (n floors, windowed
   flags, growth absorption, Blind gap, seed read for small companies) and writes the columns
   plus a one-line note. Verdicts: `Advance`, `Price`, `Pass`, `Unknown`.
3. `Pass` rows at `discovered` through `applied`: set `stage=withdrawn` with the note
   `coherence Pass`. Rows at `interviewing` or `offer` keep their stage; write the verdict and
   note only, and flag it in the summary for the user. `Unknown` rows keep the
   seed read in the note. `Advance` rows are the candidates for `add`.
4. Append the report to `~/workspace/jobs/strategy/coherence-cases.md` under a dated heading,
   and commit.

### `pipeline` — Scout, vet, and prep Advance rows end to end

One command: `scout` → `vet` on every new company → `add` (Stages 1-6) for every row whose
verdict is `Advance` and whose posting is live. Stops before any submission, as always. See
`references/coherence-pipeline.md` for the runbook and the expected shape of a run.

### `liveness` — Weekly liveness sweep + saved-list sync (orchestrator)

Read `references/orchestrator-loop.md` first. Normally invoked by a systemd timer.

1. **Liveness.** For each tracker row at `discovered` through `applied`, fetch the posting and look for **explicit on-page closure text** ("no
   longer accepting applications", "position has been filled", "posting has expired").
   - Closure text found → `stage=closed`, record the phrase and date in `notes`.
   - Loads normally → no change; clear any inconclusive counter.
   - 404 / timeout / redirect / unparseable → **inconclusive**. Increment a counter in
     `notes`, leave `stage` untouched, retry next week. Never archive on a status code.
   - Inconclusive 4 weeks running → surface in the summary for a human decision, still no
     auto-archive.
   - Rows at `interviewing` or `offer` are **never touched**; if their posting looks closed,
     say so in the summary and leave the stage alone. A closed posting during an active process
     usually means the req was filled by the candidate in it.
2. **Sync.** Reconcile each writable source's saved list to match the tracker (mapping table in
   `orchestrator-loop.md`). Rows at `rejected` / `withdrawn` / `closed` get archived on the
   source site. **LinkedIn writes are governed by `linkedin-safety.md` §7**: archive/un-save
   only, max 10 per session counting double against the page budget, abort to read-only on any
   anomaly. If more than 10 need syncing, do 10 and leave the rest for next week.
3. Commit and push. Append a run line to `orchestrator.log`.
4. Print a summary: closed, still open, inconclusive, sync writes performed.

### `watch setup` — Install the orchestrator timers

1. Create `~/workspace/jobs/sources.json` if absent (template in `references/orchestrator-loop.md`).
2. Run `~/workspace/agent-tools/skills/job-search/scripts/install-orchestrator.sh`, which
   installs and enables the systemd user timers. `--uninstall` reverses it.
3. Verify with `systemctl --user list-timers 'job-search-*'`.
4. Tell the user about `loginctl enable-linger $USER` if they want timers to fire while logged
   out, and that a sleeping machine runs missed jobs on wake (`Persistent=true`).

### `kg` — Knowledge graph operations

Read `references/knowledge-graph.md` for full setup, ingestion, and query guidance.

- `kg setup` — Start ArcadeDB and run first ingestion
- `kg ingest` — Re-ingest after a new LinkedIn export: `python3 ~/workspace/agent-tools/skills/job-search/scripts/ingest_linkedin.py --me-name "Your Name"`
- `kg query <company>` — Query warmth scores: `python3 ~/workspace/agent-tools/skills/job-search/scripts/query_connections.py "<Company>"`
- `kg status` — Check container/heartbeat/idle-timer state: `~/workspace/agent-tools/skills/job-search/scripts/arcadedb_ctl.sh status`
- `kg stop` — Stop ArcadeDB now: `~/workspace/agent-tools/skills/job-search/scripts/arcadedb_ctl.sh stop`

The `ingest`/`query` scripts start the container on demand and refresh an idle
heartbeat, so do NOT run `docker compose up` by hand. An idle-reaper systemd timer
stops the 2GB-heap container after 3h of no use, so it never gets left running.
See `references/knowledge-graph.md` → "Lifecycle".

### `status` — View pipeline

1. Read `tracker.csv`
2. Display as a formatted markdown table
3. For each active job (not in a terminal state), indicate the next action needed

### `update <id> <stage>` — Manually update stage

1. Read `tracker.csv`, find the row, update `stage` and `date_updated`
2. If `stage=applied`, also set `date_applied`
3. Commit and push: `git add tracker.csv && git commit -m "Update <id> stage to <stage>" && git push`

### `sync` — Pull both repos to current device

```bash
cd ~/workspace/job-search && git pull --rebase
cd ~/workspace/resume && git fetch --all --prune && git pull --rebase
```

Print tracker state after sync.

### `init` — Bootstrap a new job search repo

Create a fresh job search directory from scratch.

1. `mkdir -p ~/workspace/job-search && cd ~/workspace/job-search && git init`
2. Create tracker with headers:
   ```bash
   echo "id,company,role,url,stage,resume_branch,role_branch,application_url,referral_contact,referral_status,date_found,date_applied,date_updated,notes,coh_cell,coh_derivative,coh_verdict,coh_date" > tracker.csv
   ```
3. Create directories: `mkdir -p jobs data/linkedin`
4. Create `CLAUDE.md`:
   ```markdown
   # Job Search Pipeline

   ## Key Paths
   - **Tracker**: `~/workspace/jobs/tracker.csv`
   - **Resume repo**: `~/workspace/resume/`
   - **Job research**: `~/workspace/jobs/applications/<id>/`

   ## LinkedIn Safety — CRITICAL
   See the `job-search` skill's `references/linkedin-safety.md` for full protocol.

   ## Knowledge Graph (ArcadeDB)
   - **Data**: `data/linkedin/` (Connections.csv, Messages.csv, Positions.csv, Education.csv)
   - **Setup & scripts**: Run `/job-search kg setup`
   - **Query**: `python3 ~/workspace/agent-tools/skills/job-search/scripts/query_connections.py "<Company>"`
   - **Ingest**: `python3 ~/workspace/agent-tools/skills/job-search/scripts/ingest_linkedin.py --me-name "Your Name"`
   ```
5. Create `profile.md` with the template in the `setup` sub-command below
6. Initial commit: `git add -A && git commit -m "Initialize job search pipeline"`
7. Create private GitHub repo and push:
   ```bash
   gh repo create job-search --private --source=. --push
   ```
8. Print next steps:
   ```
   Job search repo initialized at ~/workspace/job-search

   Next steps:
   1. /job-search setup     — configure browser automation
   2. /job-search kg setup  — set up connection knowledge graph
   3. /job-search add <url> — start processing jobs
   ```

### `setup` — Configure browser automation

1. Run `/playwright-docker setup` to configure Dockerized Playwright (recommended). If the
   user cannot or does not want Docker, fall back to browsermcp — see `references/browser-setup.md`.
2. Verify by calling `browser_navigate` to `https://google.com` and confirming `browser_snapshot` returns content.
3. Create `~/workspace/jobs/profile.md` if it doesn't exist:
   ```markdown
   # Application Profile

   Personal details for pre-filling job application forms.

   ## Contact & Links

   | Field | Value |
   |---|---|
   | Full name | |
   | Email | |
   | Phone | |
   | Location | |
   | Current company | |
   | LinkedIn | |
   | GitHub | |
   | Website | |

   ## Work Authorization

   - Authorized to work in the US: **Yes/No**
   - Requires sponsorship now or in the future: **Yes/No**

   ## EEO (voluntary)

   - Gender:
   - Race:
   - Veteran status:
   ```
4. Ask the user to fill in their details (or confirm existing ones)

## CSV Read/Write

**Always use Python for CSV operations** to handle quoting correctly:

```bash
# Read and display tracker
python3 -c "
import csv
with open('tracker.csv') as f:
    for row in csv.DictReader(f): print(dict(row))
"
```

```bash
# Add a row
python3 -c "
import csv
row = {'id':'PLACEHOLDER','company':'PLACEHOLDER','role':'','url':'','stage':'discovered',
       'resume_branch':'','role_branch':'','application_url':'','referral_contact':'',
       'referral_status':'','date_found':'TODAY','date_applied':'','date_updated':'TODAY','notes':''}
with open('tracker.csv','a',newline='') as f:
    csv.DictWriter(f,fieldnames=list(row)).writerow(row)
"
```

```bash
# Update a field
python3 -c "
import csv
rows=[]
with open('tracker.csv') as f:
    r=csv.DictReader(f); fields=r.fieldnames
    for row in r:
        if row['id']=='TARGET_ID': row['stage']='NEW_STAGE'; row['date_updated']='TODAY'
        rows.append(row)
with open('tracker.csv','w',newline='') as f:
    w=csv.DictWriter(f,fieldnames=fields); w.writeheader(); w.writerows(rows)
"
```

## Application Form Defaults

Personal details for pre-filling application forms live at `~/workspace/jobs/profile.md`.
Read that file before filling any form. **NEVER put personal details anywhere in this public
skill — not SKILL.md, not scripts, not assets** (see the repo `AGENTS.md`). Pass them in at
runtime (flags / env / read from the private profile) instead.

### Form-Filling Strategy

1. **Resume upload**: Playwright Docker: `browser_file_upload` with `/home/pwuser/resume/resume.pdf`. browsermcp: prompt the user to upload manually.
2. **"Apply with LinkedIn"**: Worth trying — can prefill name/email/phone/location/LinkedIn. OAuth popup may fail; fall back to manual entry.
3. **Dropdowns**: Lever's combobox dropdowns don't work with `browser_select_option`. Use click → ArrowDown → Enter. Standard HTML `<select>` (e.g., EEO fields) work with `browser_select_option`.
4. **Location autocomplete**: Type city name only (e.g., "Portland"), wait for suggestions, ArrowDown + Enter. Full "City, State" often clears on blur.
5. **Stale refs**: After each `browser_type` or `browser_click`, refs update. Always use refs from the most recent snapshot. Fill fields sequentially.

## Important Rules

1. **Run end-to-end without pausing.** The user reviews everything after the pipeline completes.
2. **CAPTCHA = STOP.** If any `browser_snapshot` or `browser_screenshot` reveals a CAPTCHA, security challenge, "unusual activity" warning, or bot-detection interstitial on ANY site (LinkedIn, Glassdoor, Greenhouse, Lever, Workday, etc.): immediately stop all browser automation, navigate to `google.com`, and ask the user to resolve it via noVNC (http://localhost:6080/vnc.html). Wait for confirmation before resuming. Never attempt to solve or bypass a captcha. This is the ONE exception to "run without pausing."
3. **Route research correctly (see "Research Routing").** All research runs as Claude
   subagents via the Agent tool, spawned in parallel. LinkedIn, Glassdoor, Indeed, and
   application forms additionally need the authenticated `playwright-golden` session.
   **Never point a fresh, unauthenticated browser at those sites** — it trips bot detection
   and risks the user's accounts.
4. **LinkedIn safety is non-negotiable.** Read `references/linkedin-safety.md` before any LinkedIn browsing.
5. **Never automate** connection requests, messages, or application submissions on LinkedIn.
6. **Always read `resume/CONTEXT.md`** before modifying resume content.
7. **Use `_publish`** after every resume edit, and commit the generated artifacts.
8. **Always push both repos** at the end of a pipeline run.
9. **Draft application responses** for any written questions. Anything the user sends verbatim
    (application answers, cover letters, outreach replies) must be copy-pasteable as-is: no `>`
    blockquote indentation, no hard-wrapped lines inside the draft. See Stage 4.
10. **Never submit applications automatically.** Fill everything, then stop. User clicks Submit.
    This holds for the unattended orchestrator loop too: its authority ends at discovery,
    research, tracker state, and saved-list bookkeeping.
11. **Active processes are hands-off.** No sub-command, timer, or agent changes the stage of a
    row at `interviewing` or `offer`. Liveness, geography, and coherence verdicts write notes
    and columns on those rows and surface them; only the user moves them. Rows at `discovered`
    through `applied` may be auto-closed or withdrawn by the rules above.
12. **Geographic filter.** Roles must be Remote (United States) or in the San Francisco Bay
    Area. Anything requiring residence in another country or time zone, or in-office in another
    US metro, is closed at discovery with a note, never researched. Read the location line of
    the actual posting, not the aggregator's.
13. **No PII anywhere in this public skill** (SKILL.md, scripts, assets — the whole repo). All
    personal details live in the private job-search repo (`~/workspace/jobs/`, incl. `profile.md`)
    and are passed to scripts at runtime via flags or env vars. See the repo `AGENTS.md`.
