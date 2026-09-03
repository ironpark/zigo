---
completed_at: "2026-09-03T05:35:58Z"
perf_phase: false
status: done
---
> DONE-WHEN: `fn f(text: []const u21)` and a `[]u21` caller-owned return bind and round-trip in Go tests on both backends.
> NEXT: none

# Narrow integer slice elements

## Planned Work

- Validation carve-out, lowering, shim conversion for inputs and caller-owned outputs on cgo and purego, tests, generator case, example, docs, CHANGELOG.

## Done When

- `fn f(text: []const u21)` and a `[]u21` caller-owned return bind and round-trip in Go tests on both backends.
