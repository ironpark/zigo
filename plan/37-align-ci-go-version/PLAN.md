---
description: Align example Go module requirements with the Go 1.24 CI toolchain.
plan_status: in-progress
registered_at: "2026-08-31T07:20:30Z"
---
> NEXT: Align the two example module requirements with CI and verify their tests. ([Phase 0](phases/00-initial-work.md))

# Phases

- [ ] [Phase 00: Initial Work](phases/00-initial-work.md)

# Shared Verification

Search every example `go.mod` for its Go directive, run `go test ./...` in the two affected modules with `GOTOOLCHAIN=local`, and run `git diff --check`.

# Decisions That Constrain Ordering

The single phase is independent and atomic.

# Next Implementation Target

Align the two example module requirements with CI and verify their tests.
