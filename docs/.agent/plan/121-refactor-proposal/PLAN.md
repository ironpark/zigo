---
completed_at: "2026-09-05T14:25:41Z"
description: 코드 검토에 근거한 후속 리팩토링 제안과 검증 기준
plan_status: done
registered_at: "2026-09-05T13:53:58Z"
---
> NEXT: 세 구현 단계와 검증을 완료했다. ([Phase 0](phases/00-handle-facts.md))

# Phases

- [x] [Phase 00: Handle lifecycle facts in ABI](phases/00-handle-facts.md)
- [x] [Phase 01: Separate common emitter responsibilities](phases/01-emitter-boundaries.md)
- [x] [Phase 02: Separate reflection responsibilities](phases/02-reflection-boundaries.md)

# Shared Verification

구현 시 zig build check와 zig build test를 실행하고 예제 go-check로 출력 동일성을 확인한다.
핸들 변경은 cgo와 purego runtime contracts를 실행한다. 각 단계에서 관련 테스트를 실행하고 결과를 기록한다.
helper 탐색 최적화와 성능 측정은 이번 세 구현 단계에 포함하지 않는다.
미사용 helper 제거 계약은 유지한다.

검증 기록: 각 구현 단계에서 zig build check test 통과, 0·1 단계 전체 예제 go-check 통과.
0 단계에서 04·07·10·11·12 예제의 cgo와 purego Go 테스트 통과.
2 단계에서 전체 예제 go-check와 abi-check 통과. 생성물과 스냅샷 변경 없음.
필드 접근자와 자동 발견의 추가 모듈 분리는 별도 후속 변경으로 남긴다.

# Decisions That Constrain Ordering

120 계획의 실제 상태를 먼저 확인한다. lifecycle 판정 이동, emitter 경계 정리,
reflection 분리 순으로 제안한다. 각 단계는 독립적으로 검증하고 커밋한다.

# Next Implementation Target

세 구현 단계와 검증을 완료했다.
