---
depends_on:
- "26-26-zig-test-hardening#3"
perf_phase: false
status: in-progress
---
> DONE-WHEN: build option 경계 test와 전체 repository validation이 모두 통과하고 남은 비범위가 문서화된다.
> NEXT: none

# Build options and full matrix

## Planned Work

- raw package path/name validation을 pure testable helper로 분리해 invalid component와 keyword를 검사한다.
- 감사 문서와 개발 문서를 실제 보강 상태로 갱신한다.
- root, 8개 example Zig/Go/stale/ABI, formatting 및 host compile matrix를 실행한다.

## Done When

- build option 경계 test와 전체 repository validation이 모두 통과하고 남은 비범위가 문서화된다.
