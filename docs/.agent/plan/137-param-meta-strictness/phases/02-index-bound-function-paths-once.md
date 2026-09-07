---
perf_phase: true
status: planned
---
> DONE-WHEN: 기존 coverage 테스트가 그대로 통과하고, `functionListed`가 항목 순회 대신 색인 조회를 사용한다.
> NEXT: none

# Index bound function paths once

## Planned Work

- `coverage.zig`의 `functionListed`가 소스 함수마다 바인딩 항목 전체를 선형 탐색하던 것을, 바인딩의 함수 경로를 comptime에 한 번 모아 `std.StaticStringMap`으로 만든 뒤 조회하도록 바꾼다.
- 중첩 함수 그룹의 경로도 같은 색인에 넣는다.

## Done When

- 기존 coverage 테스트가 그대로 통과하고, `functionListed`가 항목 순회 대신 색인 조회를 사용한다.
