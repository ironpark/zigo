---
perf_phase: false
status: in-progress
---
> DONE-WHEN: 고아 키 테스트가 `error.ParamMetaKey`를 기대하며 통과한다.
> NEXT: none

# Reject orphaned param_meta keys

## Planned Work

- `walk.zig`에 comptime 검사 추가: `.param_meta`의 각 필드 이름이 `.params`에 있는지 확인, 없으면 ZIGO057 메시지로 `error.ParamMetaKey` 반환.
- 테스트와 문서 추가.

## Done When

- 고아 키 테스트가 `error.ParamMetaKey`를 기대하며 통과한다.
