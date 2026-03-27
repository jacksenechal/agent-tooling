---
name: job-search
description: >
  Job application pipeline management. Process LinkedIn job URLs, tailor resumes,
  prep applications, find referral connections, and track pipeline status.
  Triggers on: job URLs, "apply to", "tailor resume for", "find connections at",
  "job tracker", "application status", "job search", or any job pipeline tasks.
---

# Job Search Pipeline Skill

You are managing the user's job application pipeline. This skill orchestrates the full
workflow from LinkedIn job URL to ready-to-apply state.

**Run the entire pipeline end-to-end without stopping for user confirmation.** The user
will review artifacts after the run completes. The goal is: user provides a LinkedIn URL,
walks away, and comes back to a fully prepared application package.

## Project Locations

- **Job search repo**: `~/workspace/job-search/` (private GitHub repo)
- **Tracker**: `~/workspace/job-search/tracker.csv`
- **Job research**: `~/workspace/job-search/jobs/<id>/`
- **Resume repo**: `~/workspace/resume/` (separate git repo)
- **LinkedIn safety rules**: See `references/linkedin-safety.md` — READ THIS before any LinkedIn browsing

## Sub-Commands

### `add <linkedin-url>` — Process a new job

Walk through the full pipeline for a new job posting. Run all stages end-to-end without
pausing for user input. Each stage updates the tracker CSV.

**Stage 1: Discover & Research**

1. Generate an `id` slug from the company and role (e.g., `stripe-infra-eng`, `aircall-ai-productivity-eng`). Keep it short, semantic, and unique against existing tracker rows. Do NOT ask the user to confirm — just pick a good one.
2. Create directory `~/workspace/job-search/jobs/<id>/`
3. Add a row to `tracker.csv` with `stage=discovered`, `date_found` = today
4. Scrape the job posting:
   - **Use browsermcp `browser_snapshot` as the primary method.** Navigate to the LinkedIn URL
     following the safety protocol, then `browser_snapshot` to capture the full accessibility tree.
     This returns complete, verbatim text — every section, bullet, comp, benefits — with no
     summarization. It also captures external application URLs (e.g., Lever, Greenhouse links)
     and hiring team info that WebFetch misses.
   - `WebFetch` is a fallback only — it summarizes content despite instructions not to, and
     misses application URLs and hiring team details.
   - Parse out: company name, role title, full job description, external application URL
     (if present), location, requirements, **hiring team members** (names, titles, degree of connection)
5. Save the full job description to `jobs/<id>/job-posting.md` with this structure:
   ```markdown
   # <Company> — <Role>

   **URL**: <linkedin-url>
   **Application URL**: <external-url-if-found>
   **Location**: <location>
   **Date Found**: <today>

   ## Hiring Team
   - <name> — <title> (<connection degree>)
   - ...

   ## Job Description
   <full description — verbatim from snapshot, not summarized>

   ## Key Requirements
   <bulleted list of requirements extracted from description>

   ## Notes
   <any initial observations about fit, concerns, etc.>
   ```
6. Update tracker: fill in `company`, `role`, `application_url`, advance `stage` to `researched`

**Stage 2: Tailor Resume**

1. `cd ~/workspace/resume`
2. `git fetch --all --prune`
3. List remote branches (`git branch -r`) to find the closest `role/` archetype branch.
   Pick the best match based on the job description — do not ask the user.
4. Create branch `job/<id>` from the chosen base: `git checkout -b job/<id> origin/<base-branch>`
5. Read `CONTEXT.md` — respect all factual constraints
6. Read `resume.md` and the saved job description from `jobs/<id>/job-posting.md`
7. Tailor `resume.md`:
   - Adjust the Summary to emphasize relevant experience
   - Reorder and emphasize Professional Experience bullets
   - Update Skills section to match job requirements
   - Compress less-relevant experience
   - Keep ATS-friendly formatting (see `resume/AGENTS.md`)
8. Run `./_publish` to generate HTML and PDF
9. `git add -A && git commit -m "Tailor resume for <company> <role>"`
10. Push the resume branch: `git push -u origin job/<id>`
11. Open PDF: `xdg-open resume.pdf`
12. Update tracker: `resume_branch=job/<id>`, `role_branch=<base>`, advance `stage` to `resume_tailored`

**Stage 3: Prep Application**

1. If `application_url` exists in tracker:
   - `WebFetch` the application page
   - If it's a job board (Greenhouse, Lever, Workday, etc.), document all form fields
2. If no `application_url`:
   - Use browsermcp to navigate to the LinkedIn job page (following safety protocol)
   - Look for "Apply" button and identify where it leads
   - If external, capture the URL and fetch that page
3. Save to `jobs/<id>/application-form.md`:
   ```markdown
   # Application Form — <Company> <Role>

   **Application URL**: <url>
   **Platform**: <Greenhouse/Lever/Workday/Custom/LinkedIn Easy Apply>

   ## Required Fields
   - <field name>: <type> — <notes>
   - ...

   ## Optional Fields
   - ...

   ## Questions / Essays
   - <question text>
   - ...

   ## Uploads Required
   - Resume (PDF)
   - Cover letter? (yes/no)
   - Other: ...
   ```
4. Update tracker: `application_url` if newly found, advance `stage` to `application_prepped`

**Stage 4: Draft Application Responses**

If the application form includes written questions, essays, or free-text fields (identified
in Stage 3), draft responses for each one.

1. Read `jobs/<id>/application-form.md` for the questions
2. Read `jobs/<id>/job-posting.md` for context on what the company values
3. Read the tailored `resume.md` from the resume branch for the user's background
4. Read `~/workspace/resume/CONTEXT.md` for factual constraints
5. Draft responses that are:
   - Authentic and specific to the user's experience (not generic)
   - Tailored to the role and company
   - Concise but substantive
   - Honest about experience level (per CONTEXT.md constraints)
6. Save to `jobs/<id>/application-responses.md`:
   ```markdown
   # Application Responses — <Company> <Role>

   Ready for review. Edit as needed before submitting.

   ---

   ## Q: <question text>

   <drafted response>

   ---

   ## Q: <next question>

   <drafted response>

   ---
   ```
7. If there are no written questions, create the file with a note: "No written questions on this application."

**Stage 5: Find Connections & Outreach Strategy**

**READ `references/linkedin-safety.md` BEFORE THIS STAGE.**

This stage does a thorough search of the user's network at the company using LinkedIn's
semantic search, then pages through all results to build a complete map before doing
strategic analysis.

#### Step 1: Search connections via semantic query

Use a single conversational search that leverages LinkedIn's semantic search engine to find
both 1st and 2nd degree connections who currently work at the company. Construct the URL:

```
https://www.linkedin.com/search/results/people/?keywords=my%20connections%20who%20currently%20work%20at%20<URL-ENCODED-COMPANY-NAME>&origin=FACETED_SEARCH&network=%5B%22F%22%2C%22S%22%5D
```

Example for "Aircall":
```
https://www.linkedin.com/search/results/people/?keywords=my%20connections%20who%20currently%20work%20at%20aircall&origin=FACETED_SEARCH&network=%5B%22F%22%2C%22S%22%5D
```

The `network` filter restricts to 1st (`F`) and 2nd (`S`) degree. Past 2nd degree is useless.
The semantic query "my connections who currently work at" narrows to current employees, which
is significantly more useful than a plain company name search.

1. Navigate to the search URL (with safety protocol — delay + scroll)
2. `browser_snapshot` to capture results
3. Record every person: name, title, connection degree, mutual connections shown
4. **Page through ALL results**: Look for a "Next" button or pagination. For each additional page:
   - Navigate to `google.com` as breather (wait 2000-3000ms)
   - Navigate to the next page URL (with safety protocol — full delay + scroll)
   - `browser_snapshot` and record all results
   - Continue until no more pages or you hit the **hard cap of 8 LinkedIn page loads** for
     this step (covering ~80 results, which is comprehensive for most companies)
5. **NEVER click into individual profiles** — only read what's visible on search results pages
6. Navigate to `google.com` to end LinkedIn browsing

#### Step 2: Cross-reference with hiring team

Pull in the hiring team members identified in Stage 1 (from `jobs/<id>/job-posting.md`).
Note which hiring team members appeared in the search results and at what degree.

#### Step 3: Strategic analysis and outreach plan

With the complete map of connections, do a deep analysis. For EVERY person found, assess:
- **Relevance**: Are they on the hiring team's org? Adjacent team? Different department?
- **Seniority**: Peer-level IC, senior IC, manager, director, VP?
- **Connection strength**: 1st-degree (direct), or 2nd-degree (who are the mutual connections?)
- **Outreach value**: How likely are they to be able and willing to refer?

Then categorize into tiers:

**Tier 1 — Warm intro through 1st-degree (highest value):**
A 1st-degree connection who can introduce the user or submit a referral. This is almost always
stronger than cold outreach to a 2nd-degree. A message from a mutual carries social proof
and creates obligation to at least look. The mutual can also provide intel on the team,
hiring process, and whether the role is genuinely open.

**Tier 2 — Peer-level ICs on the same or adjacent team (best direct outreach):**
Engineers or ICs at the user's level or one above, on the team the role belongs to or a
neighboring team. They understand the role, can speak credibly about fit, and most companies
give referral bonuses. Peer-to-peer conversation feels natural, not like asking a favor.
These are the best targets for direct outreach if no strong 1st-degree path exists.

**Tier 3 — The hiring manager (high value, handle with care):**
If the hiring manager is visible (e.g., from the Hiring Team section of the job posting),
reaching out can be powerful but framing is critical. Do NOT lead with "I applied for your
role." Lead with genuine curiosity about what they're building — a thoughtful question about
their team's direction. If the conversation goes well, they will often say "you should apply"
or connect the user with recruiting. This is the strongest outcome because it becomes a pull
rather than a push. Only recommend this path if the user can craft an insightful, non-generic opener.

**Tier 4 — Adjacent department (low conversion, low risk):**
People in other departments (product, other engineering teams). Good for intel-gathering
but unlikely to lead directly to a referral.

When writing the outreach plan:
- **1st-degree connections**: Recommend asking them casually about the role and whether
  they'd be comfortable making an intro or submitting a referral.
- **2nd-degree connections**: Recommend conversational openers — never ask for a referral
  in the first message. Lead with interest in their work or the team.
- **Hiring manager**: Only recommend direct outreach if there's a credible angle (shared
  background, specific question about their technical direction). Suggest researching
  anything they've published or spoken about first.
- **Always recommend applying regardless** — don't gate the application on getting a referral.
  The referral is a booster, not a prerequisite. Apply now, work connections in parallel.
- **Rank all recommendations** — don't just pick the top 2-3. Rank every viable connection
  so the user can work down the list.

#### Step 5: Save and update tracker

Save findings to `jobs/<id>/connections.md` (see template below). Update tracker:
`referral_contact` with top recommendation, `referral_status=identified`, advance `stage`
to `connections_found`.

#### connections.md Template

```markdown
# Connections at <Company>

## 1st Degree Connections
- <name> — <title>
- ...

(or "None found" if empty)

## 2nd Degree Connections (complete list)
- <name> — <title> | Mutual: <mutual connection names>
- <name> — <title> | Mutual: <mutual connection names>
- ...

(<N> total across <M> pages of results)

## Hiring Team (from job posting)
- <name> — <title> (<connection degree, if found in search>)

## Outreach Strategy

### Recommended Actions (ranked by priority)

**1. [Tier] [Approach]: [Name] — [Title]**
- Why: <why this person is a high-value target — team relevance, seniority fit, mutual strength>
- Approach: <specific suggested approach — what to say, how to frame it>
- Draft message:
  > <a short, natural-sounding message the user can copy and adapt>

**2. [Tier] [Approach]: [Name] — [Title]**
- Why: ...
- Approach: ...
- Draft message:
  > ...

(continue for ALL viable connections, ranked — not just top 3)

### Strategic Summary
- Best path to referral: <1-2 sentence summary of the strongest play>
- Backup paths: <alternative approaches if the primary doesn't pan out>
- Key insight: <any non-obvious observation — e.g., "3 mutual connections with Person X
  suggests a strong tie worth leveraging", "hiring manager previously worked at Company Y
  where the user also worked", "no strong 1st-degree path — peer outreach is the best bet">
- Reminder: Apply regardless. Referral is a booster, not a gate.
```

**Stage 6: Finalize & Push**

1. Verify all artifacts exist:
   - `jobs/<id>/job-posting.md`
   - `jobs/<id>/application-form.md`
   - `jobs/<id>/application-responses.md`
   - `jobs/<id>/connections.md`
   - Resume PDF on branch `job/<id>`
2. Update tracker: advance `stage` to `ready_to_apply`
3. Commit and push everything in the job-search repo:
   ```bash
   cd ~/workspace/job-search
   git add -A
   git commit -m "Add <company> <role> application package"
   git push
   ```
4. Ensure resume branch was pushed (should have been in Stage 2, but verify):
   ```bash
   cd ~/workspace/resume
   git push -u origin job/<id>
   ```
5. Print a final summary:
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

### `status` — View pipeline

1. Read `tracker.csv`
2. Display as a formatted markdown table
3. For each active job (not in a terminal state), indicate the next action needed

### `update <id> <stage>` — Manually update stage

1. Read `tracker.csv`
2. Find the row matching `<id>`
3. Update `stage` to the new value
4. Update `date_updated` to today
5. If stage is `applied`, set `date_applied` to today
6. Write back to CSV
7. Commit and push:
   ```bash
   cd ~/workspace/job-search
   git add tracker.csv
   git commit -m "Update <id> stage to <stage>"
   git push
   ```

### `sync` — Pull both repos to current device

Pull the latest state of both repos so work can resume from any machine.

```bash
# Pull job-search repo
cd ~/workspace/job-search
git pull --rebase

# Pull resume repo (fetch all branches including job/* branches)
cd ~/workspace/resume
git fetch --all --prune
git pull --rebase
```

Print a summary of current tracker state after sync.

## CSV Read/Write

**Always use Python for CSV operations** to handle quoting correctly:

```bash
# Read and display tracker
python3 -c "
import csv, sys
with open('~/workspace/job-search/tracker.csv') as f:
    reader = csv.DictReader(f)
    for row in reader:
        print(dict(row))
"
```

```bash
# Add a row
python3 -c "
import csv
row = {
    'id': 'PLACEHOLDER',
    'company': 'PLACEHOLDER',
    # ... fill all fields
}
with open('~/workspace/job-search/tracker.csv', 'a', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=['id','company','role','url','stage','resume_branch','role_branch','application_url','referral_contact','referral_status','date_found','date_applied','date_updated','notes'])
    writer.writerow(row)
"
```

```bash
# Update a field in an existing row
python3 -c "
import csv
rows = []
with open('~/workspace/job-search/tracker.csv') as f:
    reader = csv.DictReader(f)
    fieldnames = reader.fieldnames
    for row in reader:
        if row['id'] == 'TARGET_ID':
            row['stage'] = 'NEW_STAGE'
            row['date_updated'] = 'TODAY'
        rows.append(row)
with open('~/workspace/job-search/tracker.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=fieldnames)
    writer.writeheader()
    writer.writerows(rows)
"
```

## Application Form Defaults

Personal details for pre-filling application forms are stored in the **private** job-search
repo at `~/workspace/job-search/profile.md`. Read that file before filling any
application form. It contains contact info, links, work authorization, EEO responses, and
other standard fields.

**NEVER put personal details in this skill file** — it lives in a public repo.

### Form-Filling Strategy with browsermcp

1. **Resume upload**: browsermcp cannot do file uploads. Prompt the user to upload
   `resume.pdf` from the resume branch manually.
2. **"Apply with LinkedIn" button**: If present on a Lever/Greenhouse form, clicking this
   can prefill name, email, phone, location, company, and LinkedIn URL — saving significant
   time. However, it triggers an OAuth popup that may not work reliably through browsermcp.
   Worth trying first; fall back to manual field entry if it fails.
3. **Dropdowns**: Lever's custom location dropdown doesn't work with `browser_select_option`.
   Use the click-then-ArrowDown-key approach instead (click the combobox, press ArrowDown to
   select the desired option). Standard HTML `<select>` elements (like EEO dropdowns) do
   work with `browser_select_option` using the visible option text as the value.
4. **Location autocomplete**: Lever's location field is a Google Places autocomplete. Type
   the city name only (e.g., "Portland"), wait for suggestions to load, then press ArrowDown
   and Enter to select.
5. **Stale refs**: After each `browser_type` or `browser_click`, the page snapshot refs
   update. Always use refs from the most recent snapshot — parallel field fills will fail
   with stale ref errors. Fill fields sequentially.

## Important Rules

1. **Run end-to-end without pausing.** Do not stop to ask for user confirmation between stages. The user reviews everything after the pipeline completes.
2. **LinkedIn safety is non-negotiable.** Read `references/linkedin-safety.md` before any browsermcp interaction with LinkedIn.
3. **Never automate** connection requests, messages, or application submissions on LinkedIn.
4. **Always read `resume/CONTEXT.md`** before modifying resume content.
5. **Use `_publish`** after every resume edit, and commit the generated artifacts.
6. **Always push both repos** at the end of a pipeline run so work is resumable from any device.
7. **Draft application responses** for any written questions — the user should be able to copy-paste these into the application form with minimal editing.
8. **Never submit applications automatically.** Fill out every field, then stop. The user clicks Submit.
9. **No PII in this skill file.** All personal details live in the private job-search repo (`profile.md`).
