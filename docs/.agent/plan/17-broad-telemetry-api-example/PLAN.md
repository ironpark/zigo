---
completed_at: "2026-08-30T05:10:49Z"
description: Add a deliberately large telemetry hub example with 40+ public operations to stress binding generation, ownership, errors, enums, slices, callbacks, docs, and CI.
plan_status: done
registered_at: "2026-08-30T05:03:38Z"
---
> NEXT: Implement the broad TelemetryHub state machine and expose at least 40 operations. ([Phase 0](phases/00-broad-telemetry-api.md))

# Phases

- [x] [Phase 00: Broad telemetry API example](phases/00-broad-telemetry-api.md)

# Shared Verification

Use source/generated declaration counts, example Zig and Go tests, all eight
example generation checks, root Zig tests, Windows compile, `zig fmt --check`,
`git diff --check`, and a post-commit ABI comparison.

# Decisions That Constrain Ordering

Build and test the Zig state machine first, bind and generate second, derive Go
tests from the generated API third, then update CI/docs and finish with full checks.

# Next Implementation Target

Implement the broad TelemetryHub state machine and expose at least 40 operations.
