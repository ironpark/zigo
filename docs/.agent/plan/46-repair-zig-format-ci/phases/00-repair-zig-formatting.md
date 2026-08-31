---
perf_phase: false
status: in-progress
---
> DONE-WHEN: CI와 동일한 format check 및 `zig build test --summary all`이 성공한다.
> NEXT: none

# Repair Zig formatting

## Planned Work

- `src/gen/emit.zig`에 Zig formatter를 적용하고 diff가 기계적 변경인지 확인한다.
- 전체 format check와 Zig test를 실행한다.

## Done When

- CI와 동일한 format check 및 `zig build test --summary all`이 성공한다.
