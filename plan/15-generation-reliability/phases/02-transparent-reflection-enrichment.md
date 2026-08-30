---
depends_on:
- "15-generation-reliability#1"
perf_phase: false
status: in-progress
---
> DONE-WHEN: Focused tests verify fatal primary errors, allowed missing root files, visible
> NEXT: none

# Transparent reflection enrichment

## Planned Work

- Make the primary binding source failure fatal, distinguish optional missing
  sources from real I/O failures, and emit path-specific warnings for auxiliary
  read and AST parse failures while preserving fallback behavior.

## Done When

- Focused tests verify fatal primary errors, allowed missing root files, visible
  import/parse warnings, and stable fallback-name warnings; full tests pass.
