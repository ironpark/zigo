---
perf_phase: false
status: planned
---
> DONE-WHEN: 예제 10종이 새 옵션으로 갱신되고 두 백엔드가 통과한다.
> NEXT: none

# Collapse the build option axes

## Planned Work

- `backend` + `link_mode`를 하나의 축으로 접는다 (`cgo_static`, `cgo_dynamic`, `purego`).
  purego가 동적 링크를 강제하던 `@panic`이 사라진다.
- `raw_package`를 경로 하나로 표현하고 동위치 여부를 public package 경로와의 비교로 파생한다.
- 남는 `@panic` 검증을 진단이나 컴파일 오류로 옮길 수 있는지 검토한다.

## Done When

- 예제 10종이 새 옵션으로 갱신되고 두 백엔드가 통과한다.
- `configuration.md`에 옛 옵션 → 새 옵션 마이그레이션 표가 있다.
