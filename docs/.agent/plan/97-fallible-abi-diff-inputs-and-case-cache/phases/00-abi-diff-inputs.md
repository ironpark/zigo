---
perf_phase: false
status: planned
---
> DONE-WHEN: Malformed input yields a diagnostic and non-zero exit; existing abi-diff tests unchanged; tests green.
> NEXT: none

# abi-diff input validation

## Planned Work

- Validate both abi-diff inputs (or make lowering fallible), add the CLI fixture and test, document the precondition.

## Done When

- Malformed input yields a diagnostic and non-zero exit; existing abi-diff tests unchanged; tests green.
