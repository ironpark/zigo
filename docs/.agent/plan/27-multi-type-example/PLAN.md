---
completed_at: "2026-08-30T10:06:48Z"
description: Add a verified example with multiple opaque types and a method whose receiver accepts another exposed type.
plan_status: done
registered_at: "2026-08-30T10:02:40Z"
---
> NEXT: Implement and validate the multi-type consumer example. ([Phase 0](phases/00-multi-type-consumer-example.md))

# Phases

- [x] [Phase 00: Multi-type consumer example](phases/00-multi-type-consumer-example.md)

# Shared Verification

Run the example `test`, `go`, `go-check`, `abi-check`, and Go tests; then run root formatting, test, and diff checks.

# Decisions That Constrain Ordering

The single phase creates source first, generates committed artifacts second, and validates the complete consumer last.

# Next Implementation Target

Implement and validate the multi-type consumer example.
