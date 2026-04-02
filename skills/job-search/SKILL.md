---
name: job-search
description: >
  Job application pipeline management. Process LinkedIn job URLs, tailor resumes,
  prep applications, find referral connections, and track pipeline status.
  Includes LinkedIn connection knowledge graph (ArcadeDB) for warmth-ranked outreach.
  Triggers on: job URLs, "apply to", "tailor resume for", "find connections at",
  "job tracker", "application status", "job search", "knowledge graph", "warmth score",
  "ingest linkedin", or any job pipeline tasks.
---

# Job Search Pipeline Skill

You are managing the user's job application pipeline. This skill orchestrates the full
workflow from LinkedIn job URL to ready-to-apply state.

**Run the entire pipeline end-to-end without stopping for user confirmation.** The user
will review artifacts after the run completes.

## Project Locations

- **Job search repo**: `~/workspace/job-search/` (private GitHub repo)
- **Tracker**: `~/workspace/job-search/tracker.csv`
- **Job research**: `~/workspace/job-search/jobs/<id>/`
- **Resume repo**: `~/workspace/resume/` (separate git repo)
- **LinkedIn safety rules**: See `references/linkedin-safety.md` — READ THIS before any LinkedIn browsing

## Browser Automation

This skill requires an MCP server providing Playwright-style browser tools
(`browser_navigate`, `browser_snapshot`, `browser_click`, `browser_type`, etc.).

- **browsermcp** — Controls the user's real desktop browser. Simplest setup. Cannot do file uploads.
- **Dockerized Playwright + noVNC** — Headless Chromium in Docker. Supports file uploads, persistent LinkedIn sessions. Recommended for full automation.

Run `/job-search setup` to configure. See `references/browser-setup.md` for detailed setup instructions.

## Knowledge Graph

A local ArcadeDB graph of LinkedIn connections ranked by warmth. Used in Stage 5 to
prioritize outreach. Run `/job-search kg setup` to initialize.
See `references/knowledge-graph.md` for setup, schema, warmth algorithm, and query patterns.

## Sub-Commands

### `add <linkedin-url>` — Process a new job

Walk through the full pipeline for a new job posting end-to-end.

**Stage 1: Discover & Research**

1. Generate an `id` slug (e.g., `stripe-infra-eng`, `aircall-ai-eng`). Short, semantic, unique. Do NOT ask the user.
2. Create `~/workspace/job-search/jobs/<id>/`
3. Add row to `tracker.csv`: `stage=discovered`, `date_found=today`
4. Scrape the job posting:
   - **Use `browser_snapshot` as the primary method.** Navigate following the safety protocol, then snapshot to capture the full accessibility tree — verbatim text, application URLs, hiring team. No summarization.
   - `WebFetch` is a fallback only — it summarizes and misses application URLs and hiring team.
   - Parse: company, role, full description, external application URL, location, requirements, hiring team (names, titles, connection degree)
5. Save to `jobs/<id>/job-posting.md`:
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
6. Research company on Glassdoor:
   - Navigate to `https://www.glassdoor.com/Search/results.htm?keyword=<URL-encoded-company-name>` (no LinkedIn safety delays needed — this is not LinkedIn)
   - `browser_snapshot` the search results, click through to the company's Reviews page
   - `browser_snapshot` the Reviews overview to capture: overall rating, CEO approval, "recommend to a friend" %, and the pros/cons summary
   - Scroll down and snapshot to capture more review highlights if available
   - Save to `jobs/<id>/glassdoor.md`:
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
   - If the company isn't found on Glassdoor, note that in `glassdoor.md` and move on
7. Update tracker: `company`, `role`, `application_url`, `stage=researched`

**Stage 2: Tailor Resume**

1. `cd ~/workspace/resume && git fetch --all --prune`
2. List remote branches (`git branch -r`), find the closest `role/` archetype. Do not ask the user.
3. Create branch: `git checkout -b job/<id> origin/<base-branch>`
4. Read `CONTEXT.md` — respect all factual constraints
5. Read `resume.md` and the saved job description
6. Tailor `resume.md`: adjust Summary, reorder/emphasize bullets, update Skills, compress less-relevant experience. Keep ATS-friendly formatting (see `resume/AGENTS.md`)
7. Run `./_publish` to generate HTML and PDF
8. `git add -A && git commit -m "Tailor resume for <company> <role>"`
9. `git push -u origin job/<id>`
10. `xdg-open resume.pdf`
11. Update tracker: `resume_branch=job/<id>`, `role_branch=<base>`, `stage=resume_tailored`

**Stage 3: Prep Application**

1. If `application_url` exists: `WebFetch` the page, identify all form fields
2. If not: use browser tools to find the Apply button and capture the URL
3. Save to `jobs/<id>/application-form.md`:
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

For any written questions or essays identified in Stage 3:

1. Read `jobs/<id>/application-form.md`, `jobs/<id>/job-posting.md`, `jobs/<id>/glassdoor.md`, tailored `resume.md`, and `~/workspace/resume/CONTEXT.md`
2. Draft responses: specific to the user's experience, tailored to role and company, concise, honest per CONTEXT.md constraints
3. Save to `jobs/<id>/application-responses.md` with each question clearly labeled. If no written questions, note that.

**Stage 5: Find Connections & Outreach Strategy**

**READ `references/linkedin-safety.md` BEFORE THIS STAGE.**

#### Step 1: Search connections via semantic query

Use a single conversational search that finds 1st and 2nd degree connections at the company:

```
https://www.linkedin.com/search/results/people/?keywords=my%20connections%20who%20currently%20work%20at%20<URL-ENCODED-COMPANY>&origin=FACETED_SEARCH&network=%5B%22F%22%2C%22S%22%5D
```

1. Navigate (with safety protocol — delay + scroll), `browser_snapshot`, record every person: name, title, degree, mutual connections
2. **Page through ALL results**: For each additional page, navigate via `google.com` breather, snapshot and record all results. Continue until no more pages or **hard cap of 8 LinkedIn page loads** for this step.
3. **NEVER click into individual profiles**
4. Navigate to `google.com` to end LinkedIn browsing

#### Step 2: Pull warmth scores from Knowledge Graph

```bash
python3 ~/workspace/agent-tools/skills/job-search/scripts/query_connections.py "<Company Name>"
```

Returns 1st-degree connections at the company ranked by warmth score. See `references/knowledge-graph.md` for score interpretation and setup. If the KG hasn't been set up, skip this step and note it in the output.

#### Step 3: Cross-reference with hiring team

Pull hiring team from `jobs/<id>/job-posting.md`. Note which members appeared in search results and at what degree.

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

Save to `jobs/<id>/connections.md` using the template in `references/knowledge-graph.md`.
Update tracker: `referral_contact` with top recommendation, `referral_status=identified`, `stage=connections_found`.

**Stage 6: Finalize & Push**

1. Verify all artifacts exist: `job-posting.md`, `glassdoor.md`, `application-form.md`, `application-responses.md`, `connections.md`, resume PDF on branch `job/<id>`
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
   Research: job-search/jobs/<id>/

   Files to review before applying:
   - jobs/<id>/application-responses.md  (edit your written answers)
   - resume.pdf                          (on branch job/<id>)

   Both repos pushed to GitHub — resume from any device with /job-search sync
   ```

### `kg` — Knowledge graph operations

Read `references/knowledge-graph.md` for full setup, ingestion, and query guidance.

- `kg setup` — Start ArcadeDB and run first ingestion
- `kg ingest` — Re-ingest after a new LinkedIn export: `python3 ~/workspace/agent-tools/skills/job-search/scripts/ingest_linkedin.py --me-name "Your Name"`
- `kg query <company>` — Query warmth scores: `python3 ~/workspace/agent-tools/skills/job-search/scripts/query_connections.py "<Company>"`
- `kg status` — Check if ArcadeDB is running and populated

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
   echo "id,company,role,url,stage,resume_branch,role_branch,application_url,referral_contact,referral_status,date_found,date_applied,date_updated,notes" > tracker.csv
   ```
3. Create directories: `mkdir -p jobs data/linkedin`
4. Create `CLAUDE.md`:
   ```markdown
   # Job Search Pipeline

   ## Key Paths
   - **Tracker**: `~/workspace/job-search/tracker.csv`
   - **Resume repo**: `~/workspace/resume/`
   - **Job research**: `~/workspace/job-search/jobs/<id>/`

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

Read `references/browser-setup.md` for full setup instructions, then:

1. Ask the user: **browsermcp** (simpler, no file uploads) or **Dockerized Playwright + noVNC** (full automation, requires Docker)?
2. Walk through setup from the reference doc for their chosen option
3. Verify by calling `browser_navigate` to `https://google.com` and confirming `browser_snapshot` returns content
4. If Docker: confirm noVNC accessible at http://localhost:6080
5. Create `~/workspace/job-search/profile.md` if it doesn't exist:
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
6. Ask the user to fill in their details (or confirm existing ones)

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

Personal details for pre-filling application forms live at `~/workspace/job-search/profile.md`.
Read that file before filling any form. **NEVER put personal details in this skill file.**

### Form-Filling Strategy

1. **Resume upload**: Dockerized Playwright: `browser_file_upload` with `/home/pwuser/resume/resume.pdf`. browsermcp: prompt the user to upload manually.
2. **"Apply with LinkedIn"**: Worth trying — can prefill name/email/phone/location/LinkedIn. OAuth popup may fail; fall back to manual entry.
3. **Dropdowns**: Lever's combobox dropdowns don't work with `browser_select_option`. Use click → ArrowDown → Enter. Standard HTML `<select>` (e.g., EEO fields) work with `browser_select_option`.
4. **Location autocomplete**: Type city name only (e.g., "Portland"), wait for suggestions, ArrowDown + Enter. Full "City, State" often clears on blur.
5. **Stale refs**: After each `browser_type` or `browser_click`, refs update. Always use refs from the most recent snapshot. Fill fields sequentially.

## Important Rules

1. **Run end-to-end without pausing.** The user reviews everything after the pipeline completes.
2. **LinkedIn safety is non-negotiable.** Read `references/linkedin-safety.md` before any LinkedIn browsing.
3. **Never automate** connection requests, messages, or application submissions on LinkedIn.
4. **Always read `resume/CONTEXT.md`** before modifying resume content.
5. **Use `_publish`** after every resume edit, and commit the generated artifacts.
6. **Always push both repos** at the end of a pipeline run.
7. **Draft application responses** for any written questions.
8. **Never submit applications automatically.** Fill everything, then stop. User clicks Submit.
9. **No PII in this skill file.** All personal details live in the private job-search repo.
