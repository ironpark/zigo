---
description: add .repr = .materialized so pointer-bearing result trees cross the boundary as one serialized buffer decoded into idiomatic Go structs
plan_status: in-progress
registered_at: "2026-09-03T03:53:27Z"
---
> NEXT: Reflect .repr = .materialized trees and validate their shape. ([Phase 0](phases/00-reflect-and-validate.md))

# Phases

- [ ] [Phase 00: Reflection, semantic model and validation](phases/00-reflect-and-validate.md)
- [ ] [Phase 01: Lowering and the Zig walker](phases/01-lowering-and-walker.md)
- [ ] [Phase 02: Go decoders on cgo and purego](phases/02-go-decoders.md)
- [ ] [Phase 03: Example, benchmark and docs](phases/03-example-and-docs.md)

# Shared Verification

`zig build test --summary all`; `zig fmt --check build.zig src tests examples`; for every `examples/NN`: `zig build --build-file examples/NN/build.zig test go-check abi-check go-lib go-coverage`, then `go vet ./...` and `go test -count=1 ./...` in each `go.mod` dir; purego: 04/07/08/11 `purego-go purego-go-check`, 10 `go go-check -Dpurego=true`; 07 `go test -race`. Generator goldens must not change unless a case opts in.

# Decisions That Constrain Ordering

Strictly sequential: 0 -> 1 -> 2 -> 3.

# Next Implementation Target

Reflect .repr = .materialized trees and validate their shape.
