---
description: make abi-diff report malformed semantic.json instead of panicking and make generator case steps rerun when their inputs change
plan_status: in-progress
registered_at: "2026-09-03T02:46:06Z"
---
> NEXT: Make abi-diff reject malformed inputs with a diagnostic. ([Phase 0](phases/00-abi-diff-inputs.md))

# Phases

- [ ] [Phase 00: abi-diff input validation](phases/00-abi-diff-inputs.md)
- [ ] [Phase 01: generator case cache correctness](phases/01-case-cache.md)

# Shared Verification

`zig build test --summary all`; `zig fmt --check build.zig src tests examples`; for every `examples/NN`: `zig build --build-file examples/NN/build.zig test go-check abi-check go-lib go-coverage`, then `go vet ./...` and `go test -count=1 ./...` in each `go.mod` dir; purego: 04/07/08/11 `purego-go purego-go-check`, 10 `go go-check -Dpurego=true`; 07 `go test -race`; `git status` shows no drift in goldens or example generated files.

# Decisions That Constrain Ordering

Independent; do 0 then 1.

# Next Implementation Target

Make abi-diff reject malformed inputs with a diagnostic.
