---
description: make a failed Go callback trip the function's cancel flag and let bindings declare a domain fallback result instead of the in-band -3/-4 sentinels
plan_status: in-progress
registered_at: "2026-09-03T03:53:27Z"
---
> NEXT: Set the cancel flag from every callback failure path. ([Phase 0](phases/00-cancel-trip.md))

# Phases

- [x] [Phase 00: Trip the cancel flag on callback failure](phases/00-cancel-trip.md)
- [ ] [Phase 01: Declared fallback result](phases/01-fallback-result.md)

# Shared Verification

`zig build test --summary all`; `zig fmt --check build.zig src tests examples`; for every `examples/NN`: `zig build --build-file examples/NN/build.zig test go-check abi-check go-lib go-coverage`, then `go vet ./...` and `go test -count=1 ./...` in each `go.mod` dir; purego: 04/07/08/11 `purego-go purego-go-check`, 10 `go go-check -Dpurego=true`; 07 `go test -race`. Generator goldens must not change unless a case opts in.

# Decisions That Constrain Ordering

Phase 1 reuses the failure-path helper introduced in phase 0.

# Next Implementation Target

Set the cancel flag from every callback failure path.
