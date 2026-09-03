---
description: emit generated Go helpers only when the public layer references them, and gate the examples with staticcheck U1000
plan_status: in-progress
registered_at: "2026-09-03T03:53:27Z"
---
> NEXT: Gate every helper on an actual reference. ([Phase 0](phases/00-referenced-helpers.md))

# Phases

- [ ] [Phase 00: Reference-driven helper emission](phases/00-referenced-helpers.md)
- [ ] [Phase 01: staticcheck in CI](phases/01-staticcheck-ci.md)

# Shared Verification

`zig build test --summary all`; `zig fmt --check build.zig src tests examples`; for every `examples/NN`: `zig build --build-file examples/NN/build.zig test go-check abi-check go-lib go-coverage`, then `go vet ./...` and `go test -count=1 ./...` in each `go.mod` dir; purego: 04/07/08/11 `purego-go purego-go-check`, 10 `go go-check -Dpurego=true`; 07 `go test -race`. Generator goldens must not change unless a case opts in.

# Decisions That Constrain Ordering

Phase 1 needs phase 0's clean baseline.

# Next Implementation Target

Gate every helper on an actual reference.
