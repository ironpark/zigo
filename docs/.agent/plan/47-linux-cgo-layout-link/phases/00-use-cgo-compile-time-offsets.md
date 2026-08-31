---
perf_phase: false
status: in-progress
---
> DONE-WHEN: helper에 `static const size_t offsetof_` 선언이 없고 모든 검증 명령이 성공한다.
> NEXT: none

# Use cgo compile-time offsets

## Planned Work

- layout helper의 offset 선언을 C enum constant로 바꾸고 Go reference를 유지한다.
- Go formatting, event-queue generation·Go test, 전체 format·Zig test를 실행한다.

## Done When

- helper에 `static const size_t offsetof_` 선언이 없고 모든 검증 명령이 성공한다.
