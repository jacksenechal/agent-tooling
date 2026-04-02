# Code Question Answering Semi-formal Reasoning Template

Use this template when answering questions about code semantics, behavior, or design.
Fill in every `[bracketed]` field with evidence gathered from the codebase.
Reduces the tendency to guess based on function names by requiring explicit evidence citations.

```
FUNCTION TRACE TABLE:
| Function/Method | File:Line | Parameter Types | Return Type | Behavior (VERIFIED) |
|-----------------|-----------|-----------------|-------------|---------------------|
| [function1]     | [file:N]  | [param types]   | [ret type]  | [ACTUAL behavior]   |
| [function2]     | [file:N]  | [param types]   | [ret type]  | [ACTUAL behavior]   |

DATA FLOW ANALYSIS:
Variable: [key variable name]
- Created at: [file:line]
- Modified at: [file:line(s)], or 'NEVER MODIFIED'
- Used at: [file:line(s)]

[Repeat for each key variable relevant to the question]

SEMANTIC PROPERTIES:
Property 1: [e.g., 'HashMap is mutable' or 'function is idempotent']
- Evidence: [specific file:line]

Property 2: [e.g., 'invariant holds because...']
- Evidence: [specific file:line]

ALTERNATIVE HYPOTHESIS CHECK:
If the opposite answer were true, what evidence would exist?
- Searched for: [what you looked for]
- Found: [what you found — cite file:line]
- Conclusion: [REFUTED / SUPPORTED]

<answer>[Final answer with explicit evidence citations]</answer>
```

## Usage Notes

- Fill the Function Trace Table by actually reading the source files — do not infer behavior from names.
- The Alternative Hypothesis Check is mandatory: explicitly try to disprove your conclusion before committing to it.
- For questions about differences between two APIs/functions, both must appear in the trace table.
- `Behavior (VERIFIED)` means you read the implementation, not that you inferred it.

## Key Failure Modes to Avoid

1. **Naming assumption** — functions with similar names often have different semantics; always read the implementation.
2. **Incomplete trace** — tracing 5 functions but missing the 6th that handles the edge case leads to a confident wrong answer.
3. **Irrelevant edge cases** — don't mention hypothetical behaviors that the actual code paths cannot exercise; this loses points on rubrics.
