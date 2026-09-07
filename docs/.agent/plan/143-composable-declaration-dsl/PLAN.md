---
completed_at: "2026-09-07T06:41:52Z"
description: Add stable exact-list selectors, reusable path projections, generic collection, named type batches, and lifecycle shortcuts to the comptime DSL.
plan_status: done
registered_at: "2026-09-07T06:31:24Z"
---
> NEXT: Implement stable exact function lists, generic collection, and path projection. ([Phase 0](phases/00-stable-function-lists.md))

# Phases

- [x] [Phase 00: Stable function lists and projections](phases/00-stable-function-lists.md)
- [x] [Phase 01: Named type batches](phases/01-named-type-batches.md)
- [x] [Phase 02: Lifecycle ergonomics and documentation](phases/02-lifecycle-and-docs.md)

# Shared Verification

Run focused root/DSL tests after each implementation phase, repository compile-failure coverage for diagnostic behavior, `zig fmt --check build.zig src examples`, `git diff --check`, and `zig build test --summary all` before completion.

# Decisions That Constrain Ordering

Function list primitives land first because generic collection is required by type batches. Type batches land next. Lifecycle conveniences and public documentation land only after the final API shapes are verified.

# Next Implementation Target

Implement stable exact function lists, generic collection, and path projection.
