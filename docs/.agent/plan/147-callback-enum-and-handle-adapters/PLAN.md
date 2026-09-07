---
description: Callback adapters convert enum params/results and wrap handle pointer params as borrowed handles on both backends
plan_status: in-progress
registered_at: "2026-09-07T08:40:47Z"
---
> NEXT: Enum callback adapters: adapter converts enum params and results. ([Phase 0](phases/00-enum-adapters.md))

# Phases

- [ ] [Phase 00: Enum callback adapters](phases/00-enum-adapters.md)
- [ ] [Phase 01: Borrowed handle callback parameters](phases/01-handle-params.md)
- [ ] [Phase 02: Example coverage and changelog](phases/02-example-and-changelog.md)

# Shared Verification

- `zig build test --summary all` at the repository root.
- `scripts/update-generator-cases.sh callback_enum_handle callback_enum_handle_purego`
  followed by a diff review.
- `examples/04-callback`: `zig build test go-check go-lib abi-check go-coverage
  purego-go-check purego-go-lib --summary all`, then `go test ./...` in `go` and `go-purego`.

# Decisions That Constrain Ordering

Phase 0 changes the adapter signature that phase 1 extends; phase 2 exercises both through
a real library, so it goes last.

# Next Implementation Target

Enum callback adapters: adapter converts enum params and results.
