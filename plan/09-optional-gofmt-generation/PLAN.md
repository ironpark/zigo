---
description: Run gofmt on generated Go files when available, without mutating generator cache outputs, and use formatted files for update and stale checks.
plan_status: in-progress
registered_at: "2026-08-30T02:46:59Z"
---
> NEXT: Implement and verify the optional immutable gofmt stage. ([Phase 0](phases/00-optional-gofmt-stage.md))

# Phases

- [ ] [Phase 00: Optional gofmt stage](phases/00-optional-gofmt-stage.md)

# Shared Verification

Run `zig build test --summary all`, every example's `zig build go go-check abi-check --summary all`, every Go module's tests, inspect formatter steps, and run `git diff --check`.

# Decisions That Constrain Ordering

The format stage and both consumers change atomically to prevent formatted source updates from disagreeing with `go-check`.

# Next Implementation Target

Implement and verify the optional immutable gofmt stage.
