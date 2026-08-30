---
description: Replace the internal zigo-gen positional protocol with tested generate, check, and abi-diff subcommands using named arguments.
plan_status: in-progress
registered_at: "2026-08-30T03:14:53Z"
---
> NEXT: Replace the positional generator protocol with named subcommands and verify it end to end. ([Phase 0](phases/00-named-generator-protocol.md))

# Phases

- [ ] [Phase 00: Named generator protocol](phases/00-named-generator-protocol.md)

# Shared Verification

Run `zig build test --summary all`, each example's `zig build go go-check abi-check --summary all`, each Go module's tests, source searches, and `git diff --check`.

# Decisions That Constrain Ordering

Parser, command handlers and build graph callers change in one phase because old and new protocols are intentionally not mixed.

# Next Implementation Target

Replace the positional generator protocol with named subcommands and verify it end to end.
