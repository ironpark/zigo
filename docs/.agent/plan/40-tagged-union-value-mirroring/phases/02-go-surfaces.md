---
completed_at: "2026-08-31T09:49:41Z"
depends_on:
- "40-tagged-union-value-mirroring#1"
perf_phase: false
status: done
---
> DONE-WHEN: 값 스냅샷 union에서 tag와 payload 읽기가 native 호출 1회로 끝나는 것이 테스트로 확인된다.
> NEXT: none

# Go surfaces for both backends

## Planned Work

- cgo raw와 purego raw에 스냅샷 심볼을 추가한다. purego는 포인터 인자만 쓰므로 struct
  전달 제약을 피한다.
- public Go에 `Snapshot() (ValueSnapshot, error)` 계열 API를 생성하고, 스냅샷에서
  tag와 payload를 읽는 접근자를 만든다.
- 기존 `Tag`/`As*`/`TryAs*` 표면은 유지한다. 스냅샷은 추가 API다.

## Done When

- 값 스냅샷 union에서 tag와 payload 읽기가 native 호출 1회로 끝나는 것이 테스트로 확인된다.
- cgo와 purego 생성물이 같은 공개 API를 제공하고 두 백엔드 테스트가 통과한다.
