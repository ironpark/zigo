---
description: payload가 스칼라/void뿐인 tagged union을 값 파라미터로 받는 경로
plan_status: in-progress
registered_at: "2026-09-02T17:32:43Z"
---
> NEXT: 스칼라 payload tagged union의 값 파라미터 적격성과 C 평탄화를 설계·구현한다. ([Phase 0](phases/00-eligibility-and-abi.md))

# Phases

- [ ] [Phase 00: 적격성과 ABI 설계](phases/00-eligibility-and-abi.md)
- [ ] [Phase 01: Go 값 타입과 purego, 예제, 문서](phases/01-go-surface-and-docs.md)

# Shared Verification

- `zig build test --summary all`, `zig fmt --check build.zig src tests examples`.
- 전 예제 루프(cgo·purego), 골든 갱신은 실패 출력의 actual 경로 사용.

# Decisions That Constrain Ordering

0 → 1. 우선순위 낮음: 79, 80 이후.

# Next Implementation Target

스칼라 payload tagged union의 값 파라미터 적격성과 C 평탄화를 설계·구현한다.
