---
completed_at: "2026-09-06T05:56:59Z"
description: Allow ?scalar and ?[]const u8 fields in materialized result trees, decoded to Go pointers
plan_status: done
registered_at: "2026-09-06T05:53:16Z"
---
> NEXT: Optional scalar and string fields. ([Phase 0](phases/00-optional-fields.md))

# Phases

- [x] [Phase 00: Optional scalar and string fields](phases/00-optional-fields.md)

# Shared Verification

`zig build test`; `zig build go && (cd go && go test ./...)` and the purego
equivalent in `examples/12-materialized`.

# Decisions That Constrain Ordering

One phase.

# Next Implementation Target

Optional scalar and string fields.
