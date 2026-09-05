---
depends_on:
- "121-refactor-proposal#0"
perf_phase: false
status: planned
---
> DONE-WHEN: 공통 타입 표기 모듈이 구체 emitter를 import하지 않고 기존 출력이 동일하다.
> NEXT: none

# Separate common emitter responsibilities

## Planned Work

- common의 타입 표기와 target 경로 해석을 작은 독립 모듈로 추출한다.
- 구체 출력 writer는 해당 emitter로 옮기고 공통 모듈의 역방향 의존을 줄인다.
- 단순 재export만 늘리는 분할은 피한다.

## Done When

- 공통 타입 표기 모듈이 구체 emitter를 import하지 않고 기존 출력이 동일하다.
