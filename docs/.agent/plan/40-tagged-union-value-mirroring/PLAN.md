---
completed_at: "2026-08-31T09:50:30Z"
description: Opt-in value snapshot representation for scalar-only tagged unions, keeping projections elsewhere
plan_status: done
registered_at: "2026-08-31T09:00:39Z"
---
> NEXT: 표현과 적격 조건 확정. ([Phase 0](phases/00-representation-eligibility.md))

# Phases

- [x] [Phase 00: Representation and eligibility](phases/00-representation-eligibility.md)
- [x] [Phase 01: Lowering and native emitters](phases/01-lowering-native-emit.md)
- [x] [Phase 02: Go surfaces for both backends](phases/02-go-surfaces.md)
- [x] [Phase 03: ABI rules](phases/03-abi-rules.md)
- [x] [Phase 04: Example and documentation](phases/04-example-docs.md)

# Shared Verification

`zig build test` 로 generator case 골든 트리와 진단 스냅샷, CLI 계약 테스트를 확인한다.
예제 디렉터리에서 `zig build go go-check abi-check` 와 cgo·purego `go test` 를 실행한다.
호출 횟수 감소는 예제의 벤치마크로 확인한다.

# Decisions That Constrain Ordering

0 → 1 → (2, 3) → 4. 2와 3은 1 이후 병렬로 진행할 수 있다.

# Next Implementation Target

표현과 적격 조건 확정.
