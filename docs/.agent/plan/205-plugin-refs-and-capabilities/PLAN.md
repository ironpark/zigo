---
depends_on:
- plugin-targets-and-native
description: "Plugin contract 7.0: reference-typed options (type, function, interface refs checked at declaration and resolved at generation) and capability-based inter-plugin dependencies with shared typed facts"
plan_status: in-progress
registered_at: "2026-09-15T08:32:17Z"
---
> NEXT: Reference-typed options: the wire and comptime machinery satisfies and later capabilities build on. ([Phase 0](phases/00-ref-options.md))

# Phases

- [x] [Phase 00: Reference-typed options](phases/00-ref-options.md)
- [x] [Phase 01: satisfies with checked interfaces](phases/01-satisfies-refs.md)
- [x] [Phase 02: Capabilities and shared facts](phases/02-capabilities.md)
- [ ] [Phase 03: json consumes enumkit](phases/03-json-uses-enumkit.md)

# Shared Verification

Per phase: `zig fmt --check .`; root `zig build test`; `cd plugins/<name> && zig build test` for every shipped plugin;
examples 07, 10, 11 `go-verify` (+ purego) and `go test ./...`; example 13 `rust-check`, `rust-abi-check`, `cargo test`;
`go-check` in all other examples. Regenerate goldens only where a phase says output changes.

# Decisions That Constrain Ordering

0 → 1 → 2 → 3, strictly sequential, one handoff agent per phase, committed before the next.

# Next Implementation Target

Reference-typed options: the wire and comptime machinery satisfies and later capabilities build on.
