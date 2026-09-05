---
depends_on:
- "121-refactor-proposal#1"
perf_phase: false
status: planned
---
> DONE-WHEN: semantic 스냅샷, 패키지 관계, 필드 접근자와 자동 발견 관련 기존 검증이 통과한다.
> NEXT: none

# Separate reflection responsibilities

## Planned Work

- reflect/walk의 패키지 선택과 closure부터 독립 모듈로 추출한다.
- 필드 접근자와 자동 발견은 별도 변경으로 분리한다.
- comptime 매개변수와 기존 진단 순서를 보존한다.

## Done When

- semantic 스냅샷, 패키지 관계, 필드 접근자와 자동 발견 관련 기존 검증이 통과한다.
