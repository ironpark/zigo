---
completed_at: "2026-09-07T09:02:40Z"
depends_on:
- "147-callback-enum-and-handle-adapters#1"
perf_phase: false
status: done
---
> DONE-WHEN: `zig build test go-check go-lib abi-check go-coverage` and the purego steps pass in the
> NEXT: none

# Example coverage and changelog

## Planned Work

- Add to `examples/04-callback` a `Level` enum, an `Inspector` callback that receives
  `(*CallbackContext, Level, bool)` and returns `Level`, plus a driver function; register
  them in the bindings and add a Go test on both backends that asserts the handle method
  works inside the callback and the enum round-trips.
- Add an Unreleased `Fixed` entry to `CHANGELOG.md`.

## Done When

- `zig build test go-check go-lib abi-check go-coverage` and the purego steps pass in the
  example, and `go test ./...` passes in `go` and `go-purego`.
