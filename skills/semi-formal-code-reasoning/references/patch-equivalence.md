# Patch Equivalence Semi-formal Certificate Template

Use this template when determining whether two patches produce identical test outcomes.
Fill in every `[bracketed]` field with evidence gathered from the codebase.

```
DEFINITIONS:
D1: Two patches are EQUIVALENT MODULO TESTS iff executing the
    existing repository test suite produces identical pass/fail
    outcomes for both patches.
D2: The relevant tests are ONLY those in FAIL_TO_PASS and
    PASS_TO_PASS (the existing test suite in the repository).

PREMISES (state what each patch does):
P1: Patch 1 modifies [file(s)] by [specific change description]
P2: Patch 2 modifies [file(s)] by [specific change description]
P3: The FAIL_TO_PASS tests check [specific behavior being tested]
P4: The PASS_TO_PASS tests check [specific behavior, if relevant]

ANALYSIS OF TEST BEHAVIOR:

For FAIL_TO_PASS test(s):
  Claim 1.1: With Patch 1 applied, test [name] will [PASS/FAIL]
             because [trace through the code behavior]
  Claim 1.2: With Patch 2 applied, test [name] will [PASS/FAIL]
             because [trace through the code behavior]
  Comparison: [SAME/DIFFERENT] outcome

For PASS_TO_PASS test(s) (if patches could affect them differently):
  Claim 2.1: With Patch 1 applied, test behavior is [description]
  Claim 2.2: With Patch 2 applied, test behavior is [description]
  Comparison: [SAME/DIFFERENT] outcome

EDGE CASES RELEVANT TO EXISTING TESTS:
(Only analyze edge cases that the ACTUAL tests exercise)

E1: [Edge case that existing tests exercise]
  - Patch 1 behavior: [specific output/behavior]
  - Patch 2 behavior: [specific output/behavior]
  - Test outcome same: [YES/NO]

COUNTEREXAMPLE (required if claiming NOT EQUIVALENT):
Test [name] will [PASS/FAIL] with Patch 1 because [reason]
Test [name] will [FAIL/PASS] with Patch 2 because [reason]
Therefore patches produce DIFFERENT test outcomes.

OR

NO COUNTEREXAMPLE EXISTS (required if claiming EQUIVALENT):
All existing tests produce identical outcomes because [reason]

FORMAL CONCLUSION:
By Definition D1:
- Test outcomes with Patch 1: [PASS/FAIL for each test]
- Test outcomes with Patch 2: [PASS/FAIL for each test]
- Since test outcomes are [IDENTICAL/DIFFERENT], patches are
  [EQUIVALENT/NOT EQUIVALENT] modulo the existing tests.

ANSWER: [YES/NO]
```

## Key Failure Modes to Avoid

1. **Assuming stdlib semantics** — always grep for local definitions of called functions; modules can shadow builtins.
2. **Third-party library guessing** — when source is unavailable, explicitly state the uncertainty rather than assuming.
3. **Dismissing subtle differences** — if one patch handles an edge case differently, trace whether any test exercises that edge case.
