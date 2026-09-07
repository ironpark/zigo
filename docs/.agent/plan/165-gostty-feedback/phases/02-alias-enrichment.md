---
perf_phase: false
status: planned
---
> DONE-WHEN: alias 테스트에서 doc과 파라미터 이름이 채워지고 `zig build test` 통과, 커밋.
> NEXT: none

# Alias enrichment

## Planned Work

- names.zig scanMembers가 `pub const a = B.c;`를 alias로 기록(파일 간 지속), enrichMatches가 alias 대상으로도 매칭.
- alias 자체 doc이 있으면 우선 적용. 테스트·docs.

## Done When

- alias 테스트에서 doc과 파라미터 이름이 채워지고 `zig build test` 통과, 커밋.
