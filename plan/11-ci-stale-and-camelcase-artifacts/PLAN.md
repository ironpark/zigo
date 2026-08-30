---
description: Make stale generated-file CI checks effective and keep CamelCase package artifact names normalized end to end.
plan_status: in-progress
registered_at: "2026-08-30T03:33:00Z"
---
> NEXT: Implement the normalized artifact stem, effective CI stale gate, and CamelCase integration example. ([Phase 0](phases/00-enforce-stale-checks-and-normalized-artifacts.md))

# Phases

- [ ] [Phase 00: Enforce stale checks and normalized artifacts](phases/00-enforce-stale-checks-and-normalized-artifacts.md)

# Shared Verification

Run the root Zig suite, the same check/generate/clean-tree/Go-test sequence used by CI, and inspect the CamelCase example's installed library/header names. Validate workflow syntax with `actionlint` when available.

# Decisions That Constrain Ordering

The shared naming fix and fixture must land together because the fixture is an end-to-end regression test. CI ordering is changed in the same phase so its clean-tree gate covers the new fixture.

# Next Implementation Target

Implement the normalized artifact stem, effective CI stale gate, and CamelCase integration example.
