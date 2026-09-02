---
description: reject void callback returns with a diagnostic; release retained callback handles when re-registered or when the owning handle closes
plan_status: in-progress
registered_at: "2026-09-02T22:10:46Z"
---
> NEXT: Make `void` callback results generate on both backends instead of panicking. ([Phase 0](phases/00-void-callback-results.md))

# Phases

- [x] [Phase 00: Void callback results](phases/00-void-callback-results.md)
- [ ] [Phase 01: Retained callback ownership on methods](phases/01-retained-callback-ownership.md)

# Shared Verification

From the repo root: `zig build test --summary all`; `zig fmt --check build.zig src tests examples`; for every `examples/NN`: `zig build --build-file examples/NN/build.zig test go-check abi-check go-lib`, then in each `go.mod` directory `go vet ./...` and `go test -count=1 ./...`; purego: 04/07/08/11 `purego-go purego-go-check`, 10 `go go-check -Dpurego=true`; 07 additionally `go test -race`.

# Decisions That Constrain Ordering

Phase 0 then phase 1; phase 1 tests may use a `void` callback so it depends on phase 0.

# Next Implementation Target

Make `void` callback results generate on both backends instead of panicking.
