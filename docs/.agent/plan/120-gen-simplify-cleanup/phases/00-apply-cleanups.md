---
completed_at: "2026-09-05T14:17:54Z"
perf_phase: false
status: done
---
> DONE-WHEN: `zig build test` passes and `git diff` shows no snapshot changes.
> NEXT: none

# Apply Cleanups

## Planned Work

- Replace duplicated lookups with `semantic.typeDecl`, `lower.constructorForType`, `errorPayload()`, `naming.freeParamNames`.
- Delete dead code (`publicTypeNameExists`, unused re-exports) and route the public-function filter through one predicate.
- Factor `handles.zig` lifecycle names and repeated snippets; simplify decoder scope threading; trim output without re-copying.

## Done When

- `zig build test` passes and `git diff` shows no snapshot changes.
