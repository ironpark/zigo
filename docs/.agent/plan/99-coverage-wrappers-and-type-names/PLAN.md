---
description: let wrappers declare which upstream declaration they cover, classify them in go-coverage, and fix the unregistered type list's names and false positives
plan_status: in-progress
registered_at: "2026-09-03T03:14:22Z"
---
> NEXT: Add `.covers` and the `wrapped` classification to go-coverage. ([Phase 0](phases/00-covers.md))

# Phases

- [ ] [Phase 00: Wrapper coverage via `.covers`](phases/00-covers.md)
- [ ] [Phase 01: Unregistered type names and false positives](phases/01-type-names.md)

# Shared Verification

`zig build test --summary all`; `zig fmt --check build.zig src tests examples`; for every `examples/NN`: `zig build --build-file examples/NN/build.zig test go-check abi-check go-lib go-coverage`, then `go vet ./...` and `go test -count=1 ./...` in each `go.mod` dir; purego: 04/07/08/11 `purego-go purego-go-check`, 10 `go go-check -Dpurego=true`; 07 `go test -race`.

# Decisions That Constrain Ordering

Independent; do 0 then 1.

# Next Implementation Target

Add `.covers` and the `wrapped` classification to go-coverage.
