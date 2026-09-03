---
description: honor .name on .constructs functions and let .cancel name the Zig error that means cancellation
plan_status: in-progress
registered_at: "2026-09-03T03:53:27Z"
---
> NEXT: Use the explicit .name for constructor wrappers. ([Phase 0](phases/00-constructor-name.md))

# Phases

- [ ] [Phase 00: Honor .name on constructors](phases/00-constructor-name.md)
- [ ] [Phase 01: Configurable cancel error name](phases/01-cancel-error-name.md)

# Shared Verification

`zig build test --summary all`; `zig fmt --check build.zig src tests examples`; for every `examples/NN`: `zig build --build-file examples/NN/build.zig test go-check abi-check go-lib go-coverage`, then `go vet ./...` and `go test -count=1 ./...` in each `go.mod` dir; purego: 04/07/08/11 `purego-go purego-go-check`, 10 `go go-check -Dpurego=true`; 07 `go test -race`. Generator goldens must not change unless a case opts in.

# Decisions That Constrain Ordering

Independent; do 0 then 1.

# Next Implementation Target

Use the explicit .name for constructor wrappers.
