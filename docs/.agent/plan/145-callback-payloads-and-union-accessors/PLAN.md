---
completed_at: "2026-09-07T08:06:28Z"
description: Carry strings and byte slices through callback parameters, and expose payload accessors on value-returned tagged unions
plan_status: done
registered_at: "2026-09-07T07:11:36Z"
---
> NEXT: Reflect and emit byte payloads in callback signatures. ([Phase 1](phases/01-callback-byte-payloads.md))

# Phases

- [x] [Phase 00: Value union accessors](phases/00-value-union-accessors.md)
- [x] [Phase 01: Callback string and byte payloads](phases/01-callback-byte-payloads.md)

# Shared Verification

`zig build test`; `examples/04-callback` and `examples/10-tagged-union` Go tests on both backends.

# Decisions That Constrain Ordering

Phase 0 then 1; independent.

# Next Implementation Target

Reflect and emit byte payloads in callback signatures.
