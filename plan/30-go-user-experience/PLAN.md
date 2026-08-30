---
description: Unify generated Go handle safety, add checked APIs and standard build diagnostics, and improve generated Go documentation.
plan_status: in-progress
registered_at: "2026-08-30T11:40:38Z"
---
> NEXT: Implement uniform opaque-handle validation and source-compatible checked tagged-union projection APIs. ([Phase 0](phases/00-uniform-handle-safety.md))

# Phases

- [ ] [Phase 00: Uniform Handle Safety and Checked Projections](phases/00-uniform-handle-safety.md)
- [ ] [Phase 01: Standard Build Steps](phases/01-standard-build-steps.md)
- [ ] [Phase 02: Binding Report and Environment Doctor](phases/02-report-and-doctor.md)
- [ ] [Phase 03: Complete Generated GoDoc and User Documentation](phases/03-complete-generated-godoc.md)

# Shared Verification

Run focused emitter, CLI, build-graph, and generator tests during each phase. At completion run `zig build test`, every example's generation and stale check, configured ABI checks, and `go test ./...` for every example Go module. Run `git diff --check` and confirm a clean worktree after each phase commit and plan transition.

# Decisions That Constrain Ordering

Safety semantics come first because later docs and diagnostics must describe the final contract. Standard build-step registration precedes report/doctor exposure. Complete GoDoc and broad regeneration are last so snapshots are updated once after the public behavior and commands stabilize.

# Next Implementation Target

Implement uniform opaque-handle validation and source-compatible checked tagged-union projection APIs.
