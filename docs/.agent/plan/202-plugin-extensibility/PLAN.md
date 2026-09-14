---
depends_on:
- api-consistency-refactor
description: "Plugin contract 5.0: Go builder layer, node-level ext with param/field use, visitor hooks, built-ins on the public contract"
plan_status: in-progress
registered_at: "2026-09-14T06:30:33Z"
---
> NEXT: Go builder layer: replaces string templates so later phases port hooks once. ([Phase 0](phases/00-go-builder.md))

# Phases

- [x] [Phase 00: Go builder layer](phases/00-go-builder.md)
- [x] [Phase 01: Node-level extensions and DSL use](phases/01-node-ext.md)
- [x] [Phase 02: Visitor hooks](phases/02-visitor-hooks.md)
- [ ] [Phase 03: Built-ins on the public contract](phases/03-builtins-on-contract.md)

# Shared Verification

Per phase: `zig fmt --check .`; root `zig build test`; `cd plugins/<name> && zig build test` for enumkit, json, satisfies; examples 07, 10, 11 `zig build go-verify` and purego variants plus `go test ./...`; `go-check` in all other examples. Regenerate goldens only when a phase says output may change.

# Decisions That Constrain Ordering

0 → 1 → 2 → 3, strictly sequential, one handoff agent per phase, committed before the next.

# Next Implementation Target

Go builder layer: replaces string templates so later phases port hooks once.
