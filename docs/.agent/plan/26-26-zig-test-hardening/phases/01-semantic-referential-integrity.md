---
completed_at: "2026-08-30T09:45:20Z"
depends_on:
- "26-26-zig-test-hardening#0"
perf_phase: false
status: done
---
> DONE-WHEN: 손상 semantic이 panic하지 않고 명시적 오류를 반환하며 관련 test가 통과한다.
> NEXT: none

# Semantic referential integrity

## Planned Work

- type name uniqueness, enum tag, referenced enum/opaque/value type와 constructor mapping을 검증한다.
- missing enum panic을 validation error와 actionable diagnostic으로 바꾼다.
- table-driven validation과 generator output-preservation 회귀 테스트를 추가한다.

## Done When

- 손상 semantic이 panic하지 않고 명시적 오류를 반환하며 관련 test가 통과한다.
