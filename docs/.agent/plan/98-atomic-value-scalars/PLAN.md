---
completed_at: "2026-09-03T03:49:12Z"
description: treat std.atomic.Value(T) as its scalar in value positions and accept pointer atomics as call-scoped Go sync/atomic parameters
plan_status: done
registered_at: "2026-09-03T03:09:56Z"
---
> NEXT: Treat `std.atomic.Value(T)` as its scalar in value positions. ([Phase 0](phases/00-atomic-values.md))

# Phases

- [x] [Phase 00: Atomic values as scalars](phases/00-atomic-values.md)
- [x] [Phase 01: Pointer atomics as call-scoped Go sync/atomic parameters](phases/01-atomic-pointers.md)

# Shared Verification

`zig build test --summary all`; `zig fmt --check build.zig src tests examples`; for every `examples/NN`: `zig build --build-file examples/NN/build.zig test go-check abi-check go-lib go-coverage`, then `go vet ./...` and `go test -count=1 ./...` in each `go.mod` dir; purego: 04/07/08/11 `purego-go purego-go-check`, 10 `go go-check -Dpurego=true`; 07 `go test -race`.

# Decisions That Constrain Ordering

0 then 1.

# Next Implementation Target

Treat `std.atomic.Value(T)` as its scalar in value positions.
