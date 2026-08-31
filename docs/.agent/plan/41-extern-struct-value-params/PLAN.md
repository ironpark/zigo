---
completed_at: "2026-08-31T10:25:51Z"
description: Lower extern struct parameters and returns through pointers while presenting Go value semantics
plan_status: done
registered_at: "2026-08-31T10:01:11Z"
---
> NEXT: 적격 조건과 진단부터 세워 도달 가능한 unreachable을 없앤다. ([Phase 0](phases/00-eligibility-diagnostics.md))

# Phases

- [x] [Phase 00: Eligibility and diagnostics](phases/00-eligibility-diagnostics.md)
- [x] [Phase 01: Lowering and native emitters](phases/01-lowering-native-emit.md)
- [x] [Phase 02: Go surfaces for both backends](phases/02-go-surfaces.md)
- [x] [Phase 03: ABI rules, example and documentation](phases/03-abi-example-docs.md)

# Shared Verification

`zig build test` 로 골든 트리, 진단 스냅샷, CLI 계약 테스트를 확인한다. 예제 디렉터리에서
`zig build go go-check abi-check` 와 cgo·purego `go test` 를 실행한다. 회귀 재현으로
`value_struct` 픽스처를 `zigo-gen generate` 에 직접 통과시킨다.

# Decisions That Constrain Ordering

0 → 1 → 2 → 3. 순차 진행한다.

# Next Implementation Target

적격 조건과 진단부터 세워 도달 가능한 unreachable을 없앤다.
