---
depends_on:
- slice-ownership-and-struct-elements
description: Document and propagate cgo link flags (pkg-config, lib paths); out-only deep-copied value struct trees; struct append ABI policy
plan_status: in-progress
registered_at: "2026-09-01T21:31:55Z"
---
> NEXT: Document link-flag propagation and emit `#cgo pkg-config:` and `-L` lines from the target module. ([Phase 0](phases/00-link-flag-propagation.md))

# Phases

- [x] [Phase 00: Link flag rules and pkg-config propagation](phases/00-link-flag-propagation.md)
- [ ] [Phase 01: Out-only deep-copied value struct trees](phases/01-out-only-struct-trees.md)
- [x] [Phase 02: Value struct append ABI policy](phases/02-struct-append-policy.md)

# Shared Verification

- `zig build test --summary all` at the root; `src/gen/generator.zig` link-line
  tests; example `go-check` and Go tests for touched examples; purego suite for
  phase 1.

# Decisions That Constrain Ordering

Phase 0 and phase 2 are independent and small; run them first. Phase 1 waits
on plan 61 phases 1 and 4 and on a maintainer decision.

# Next Implementation Target

Document link-flag propagation and emit `#cgo pkg-config:` and `-L` lines from the target module.
