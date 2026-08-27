# Coherence Pipeline: discovery, vetting, application

The end-to-end loop for finding roles at organizations worth working for, deciding which are,
and preparing the applications. Three stages, each a sub-command, chained by `pipeline`.

```
scout  ──►  vet  ──►  add (Stages 1-6)  ──►  user applies
 find        score      research, resume,      (never automated)
 companies   tier 1     form, responses,
 first       verdict    connections
```

The framework itself (definition, mechanism, the eight dimensions, the probes) lives in the
user's private repo, `~/workspace/jobs/strategy/coherence.md`; the runnable instrument in
`coherence-instrument.md`; the scored cases in `coherence-cases.md`. This file is the operating
procedure. It carries no personal data.

## Why companies first

Searching by job title returns every open req at every company and leaves the quality judgment
to the resume-tailoring stage, which is the expensive one. Searching for companies that produce
the artifacts of a coherent organization (a public handbook, an RFC process, a postmortem archive,
a founder still in the seat, revenue that depends on the product) and only then looking for a
matching req inverts that. The first run found six companies with nine matching roles in ten
minutes and fifteen tool calls; three read Advance at vetting, against roughly one in five from
the organic inflow.

The inversion is a candidate generator, not a verdict. One company hit the artifact signals
perfectly and read *extraction* on its employees at vetting. Every hit gets vetted.

## Kick-off

```
/job-search pipeline
```

or the stages separately:

```
/job-search scout --minutes 10 --max 15
/job-search vet --all-unvetted
/job-search add <url>          # for each Advance row with a live posting
```

## Stage 1: scout

Inputs: the role profile (titles, seniority, domain lean) and the geographic filter. Output:
tracker rows at `discovered` with a scout note, and a hits table.

Rules that matter:
- **Geography is a hard filter at the posting's own location line.** Remote (US) or the
  configured metro. Greenhouse posts one req per country; take the right one. Aggregators lie
  about location; the posting does not.
- **Exclude the tracker** (any stage) and companies with a layoff in the last 18 months.
- **Time box.** Ten minutes and ~25 calls. Candidate selection is nearly free (the artifact
  signals are memorable); the budget goes to "is there an open req right now."
- **ATS-restricted search** (`site:greenhouse.io`, `site:ashbyhq.com`, `site:lever.co`) cuts the
  content-marketing noise that a plain "engineering manager <company>" query returns.
- **Never silently cap.** Say which candidates were left unchecked.

## Stage 2: vet

Inputs: company name. Output: `coh_cell`, `coh_derivative`, `coh_verdict`, `coh_date` on every
row for that company, a note, and an entry in the cases file.

The tier-1 read is ~30 minutes of summary pages for a person and 7-14 tool calls for an agent:
employee side (Glassdoor with n, Blind as the friction-gated source, the directional rule under
n=30), customer side (Gartner Peer Insights first, G2 with provenance labels second), five
windowed structural flags, a growth-absorption check when headcount doubled, turn signals,
self-production artifacts, a seam glance, and a seed read for small companies (founder prior
record, co-founder stability, Wayback team-page diff, round structure, pulled-vs-pushed, req
shape). The instrument specifies all of it; the agent reads that section and follows it.

Verdicts and what happens to the row:
| Verdict | Meaning | Tracker action |
|---|---|---|
| Advance | founder-led or partnership, no shock in window, artifacts at bar | candidate for `add` |
| Price | a shock, an extraction cell, a ceiling gap, or a Blind gap | stays; research only if the role is otherwise compelling; tier 2 before investing |
| Pass | employee side unhappy plus two or more flags | `withdrawn`, note `coherence Pass` |
| Unknown | no employee sample, seed read recorded | stays; the seed note is the next step |

Batch limit: 12-15 companies per session (shared WebSearch quota). Browser fallback exists.

## Stage 3: add, for Advance rows

The existing pipeline, Stages 1-6 in `SKILL.md`. Three things the coherence pass feeds into it:
- **Confirm the posting is live and US-eligible before Stage 2.** Two of the first run's nine
  hits were dead links; one was Berlin-only. Fetch the posting, read the location line.
- **The tier-2 Glassdoor capture is the loop-question source.** The negative tail names the
  mechanism to ask about (how expectations are written before a review, how comp changed, what
  happened the last time someone pushed back, how often teams re-form). Put those in
  `connections.md` so they travel with the outreach.
- **Watch items.** A closed req that was the better fit (reports to a founder, AI-native, public
  artifacts) goes in the tracker as `closed` with a watch note and gets mentioned in outreach.

## Shape of a run

From the first full run (one afternoon):
- scout: 6 companies, 9 roles, 15 calls
- vet: 3 Advance, 3 Price, 0 Pass, 0 Unknown
- add: of the 3 Advance companies, 1 live and eligible posting; 1 dead link, 1 wrong geography,
  1 phantom req (existed, closed). One full application package produced, ready to apply, with a
  connections map of 55 second-degree contacts and three bridges.

The lesson for the next run is in the geographic filter and the "confirm live" step above.
