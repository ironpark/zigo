---
completed_at: "2026-09-05T20:25:27Z"
description: "Let one cgo binding set build and link native libraries for several GOOS/GOARCH targets via qualified #cgo directives"
plan_status: done
registered_at: "2026-09-05T20:11:31Z"
---
> NEXT: Emitter and CLI target list. ([Phase 0](phases/00-emitter-cgo-targets.md))

# Phases

- [x] [Phase 00: Emitter and CLI target list](phases/00-emitter-cgo-targets.md)
- [x] [Phase 01: Build integration for several targets](phases/01-build-targets.md)
- [x] [Phase 02: Documentation and release notes](phases/02-docs.md)

# Shared Verification

- `zig build test` (unit tests, generator snapshot cases, build options).
- Manual: temporary project with two targets, `zig build go`, inspect
  `zig-out/lib/<goos>_<goarch>/`, `go build ./...` on the host.
- Examples: `zig build go-check` in one cgo example to confirm no drift.

# Decisions That Constrain Ordering

Phase 0 first because the build integration passes the new flags. Phase 1
next. Phase 2 last, once behavior is fixed.

# Next Implementation Target

Emitter and CLI target list.
