---
description: Productionize shared-library output and add an opt-in purego backend for generated Go bindings without requiring cgo at application build time.
plan_status: in-progress
registered_at: "2026-08-30T12:44:24Z"
---
> NEXT: Define and test the shared-library artifact, exported-symbol, and runtime-loading contract first. ([Phase 0](phases/00-shared-library-contract.md))

# Phases

- [x] [Phase 00: Shared Library Artifact Contract](phases/00-shared-library-contract.md)
- [x] [Phase 01: Backend Model and Atomic purego Loader](phases/01-purego-loader.md)
- [x] [Phase 02: Callback-Free purego Call Surface](phases/02-purego-call-surface.md)
- [ ] [Phase 03: Callback Function-Pointer ABI](phases/03-callback-pointer-abi.md)
- [ ] [Phase 04: purego Callback Registry and Lifecycle](phases/04-purego-callbacks.md)
- [ ] [Phase 05: Packaging, CI, and User Documentation](phases/05-packaging-ci-docs.md)

# Shared Verification

- Zig: generator/lowering/emitter/ABI/doctor unit tests plus `zig build test --summary all`.
- Artifact: platform file inspection, symbol-table assertions, dependency/install-name checks, and a
  process-level dynamic-load smoke test.
- Go cgo: every existing example continues to pass `go test ./...`, `go-check`, and optional ABI check.
- Go purego: `CGO_ENABLED=0 go test -race ./...` where purego supports the race mode, normal
  `CGO_ENABLED=0 go test ./...` everywhere else, plus repeated loader/callback lifecycle stress tests.
- Compatibility: compare generated public Go AST declarations across cgo and purego, and require ABI
  diff to report backend/callback convention changes.

# Decisions That Constrain Ordering

The shared artifact contract precedes code generation because purego needs a loadable, named binary.
The atomic loader precedes call wrappers. Callback-free calls establish the direct FFI mapping before
the higher-risk callback ABI and lifetime work. Packaging and claims wait until both call directions
pass on the supported platform matrix.

# Next Implementation Target

Define and test the shared-library artifact, exported-symbol, and runtime-loading contract first.
