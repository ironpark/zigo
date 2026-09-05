---
description: 코드 검토에 근거한 후속 리팩토링 제안과 검증 기준
plan_status: in-progress
registered_at: "2026-09-05T13:53:58Z"
---
> NEXT: Handle lifecycle facts를 ABI에 기록하는 첫 단계를 진행한다. ([Phase 0](phases/00-handle-facts.md))

# Phases

- [ ] [Phase 00: Handle lifecycle facts in ABI](phases/00-handle-facts.md)
- [ ] [Phase 01: Separate common emitter responsibilities](phases/01-emitter-boundaries.md)
- [ ] [Phase 02: Separate reflection responsibilities](phases/02-reflection-boundaries.md)

# Shared Verification

구현 시 zig build check와 zig build test를 실행하고 예제 go-check로 출력 동일성을 확인한다.
핸들 변경은 cgo와 purego runtime contracts를 실행한다. 각 단계에서 관련 테스트를 실행하고 결과를 기록한다.
helper 탐색은 telemetry-hub와 materialized에서 반복 횟수, 시간, 할당을 측정한 후
렌더 결과 재사용 여부를 결정한다. 미사용 helper 제거 계약은 유지한다.

# Decisions That Constrain Ordering

120 계획의 실제 상태를 먼저 확인한다. lifecycle 판정 이동, emitter 경계 정리,
reflection 분리 순으로 제안한다. 각 단계는 독립적으로 검증하고 커밋한다.

# Next Implementation Target

Handle lifecycle facts를 ABI에 기록하는 첫 단계를 진행한다.
