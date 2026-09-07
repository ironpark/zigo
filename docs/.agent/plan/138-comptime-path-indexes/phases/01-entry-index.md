---
completed_at: "2026-09-07T03:00:23Z"
depends_on:
- "138-comptime-path-indexes#0"
perf_phase: true
status: done
---
> DONE-WHEN: discovery 테스트 전부 통과, 예제 coverage 통과.
> NEXT: none

# Index bound entries by path

## Planned Work

- `boundFunctionPaths`의 값을 항목 위치(그룹 인덱스, 항목 인덱스)로 바꾸고, discovery 루프가 색인으로 항목을 찾아 `appendDiscoveredEntry`에 넘기게 한다.

## Done When

- discovery 테스트 전부 통과, 예제 coverage 통과.
