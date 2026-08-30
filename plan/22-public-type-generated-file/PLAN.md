---
description: Split generated public Go type declarations into package_type_gen.go and update the build graph, fixtures, examples, and docs.
plan_status: in-progress
registered_at: "2026-08-30T06:54:53Z"
---
> NEXT: Add the type-file emitter and wire it through the complete generation build graph. ([Phase 0](phases/00-emitter-and-build-graph.md))

# Phases

- [ ] [Phase 00: Emitter and build graph](phases/00-emitter-and-build-graph.md)
- [ ] [Phase 01: Fixtures, documentation, and verification](phases/01-fixtures-docs-and-verification.md)

# Shared Verification

Run `zig build test`, `zig build check`, `zig build check -Dtarget=x86_64-windows-gnu`, `zig fmt --check .`, `git diff --check`, all example `go-check`/`abi-check` steps, all Go module tests, and available example Zig tests.

# Decisions That Constrain Ordering

Implement and validate the new generated-file contract before regenerating committed examples and updating documentation.

# Next Implementation Target

Add the type-file emitter and wire it through the complete generation build graph.
