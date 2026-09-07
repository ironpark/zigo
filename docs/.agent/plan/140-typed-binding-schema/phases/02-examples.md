---
depends_on:
- "140-typed-binding-schema#1"
perf_phase: false
status: planned
---
> DONE-WHEN: 예제 루프 go-check와 staticcheck 통과, 생성물 diff 검토 완료.
> NEXT: none

# Examples

## Planned Work

- 예제 13개의 `bindings.zig`를 새 문법으로 옮기고 `zig build go`(purego 포함)로 생성물을 재생성한다. 생성물 diff는 함수 순서(그룹이 `.methods`로 이동)와 `.doc` 반영 외에는 없어야 한다.

## Done When

- 예제 루프 go-check와 staticcheck 통과, 생성물 diff 검토 완료.
