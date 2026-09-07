---
depends_on:
- "140-typed-binding-schema#0"
perf_phase: false
status: in-progress
---
> DONE-WHEN: `zig build test --summary all` 전체 통과.
> NEXT: none

# Coverage, packages, interfaces

## Planned Work

- `coverage.zig`, `packages.zig`, interfaces 반영이 타입 스키마를 읽게 하고 테스트를 옮긴다.
- `tests/generator_cases`와 `tests/fixtures`의 바인딩 선언을 옮긴다.

## Done When

- `zig build test --summary all` 전체 통과.
