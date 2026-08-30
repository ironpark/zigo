---
perf_phase: false
status: in-progress
---
> DONE-WHEN: Existing explicit declarations produce unchanged public output and duplicate method names receive the correct parameter names/docs in tests.
> NEXT: none

# Qualified reflection model

## Planned Work

- Extend reflected function identity with stable owner-qualified Zig paths.
- Make AST enrichment resolve root functions and nested methods by qualified owner rather than bare name.
- Pass the actual target module source root to enrichment and add focused duplicate-method tests.

## Done When

- Existing explicit declarations produce unchanged public output and duplicate method names receive the correct parameter names/docs in tests.
