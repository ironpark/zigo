---
depends_on:
- "30-go-user-experience#2"
perf_phase: false
status: in-progress
---
> DONE-WHEN: The Go AST documentation audit passes across generated fixtures, wiki and README examples match the implemented API, all generated artifacts are current, and the full Zig/example Go/ABI validation matrix passes.
> NEXT: none

# Complete Generated GoDoc and User Documentation

## Planned Work

- Emit identifier-leading GoDoc for all exported generated declarations, including types, enum values, errors, constructors, lifecycle methods, projections, callbacks, and fallback function documentation.
- Document ownership, slice/borrow lifetimes, checked versus panic APIs, standard build steps, report/doctor usage, and concurrency limits.
- Regenerate and format every example; add a Go AST regression that rejects undocumented exported generated declarations.

## Done When

- The Go AST documentation audit passes across generated fixtures, wiki and README examples match the implemented API, all generated artifacts are current, and the full Zig/example Go/ABI validation matrix passes.
