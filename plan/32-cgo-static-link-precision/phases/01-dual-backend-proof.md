---
completed_at: "2026-08-31T05:28:03Z"
depends_on:
- "32-cgo-static-link-precision#0"
perf_phase: false
status: done
---
> DONE-WHEN: CI runs both backends from one tree in a fixed order that used to fail, and the user documentation
> NEXT: none

# Dual-Backend Build Proof

## Planned Work

- Add a CI step that installs both backends into one build tree and then runs the cgo Go tests and
  the `CGO_ENABLED=0` purego tests, so a future regression of the shadowing bug fails the build.
- Replace the separate-prefix and clean-`zig-out` workaround in the wiki with the supported
  single-tree instructions, keeping the accurate parts about per-target artifacts.

## Done When

- CI runs both backends from one tree in a fixed order that used to fail, and the user documentation
  describes only steps that work as written.
