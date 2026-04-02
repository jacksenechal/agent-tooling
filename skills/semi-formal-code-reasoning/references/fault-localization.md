# Fault Localization Semi-formal Reasoning Template

Use this 4-phase template when given a failing test and asked to locate the buggy code.
Every prediction must trace back through a divergence claim to a specific test premise.
The chain is: PREMISE → CLAIM → PREDICTION.

## Phase 1: Test Semantics Analysis

```
## Phase 1: Test Semantics Analysis
- What does the failing test method do step by step?
- What are the explicit assertions / expected exceptions?
- What is the expected behavior vs. the observed failure mode?
- State these as formal PREMISES:
  PREMISE T1: The test calls X.method(args) and expects [behavior]
  PREMISE T2: The test asserts [condition]
  ...
```

## Phase 2: Code Path Tracing

```
## Phase 2: Code Path Tracing
- Trace the execution path from the test's entry point into production code
- For each significant method call, document:
  METHOD: ClassName.methodName(params)
  LOCATION: file:line
  BEHAVIOR: what this method does
  RELEVANT: why it matters to the test
- Build a call sequence showing the flow from test -> production code
```

## Phase 3: Divergence Analysis

```
## Phase 3: Divergence Analysis
- For each code path traced, identify where the implementation
  could diverge from the test's expectations
- State divergences as formal claims:
  CLAIM D1: At [file:line], [code] would produce [behavior]
            which contradicts PREMISE T[N] because [reason]
  CLAIM D2: ...
- Each claim must reference a specific PREMISE and a specific code location
```

## Phase 4: Ranked Predictions

```
## Phase 4: Ranked Predictions
- Based on the divergence claims, produce ranked predictions
- Each prediction must cite the supporting CLAIM(s)

Rank 1 (high): [file:lines] — [reason], supported by CLAIM D[N]
Rank 2 (high): [file:lines] — [reason], supported by CLAIM D[N]
Rank 3 (medium): [file:lines] — [reason], supported by CLAIM D[N]
...
```

## Structured Exploration Format

When requesting a file during agentic exploration, use this format:

```
#### When requesting a file:

HYPOTHESIS H[N]: [What you expect to find and why it may contain the bug]
EVIDENCE: [What from the test or previously read files supports this hypothesis]
CONFIDENCE: [high/medium/low]

#### After reading a file:

OBSERVATIONS from [filename]:
  O[N]: [Key observation about the code, with line numbers]
  O[N]: [Another observation]

HYPOTHESIS UPDATE:
  H[M]: [CONFIRMED | REFUTED | REFINED] - [Explanation]

UNRESOLVED:
  - [What questions remain unanswered]
  - [What other files/functions might need examination]

NEXT ACTION RATIONALE: [Why reading another file, or why enough evidence to predict]
```

## Key Failure Modes to Avoid

1. **Indirection bugs** — the bug may be in a class not directly invoked by the test; trace callees, not just direct callers.
2. **Multi-file bugs** — bugs spanning multiple files require identifying all locations; large ground-truth sets are systematically harder.
3. **Stopping at the crash site** — the crash site is often a symptom; trace back to the root cause (e.g., an overwrite that corrupts state upstream).
4. **Pattern-matching on function names** — verify behavior by reading source, not by assuming semantics from names.
