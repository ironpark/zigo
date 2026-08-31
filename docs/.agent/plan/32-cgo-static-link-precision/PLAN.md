---
completed_at: "2026-08-31T05:28:03Z"
description: Link the generated cgo archive by explicit path so a dynamic purego artifact cannot shadow it in a shared zig-out
plan_status: done
registered_at: "2026-08-31T05:20:08Z"
---
> NEXT: Make generated static cgo bindings link their archive by explicit path. ([Phase 0](phases/00-static-archive-link.md))

# Phases

- [x] [Phase 00: Explicit Static Archive Link](phases/00-static-archive-link.md)
- [x] [Phase 01: Dual-Backend Build Proof](phases/01-dual-backend-proof.md)

# Shared Verification

- Zig: `zig build check` and `zig build test --summary all`, including emitter tests for the static,
  dynamic and overridden LDFLAGS forms.
- Generated output: `zig build go-check` in every example and a clean `git status` for `examples`
  and `tests/generator_cases` after regeneration.
- Go: every example's `go test ./...` for the cgo backend and `CGO_ENABLED=0 go test ./...` for the
  purego backend, run from one build tree that contains both artifacts.
- Documentation: every command shown in the wiki and README is executed as written.

# Decisions That Constrain Ordering

The emitter change must land with its regenerated artifacts before CI asserts the single-tree build,
because the assertion fails against the current generated files.

# Next Implementation Target

Make generated static cgo bindings link their archive by explicit path.
