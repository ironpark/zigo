---
description: Apply prioritized Zig 0.16 reliability, test, build, and developer-experience improvements informed by zls.
plan_status: in-progress
registered_at: "2026-08-30T03:49:12Z"
---
> NEXT: Harden allocator ownership and allocation-failure behavior before restructuring tests. ([Phase 0](phases/00-allocator-oom-boundaries.md))

# Phases

- [x] [Phase 00: Harden allocator and OOM boundaries](phases/00-allocator-oom-boundaries.md)
- [ ] [Phase 01: Introduce fixture tests and canonical module wiring](phases/01-fixture-tests-build-graph.md)
- [ ] [Phase 02: Improve failure diagnostics and CI gates](phases/02-diagnostics-ci-gates.md)

# Shared Verification

Run focused tests after each touched subsystem, `zig fmt --check build.zig src tests examples`, `zig build check`, `zig build test --summary all`, and the existing generated Go stale-artifact command. Confirm `git diff --check` before each phase commit.

# Decisions That Constrain Ordering

Memory correctness comes first because later test infrastructure depends on trustworthy failure behavior. Fixture and build-graph work follows because it supplies regression coverage and a faster check step. Diagnostics and CI gates are last so they can consume the final commands and test organization.

# Next Implementation Target

Harden allocator ownership and allocation-failure behavior before restructuring tests.
