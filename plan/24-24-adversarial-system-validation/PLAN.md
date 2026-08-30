---
description: Adversarially validate generator correctness, atomicity, ABI policy, discovery, layouts, formatting, callbacks, cleanup, and cross-target build behavior.
plan_status: in-progress
registered_at: "2026-08-30T08:58:46Z"
---
> NEXT: 정상 기준선과 반복 생성 결정성을 검증한다. ([Phase 0](phases/00-baseline-and-determinism.md))

# Phases

- [ ] [Phase 00: Baseline and deterministic generation](phases/00-baseline-and-determinism.md)
- [ ] [Phase 01: Mutation and failure atomicity](phases/01-mutation-and-failure-atomicity.md)
- [ ] [Phase 02: Lifecycle, breadth, and compatibility matrix](phases/02-lifecycle-breadth-and-compatibility.md)

# Shared Verification

- `zig build test --summary all`
- `zig build check` 및 `zig build check -Dtarget=x86_64-windows-gnu`
- 각 example의 `zig build go-check abi-check`와 Go `go test -count=1 ./...`
- callback/cleanup 대상의 반복 및 `go test -race`
- mutation 실험의 예상 non-zero exit와 진단 문자열 검사
- `zig fmt --check .` 및 `git diff --check`

# Decisions That Constrain Ordering

정상 기준선을 먼저 확정해야 mutation 결과를 비교할 수 있다. 실패 원자성과 gate를 검증한 뒤
비용이 큰 전체 예제/race/교차 타깃 매트릭스로 마무리한다.

# Next Implementation Target

정상 기준선과 반복 생성 결정성을 검증한다.
