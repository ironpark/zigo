---
description: merge identical predicates, record string and callback classification on the lowered IR, and diff lowered programs in abi-diff without changing output
plan_status: in-progress
registered_at: "2026-09-03T01:32:00Z"
---
> NEXT: Merge the identical predicates and split the same-name, different-concept ones. ([Phase 0](phases/00-merge-and-split.md))

# Phases

- [x] [Phase 00: Merge identical predicates and split same-name concepts](phases/00-merge-and-split.md)
- [x] [Phase 01: Record classification on the lowered IR](phases/01-classification-on-ir.md)
- [ ] [Phase 02: abi-diff over lowered programs](phases/02-abi-diff-lowered.md)

# Shared Verification

`zig build test --summary all`; `zig fmt --check build.zig src tests examples`; for every `examples/NN`: `zig build --build-file examples/NN/build.zig test go-check abi-check go-lib go-coverage`, then `go vet ./...` and `go test -count=1 ./...` in each `go.mod` dir; purego: 04/07/08/11 `purego-go purego-go-check`, 10 `go go-check -Dpurego=true`; 07 `go test -race`; `git status` shows no drift in goldens or example generated files.

# Decisions That Constrain Ordering

0, then 1, then 2.

# Next Implementation Target

Merge the identical predicates and split the same-name, different-concept ones.
