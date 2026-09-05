---
completed_at: "2026-09-05T08:45:07Z"
description: "Explicit `.interfaces` registration: a named Go interface over a chosen set of opaque handles, validated by rendered signature equality (ZIGO049), emitted as <pkg>_interfaces_gen.go. Minor release."
plan_status: done
registered_at: "2026-09-05T08:29:44Z"
---
> NEXT: `Semantic.interfaces`와 reflector의 `.interfaces` 등록을 추가한다. ([Phase 0](phases/00-ir-and-reflector.md))

# Phases

- [x] [Phase 00: IR and reflector](phases/00-ir-and-reflector.md)
- [x] [Phase 01: Structural validation](phases/01-structural-validation.md)
- [x] [Phase 02: Lowering, signature rule and emitter](phases/02-lowering-and-emitter.md)
- [x] [Phase 03: Example, abi-diff and docs](phases/03-example-diff-docs.md)

# Shared Verification

- 각 phase: `zig build test`.
- phase 2 이후: `tests/generator_cases/interfaces*/expected/*_interfaces_gen.go`가 존재한다.
- phase 3 이후: `examples/05-pipeline/go/pipeline/pipeline_interfaces_gen.go`가 존재한다.

# Decisions That Constrain Ordering

0 → 1 → 2 → 3. IR이 있어야 검증할 수 있고, 구조 검증이 있어야 lowering이 해석에 실패하지 않으며,
emitter가 있어야 예제와 문서가 실제 생성물을 보여줄 수 있다.

# Next Implementation Target

`Semantic.interfaces`와 reflector의 `.interfaces` 등록을 추가한다.
