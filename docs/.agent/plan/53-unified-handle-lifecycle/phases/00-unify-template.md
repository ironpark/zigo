---
completed_at: "2026-09-01T11:24:18Z"
perf_phase: false
status: done
---
> DONE-WHEN: Regenerated examples 04 and 10 both show the unified struct; in example
> NEXT: none

# Unify the handle template per type

## Planned Work

- Replace the two handle emission paths in `emit.zig` with one template:
  `ptr` + `once` + `mu` + `cleanup`, plus `callbackHandles` only for types
  whose constructors take callbacks (per-type decision, not per-program).
- Emit the unified constructor (`new<Type>` with AddCleanup registration),
  Close (write-lock, cleanup.Stop, deinit, callback release), and cleanup
  function (deinit + callback release from captured state).
- Emit the read-lock prologue for all handle methods in both former schemes,
  retaining existing KeepAlive emission.
- Update goldens (cgo and purego) and `generator.zig` expectations.

## Done When

- Regenerated examples 04 and 10 both show the unified struct; in example
  04, `FloatBuffer`/`IntBuffer` have no `callbackHandles` field while
  `CallbackContext` does; example 10's handles now carry `mu`.
- `zig build test` passes; examples 04 and 10 compile and their tests pass.
