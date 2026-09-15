---
completed_at: "2026-09-15T02:53:07Z"
depends_on:
- plugin-extensibility
description: "Plugin contract 6.0: per-target render slots with a Rust builder and Rust visitor, and native-side contributions (Zig source plus C symbols flowing through shim, header, raw and abi-diff)"
plan_status: done
registered_at: "2026-09-15T00:43:15Z"
---
> NEXT: Per-target render slots and Rust builder: the contract shape the other three phases build on. ([Phase 0](phases/00-target-slots.md))

# Phases

- [x] [Phase 00: Per-target render slots and Rust builder](phases/00-target-slots.md)
- [x] [Phase 01: Rust-capable shipped plugin](phases/01-rust-plugin.md)
- [x] [Phase 02: Native contributions](phases/02-native-contributions.md)
- [x] [Phase 03: Native-capable shipped plugin](phases/03-native-plugin.md)

# Shared Verification

Per phase: `zig fmt --check .`; root `zig build test`; `cd plugins/<name> && zig build test` for every shipped plugin;
examples 07, 10, 11 `go-verify` (+ purego) and `go test ./...`; example 13 `rust-check`, `rust-abi-check`, `cargo test`;
`go-check` in all other examples. Regenerate goldens only where a phase says output changes.

# Decisions That Constrain Ordering

0 → 1 → 2 → 3, strictly sequential, one handoff agent per phase, committed before the next.

# Next Implementation Target

Per-target render slots and Rust builder: the contract shape the other three phases build on.
