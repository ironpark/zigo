---
completed_at: "2026-09-05T22:54:17Z"
perf_phase: true
status: done
---
> DONE-WHEN: `zig build test` passes; 07 and 08 `go test` pass on both backends and the
> NEXT: none

# Pending callback-panic counter

## Planned Work

- Add the counter, its increment/decrement and `PendingCallbackPanics()` to
  the cgo and purego raw emitters.
- Wrap the rethrow block in the public emitter with the counter check, via a
  `zigoCallbackPanicPending()` helper in the runtime file.
- Update generator cases, regenerate examples (cgo and purego), run the
  benchmark, update `generated-runtime.md` and CHANGELOG.

## Done When

- `zig build test` passes; 07 and 08 `go test` pass on both backends and the
  callback-panic tests still observe `*CallbackPanicError`.
