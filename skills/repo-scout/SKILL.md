---
name: repo-scout
description: >
  Rapid codebase situational awareness. Produces a structured ~4-page report with Mermaid
  diagrams covering topology, tech stack, domain vocabulary, entry points, golden-path
  trace, deploy pipeline, architecture sketch, data model, code conventions, trust
  boundaries, risk hotspots, and observability.

  Use this skill whenever you need a fast structural overview of an unfamiliar codebase —
  onboarding to a new team, preparing for a pair coding interview, reviewing a project
  you haven't seen before, doing technical due diligence. Trigger on: "scout this repo",
  "repo overview", "codebase overview", "walk me through this repo", "give me the lay of
  the land", "what am I looking at", "architecture overview", "structural analysis",
  "help me understand this project", "onboard me to this codebase", "first look at this
  code", "repo-scout", "code tour". Also trigger when the user opens a new repo and asks
  broad orientation questions like "where do I start" or "how is this organized".
---

# Repo Scout

Rapid situational awareness for an experienced developer sitting down cold with an
unfamiliar codebase. The report forms the trunk of a knowledge tree — enough to orient,
ask good questions, and know where to dig deeper. Not a deep review or audit; a fast,
consumable structural analysis.

## Arguments

- **repo path** (required) — the repository root to analyze. Defaults to the current
  working directory if not specified.
- **--sections** (optional) — comma-separated list of section names to analyze. Runs all
  sections if omitted.

### Section names

| Phase | Sections |
|-------|----------|
| 1. Orient | `topology`, `stack`, `vocabulary` |
| 2. Trace | `entry-points`, `golden-path`, `deploy` |
| 3. Map | `architecture`, `data-model`, `conventions` |
| 4. Assess | `trust-boundaries`, `dragons`, `observability` |

Example: `--sections topology,golden-path,trust-boundaries`

## How It Works

The report is built in four phases. Each phase spawns up to three parallel haiku
subagents to investigate the codebase, then the main thread synthesizes their raw
findings into polished prose with Mermaid diagrams. This two-stage pattern keeps the
report tight and cross-referenced: subagents do cheap mechanical exploration, the main
thread does the thinking.

Each section targets ~1/3 page of output (~10-15 lines of prose, or a compact
diagram/table with a few lines of commentary). Each phase fills roughly one page.
The whole report should be ~4-5 pages including diagrams.

## Execution

### Step 1: Setup

1. Resolve the repo path (default: current working directory). Verify it exists.
2. Detect the OS: use `uname` to determine `xdg-open` (Linux) vs `open` (macOS).
3. Parse `--sections` if provided. Map each section name to its phase.
4. Read `references/investigation-briefs.md` from this skill's directory.

### Step 2: Run phases

For each phase (1 through 4), skip if no sections from this phase were requested:

**Spawn investigations.** For each section in the phase, spawn a haiku subagent in
a single message (so they run in parallel):

```
Agent({
  model: "haiku",
  subagent_type: "Explore",
  description: "<section-name> investigation",
  prompt: "<the section's brief from investigation-briefs.md, with REPO_PATH
           replaced with the actual repo path>"
})
```

All three subagents for a phase go in one message. They return raw findings with
file:line citations — no polished prose, no opinions.

**Synthesize.** When all subagents return, write the phase's sections using the
synthesis principles below. Each section is ~1/3 page. Add Mermaid diagrams where
the briefs indicate (golden-path, deploy, architecture, data-model).

Keep a running list of "loose threads" — things that surfaced during investigation
that don't fit the current section but might matter in Next Steps.

### Step 3: Write the closing

After all phases, write a "Next Steps" section (~1/2 page):
- Branches worth exploring deeper (module dependency graph, compliance surface,
  state lifecycle, config surface, user journey map)
- Questions to ask team members that the code can't answer
- Connections between sections ("the dragons-map hotspot in `auth/` aligns with
  thin trust-boundary coverage there")
- Anything from the loose-threads list that's worth flagging

### Step 4: Assemble and render

1. Assemble the full report using the template below. The topology investigation
   from Phase 1 provides the stats for the header (file count, LOC, primary language).
2. Write to `REPO-SCOUT.md` in the repo root.
3. Render to HTML:
   ```bash
   python3 <this-skill-directory>/scripts/render_html.py \
     <repo-path>/REPO-SCOUT.md <repo-path>/REPO-SCOUT.html
   ```
4. Open in the system browser:
   ```bash
   xdg-open <repo-path>/REPO-SCOUT.html   # Linux
   open <repo-path>/REPO-SCOUT.html        # macOS
   ```

## Synthesis Principles

These guide how you write each section from raw subagent findings. They exist because
the difference between a useful report and a forgettable one is editorial judgment, and
that's the main thread's job.

**Budget-bounded.** Each section targets ~1/3 page. If findings overflow, that's a
signal — say so ("23 entry points found; 8 most central shown, rest in `src/routes/`")
rather than cramming. Overflow is information about the codebase's complexity.

**File:line receipts.** Every claim cites a location (`src/api/routes.ts:42`). The
reader should be able to jump straight to evidence. A claim without a citation is a
guess — omit it or flag it as uncertain.

**Silent on the boring.** If something is standard and unsurprising ("uses npm"),
say "standard" and move on. The value is in what's unexpected, unusual, or would
trip up a newcomer.

**Inferred, not invented.** Extract facts from the actual code. Never describe what a
framework "typically" does. If the subagent didn't find evidence, say "not found" —
that's more useful than speculation.

**Composable.** Sections reference each other: the golden-path trace might note a trust
boundary from Phase 4, the architecture sketch should be consistent with entry points.
Cross-references turn 12 paragraphs into a connected map.

**Mermaid diagrams.** Use `sequenceDiagram` for golden-path, `graph LR` for deploy
pipeline, `graph TD` for architecture, `erDiagram` for data model. Keep diagrams to
5-12 nodes — a 30-node diagram is worse than prose. Diagrams complement text; they
don't replace it.

**Validate every diagram.** After assembling the full report, extract each mermaid code
block and validate its syntax before writing the file. Run:
```bash
npx -y @mermaid-js/mermaid-cli@latest parse -i /tmp/repo-scout-check.mmd 2>&1
```
for each block (write the block content to a temp `.mmd` file, run the check, read
stderr). Common mistakes: unquoted labels containing special characters (parentheses,
brackets, colons, commas) — wrap them in double quotes. Missing arrow syntax. Colons
in node labels (use `["label: text"]` syntax). If a diagram fails validation, fix the
syntax and re-check until it passes. Only then write REPO-SCOUT.md.

## Report Template

```markdown
# Repo Scout — <repo-name>

> Generated <date> · <total-files> files · <total-loc> LOC · Primary: <language>
> Sections: <all | list of requested sections>

---

## Phase 1: Orient

### Topology
<annotated directory tree, shape description>

### Tech Stack
<categorized tech with versions, unusual choices flagged>

### Domain Vocabulary
<definition list: term — definition (source file:line)>

---

## Phase 2: Trace

### Entry Points
<table: Type | Name | File:Line | Brief>

### Golden Path
<mermaid sequenceDiagram + narrated hops with file:line>

### Deploy Pipeline
<mermaid graph LR + stage descriptions>

---

## Phase 3: Map

### Architecture
<mermaid graph TD + component descriptions>

### Data Model
<mermaid erDiagram + entity descriptions>

### Code Conventions
<categorized patterns with file:line examples>

---

## Phase 4: Assess

### Trust Boundaries
<boundary list with type, location, gaps>

### Dragons
<hotspot list: type, file:line, evidence, severity>

### Observability
<instrumentation inventory, coverage, gaps>

---

## Next Steps
<deeper investigations, questions for team, cross-section connections, loose threads>
```

## Edge Cases

- **Enormous repos (>100k LOC):** Subagents sample rather than exhaustively scan.
  The briefs include file limits (head -2000, first 100 lines, sample 5-10 files).
- **Subagent failure:** Note the gap ("*Section skipped — investigation timed out*")
  and continue. A partial report is still useful.
- **No git history:** Dragons-map skips churn analysis and relies on code markers and
  complexity signals.
- **Small repos (<10 files):** Short report is correct. Don't pad.
- **Non-code repos (docs, data):** The report will be sparse. Note this in the header
  and focus on what's there (directory structure, any scripts, config).
