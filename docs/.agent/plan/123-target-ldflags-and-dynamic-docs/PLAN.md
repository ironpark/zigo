---
completed_at: "2026-09-05T20:59:54Z"
description: Per-platform appended cgo LDFLAGS via cgo_flags.target_ldflags, and a documented rpath recipe for .cgo_dynamic
plan_status: done
registered_at: "2026-09-05T20:58:16Z"
---
> NEXT: Per-platform appended LDFLAGS and dynamic docs. ([Phase 0](phases/00-target-ldflags.md))

# Phases

- [x] [Phase 00: Per-platform appended LDFLAGS and dynamic docs](phases/00-target-ldflags.md)

# Shared Verification

`zig build test`; `zig build go-check` in an example.

# Decisions That Constrain Ordering

One phase.

# Next Implementation Target

Per-platform appended LDFLAGS and dynamic docs.
