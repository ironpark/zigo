---
completed_at: "2026-09-03T00:42:53Z"
description: let the binding set choose where the native library, static link inputs, and C header are installed and keep cgo, purego, and coverage paths in sync
plan_status: done
registered_at: "2026-09-03T00:21:00Z"
---
> NEXT: Add the `install` option and route every artifact path through it. ([Phase 0](phases/00-install-locations.md))

# Phases

- [x] [Phase 00: Configurable install locations](phases/00-install-locations.md)

# Shared Verification

`zig build test --summary all`; `zig fmt --check build.zig src tests examples`; for every `examples/NN`: `zig build --build-file examples/NN/build.zig test go-check abi-check go-lib go-coverage`, `go vet ./...` and `go test -count=1 ./...` in each `go.mod` dir; purego: 04/07/08/11 `purego-go purego-go-check`, 10 `go go-check -Dpurego=true`; 07 `go test -race`; `git status` shows no drift in examples that did not opt in.

# Decisions That Constrain Ordering

Single phase.

# Next Implementation Target

Add the `install` option and route every artifact path through it.
