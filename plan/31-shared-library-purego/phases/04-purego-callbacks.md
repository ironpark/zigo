---
depends_on:
- "31-shared-library-purego#3"
perf_phase: false
status: planned
---
> DONE-WHEN: Callback examples pass under `CGO_ENABLED=0`, race-enabled Go tests show no registry leaks or calls
> NEXT: none

# purego Callback Registry and Lifecycle

## Planned Work

- Generate one permanent `purego.NewCallback` dispatcher per unique callback ABI signature and a
  concurrency-safe userdata token registry, avoiding unreclaimable callback-slot growth per value.
- Implement borrowed and retained callback lifetimes, constructor rollback, explicit Close,
  `runtime.AddCleanup`, concurrent invocation/close tests, and callback panic translation using the
  same public callback types and status conventions as cgo.
- Add purego variants of the event-queue and broad telemetry callback scenarios.

## Done When

- Callback examples pass under `CGO_ENABLED=0`, race-enabled Go tests show no registry leaks or calls
  through released tokens, repeated callback registration consumes a bounded number of purego native
  callback slots, and cgo callback behavior remains compatible.
