---
completed_at: "2026-09-02T22:47:32Z"
description: generate getters and optional setters for scalar and enum fields of opaque types via .fields with dotted paths
plan_status: done
registered_at: "2026-09-02T22:15:54Z"
---
> NEXT: Reflect `.fields` into synthesized accessor functions with a diagnostic for unsupported paths. ([Phase 0](phases/00-reflect-fields.md))

# Phases

- [x] [Phase 00: Reflect and validate fields](phases/00-reflect-fields.md)
- [x] [Phase 01: Emit accessors on both backends](phases/01-emit-accessors.md)

# Shared Verification

`zig build test --summary all`; `zig fmt --check build.zig src tests examples`; per example `zig build --build-file examples/NN/build.zig test go-check abi-check go-lib`, `go vet ./...` and `go test -count=1 ./...` in each `go.mod` dir; purego targets for 04/07/08/11 (`purego-go purego-go-check`) and 10 (`go go-check -Dpurego=true`).

# Decisions That Constrain Ordering

Phase 0 then 1.

# Next Implementation Target

Reflect `.fields` into synthesized accessor functions with a diagnostic for unsupported paths.
