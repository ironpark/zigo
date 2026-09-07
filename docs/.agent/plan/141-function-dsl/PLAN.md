---
description: comptime func/funcs helpers that materialize typed exact-path binding entries
plan_status: in-progress
registered_at: "2026-09-07T06:02:52Z"
---
> NEXT: Implement the declaration-layer comptime function DSL and verify it end to end. ([Phase 0](phases/00-initial-work.md))

# Phases

- [ ] [Phase 00: Initial Work](phases/00-initial-work.md)

# Shared Verification

Run `zig fmt --check build.zig src examples`, `zig build test --summary all`, and `git diff --check`.

# Decisions That Constrain Ordering

The single phase adds the isolated declaration-layer DSL before documentation and verification in the same commit.

# Next Implementation Target

Implement the declaration-layer comptime function DSL and verify it end to end.
