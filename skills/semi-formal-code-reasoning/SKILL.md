---
name: semi-formal-code-reasoning
description: >
  Deep semantic code analysis using semi-formal structured reasoning without executing code.
  Uses certificate templates requiring explicit premises, execution path tracing, and formal
  conclusions — preventing the failure mode of guessing semantics from function names.

  Always use for: code review, patch equivalence (do these diffs produce the same test
  outcomes?), fault localization (which lines cause this test to fail?), code QA (nuanced
  questions about codebase semantics or behavior).

  Also trigger when: a previous fix attempt failed without clear diagnosis; reasoning
  involves third-party library internals or framework hooks; failing test and suspected bug
  are in different modules; behavior requires tracing 3+ files; code may shadow builtins
  (format, type, open, etc.); multiple inheritance or generics; security or data-integrity
  code; refactoring verification; user is surprised by unexpected behavior.

  Skip for simple questions answerable from a single file or when a stack trace directly
  names the cause.
---

# Semi-formal Code Reasoning

Semi-formal reasoning structures the analysis process so that every claim must cite
specific code evidence before a conclusion is reached. This prevents the common failure
mode of guessing semantics from function names or making unsupported equivalence claims.

**Key principle:** Gather evidence first, conclude last. The structured template acts as
a certificate — you cannot skip cases or make unsupported claims.

## Task Selection

Choose the right template based on the task:

| Task | Trigger | Template |
|------|---------|----------|
| Patch equivalence | "are these patches equivalent?", "do these diffs produce the same tests?" | [patch-equivalence.md](references/patch-equivalence.md) |
| Fault localization | "find the bug", "localize the fault", "which lines cause this test to fail?" | [fault-localization.md](references/fault-localization.md) |
| Code question answering | "what does X do?", "why does this behave this way?", "explain the semantics of..." | [code-qa.md](references/code-qa.md) |

Read the appropriate reference file before beginning the analysis.

## Core Workflow

1. **Read the template** for the task type (links above).
2. **Explore the codebase** to gather evidence:
   - Read the test files to understand what behavior is being tested.
   - Trace function calls — don't assume; read the actual implementations.
   - For any called function, check for local/module-level definitions that shadow builtins.
3. **Fill in the template** with gathered evidence. Every bracketed field needs a value from source code.
4. **Apply the Alternative Hypothesis Check** before concluding — explicitly try to disprove your answer.
5. **State a formal conclusion** grounded in the filled-in template.

## What Makes This Different from Standard Reasoning

Standard agentic reasoning lets you conclude freely from observations. Semi-formal
reasoning requires:

- **Premises** — explicit statements of what each patch/function does, cited to source
- **Claims** — divergence claims that reference specific premises and code locations
- **Formal conclusion** — derived from the claims, not from intuition

The template structure naturally forces interprocedural reasoning: tracing a function
call requires following it into its definition, which is where subtle bugs (like a
shadowed builtin) get discovered.

## Common Pitfalls

- **Assuming stdlib semantics**: Always grep for local definitions before assuming a
  function refers to the builtin. Modules routinely shadow `format`, `open`, `type`, etc.
- **Stopping at the crash site**: For fault localization, the crash site is often a
  symptom. Trace back to the root cause (e.g., a state overwrite that happens earlier).
- **Guessing third-party behavior**: When library source is unavailable, explicitly mark
  the claim as unverified rather than assuming from the function name.
- **Skipping the counterexample check**: For patch equivalence, you must either produce
  a concrete counterexample or argue exhaustively that none exists.
