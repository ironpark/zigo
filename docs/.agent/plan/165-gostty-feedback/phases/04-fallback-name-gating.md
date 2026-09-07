---
perf_phase: false
status: planned
---
> DONE-WHEN: 평범한 struct 메서드가 익명 컨테이너 이름을 받지 않는 테스트 통과, `zig build test` 통과, 커밋.
> NEXT: none

# Fallback name gating

## Planned Work

- walk가 `owner_generic`을 기록(SemanticFn 신규 optional 필드, generic 인스턴스일 때만 true).
- names.zig unqualified fallback은 owner가 없거나 owner_generic일 때만 적용. 테스트 갱신.

## Done When

- 평범한 struct 메서드가 익명 컨테이너 이름을 받지 않는 테스트 통과, `zig build test` 통과, 커밋.
