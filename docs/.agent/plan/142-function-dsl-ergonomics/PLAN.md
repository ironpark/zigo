---
completed_at: "2026-09-07T06:17:57Z"
description: make func/funcs concise and composable without weakening exact-path binding validation
plan_status: done
registered_at: "2026-09-07T06:14:53Z"
---
> NEXT: Implement and verify the concise, composable function DSL. ([Phase 0](phases/00-initial-work.md))

# Phases

- [x] [Phase 00: Initial Work](phases/00-initial-work.md)

# Shared Verification

Run `zig test src/root.zig`, `zig fmt --check build.zig src examples`, `zig build test --summary all`, and `git diff --check`.

# Decisions That Constrain Ordering

Implement the declaration methods and selector/composition helpers together because their public example verifies the intended combined workflow.

# Next Implementation Target

Implement and verify the concise, composable function DSL.
