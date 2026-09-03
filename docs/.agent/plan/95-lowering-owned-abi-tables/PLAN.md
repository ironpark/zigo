---
description: move retained callback slots, flattened field indexes, packed bit layout, omitted variants, and C identifier note origin out of the emitter into lowering and validation data
plan_status: in-progress
registered_at: "2026-09-03T01:06:08Z"
---
> NEXT: Move slot, flatten, omitted-variant, and packed-layout facts into lowering. ([Phase 0](phases/00-lowering-tables.md))

# Phases

- [x] [Phase 00: Slots, flatten indexes, omitted variants, packed layout](phases/00-lowering-tables.md)
- [ ] [Phase 01: Identifier note origin](phases/01-note-origin.md)

# Shared Verification

`zig build test --summary all`; `zig fmt --check build.zig src tests examples`; for every `examples/NN`: `zig build --build-file examples/NN/build.zig test go-check abi-check go-lib go-coverage`, then `go vet ./...` and `go test -count=1 ./...` in each `go.mod` dir; purego: 04/07/08/11 `purego-go purego-go-check`, 10 `go go-check -Dpurego=true`; 07 `go test -race`; `git status` shows no drift in goldens or example generated files.

# Decisions That Constrain Ordering

Phases are independent; do 0 then 1.

# Next Implementation Target

Move slot, flatten, omitted-variant, and packed-layout facts into lowering.
