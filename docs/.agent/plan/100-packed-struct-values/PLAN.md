---
description: register integer-backed packed structs of bool, integer, and enum fields as Go value mirrors and let them cross as parameters, returns, extern struct fields, and field accessors
plan_status: in-progress
registered_at: "2026-09-03T03:27:39Z"
---
> NEXT: Accept integer-backed packed structs as registered value types. ([Phase 0](phases/00-packed-values.md))

# Phases

- [ ] [Phase 00: Packed struct values](phases/00-packed-values.md)

# Shared Verification

`zig build test --summary all`; `zig fmt --check build.zig src tests examples`; for every `examples/NN`: `zig build --build-file examples/NN/build.zig test go-check abi-check go-lib go-coverage`, then `go vet ./...` and `go test -count=1 ./...` in each `go.mod` dir; purego: 04/07/08/11 `purego-go purego-go-check`, 10 `go go-check -Dpurego=true`; 07 `go test -race`.

# Decisions That Constrain Ordering

Single phase.

# Next Implementation Target

Accept integer-backed packed structs as registered value types.
