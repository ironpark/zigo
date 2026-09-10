---
completed_at: "2026-09-10T05:28:06Z"
depends_on:
- "189-rust-backend-cleanup#3"
perf_phase: false
status: done
---
> DONE-WHEN: All 14 examples pass their full step list.
> NEXT: none

# Share the neutral build wiring between the two backends

## Planned Work

- Extract the errors-lock probe, the staleness-check wiring and the abi-check
  baseline from `addGoBindings` and `addRustBindings` into private helpers in
  `build.zig`, continuing the pattern `addReflection` established on this
  branch. All three operate on `semantic.json` and `errors.lock.json`, which
  every target shares.
- Rename `steps.PublishGeneratedGo` if the extraction leaves it publishing both
  trees under a Go-specific name.

## Done When

- All 14 examples pass their full step list.
- `zig build test` passes.
- The three blocks have one definition each.
