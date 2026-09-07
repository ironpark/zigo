---
depends_on:
- "139-two-pass-discovery#0"
perf_phase: true
status: planned
---
> DONE-WHEN: 전체 테스트와 예제 go-check 루프 통과, `git status --short examples` 비어 있음.
> NEXT: none

# Runtime sets in coverage and example regeneration

## Planned Work

- `coverage.classify`가 listed/excluded 집합을 만들어 `collectContainer`에 넘기고 status를 런타임에 정한다.
- 08-telemetry-hub의 cgo·purego 생성물을 재생성하고 go-check로 확인한다. CHANGELOG와 문서를 갱신한다.

## Done When

- 전체 테스트와 예제 go-check 루프 통과, `git status --short examples` 비어 있음.
