# AGENTS.md — agent-tools

Guidance for agents working anywhere in this repo.

## This is a public, general-purpose repo — no personal data

`agent-tools` (skills, scripts, assets, docs) is meant to be general-purpose and shareable. It
must contain **no personally identifiable information (PII)** and no user-specific details:

- No names, emails, phone numbers, addresses, LinkedIn/GitHub handles, employer names, or other
  personal facts — not in SKILL.md files, not in scripts, not in assets, not in comments or
  example commands.
- Scripts must take personal values at runtime: a flag (e.g. `--name`), an environment variable
  (e.g. `$JOB_SEARCH_APPLICANT_NAME`), or by reading a file in the user's **private** repo. Do
  not hardcode a default that embeds a real person.
- In docs and examples, use placeholders (`<Your Name>`, `<Company>`, `<Role>`) rather than real
  values.

**Where personal details live:** the user's private repos (for the job-search skill, that's
`~/workspace/jobs/`, including `profile.md`). Read from there at runtime; never copy into this
repo.

If you catch existing PII in this repo, treat it as a bug and remove/genericize it.
