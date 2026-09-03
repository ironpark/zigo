---
description: collect system libraries, frameworks and lib paths across imported modules and verify pkg-config names at build time
plan_status: in-progress
registered_at: "2026-09-03T03:53:27Z"
---
> NEXT: Walk the module graph for system libraries, frameworks and lib paths. ([Phase 0](phases/00-transitive-link-inputs.md))

# Phases

- [ ] [Phase 00: Transitive link inputs](phases/00-transitive-link-inputs.md)
- [ ] [Phase 01: Build-time pkg-config resolution](phases/01-pkg-config-resolution.md)

# Shared Verification

`zig build test --summary all`; `zig fmt --check build.zig src tests examples`; for every `examples/NN`: `zig build --build-file examples/NN/build.zig test go-check abi-check go-lib go-coverage`, then `go vet ./...` and `go test -count=1 ./...` in each `go.mod` dir; purego: 04/07/08/11 `purego-go purego-go-check`, 10 `go go-check -Dpurego=true`; 07 `go test -race`. Generator goldens must not change unless a case opts in.

# Decisions That Constrain Ordering

Phase 1 reuses the collector from phase 0.

# Next Implementation Target

Walk the module graph for system libraries, frameworks and lib paths.
