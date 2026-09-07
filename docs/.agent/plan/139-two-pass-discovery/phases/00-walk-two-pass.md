---
completed_at: "2026-09-07T04:08:27Z"
perf_phase: true
status: done
---
> DONE-WHEN: `zig build test` 통과.
> NEXT: none

# Two-pass discovery in walk

## Planned Work

- `checkDeclaredPaths`가 집합을 반환하게 하고, discovery 전에 `.functions` 항목을 `appendSelectedEntry`로 반영한 뒤 `discoverContainer`가 런타임 집합으로 건너뛰게 한다.
- comptime 색인 함수와 `appendDiscoveredEntry`, 관련 테스트를 제거하고 discovery 테스트의 순서 기대를 갱신한다.

## Done When

- `zig build test` 통과.
