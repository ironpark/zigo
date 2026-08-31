---
completed_at: "2026-08-30T05:28:56Z"
perf_phase: false
status: done
---
> DONE-WHEN: Helper code is isolated in package-named generated files with unchanged package behavior; every planned check passes, implementation is committed, and the phase is recorded done.
> NEXT: none

# Split Generated Go Helpers

## Planned Work

- Add a helper emitter, remove helper rendering and helper-only imports from the public emitter, and test boolean, callback, empty-helper, and colocated cases.
- Update build-graph outputs, golden fixtures, eight examples, and generated-layout documentation.
- Run focused and full Zig, regeneration, stale, ABI, Go, formatting, and cross-target verification, then commit without including unrelated worktree changes.

## Done When

- Helper code is isolated in package-named generated files with unchanged package behavior; every planned check passes, implementation is committed, and the phase is recorded done.
