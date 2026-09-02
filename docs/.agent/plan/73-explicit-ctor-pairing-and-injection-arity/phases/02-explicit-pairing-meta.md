---
completed_at: "2026-09-02T13:01:46Z"
depends_on:
- "73-explicit-ctor-pairing-and-injection-arity#1"
perf_phase: false
status: done
---
> DONE-WHEN: 메타로 짝지은 예제가 cgo·purego 통과, 진단 스냅샷 테스트 추가, 커밋.
> NEXT: none

# .constructs / .destroys 메타

## Planned Work

- 함수 메타 `.constructs`/`.destroys` 반영(`walk.zig` 짝짓기 메타 우선, 이름 규칙 fallback 유지).
- 검증: 반환/첫 파라미터 타입 불일치, 한쪽만 지정, 같은 타입에 중복 지정 → `ZIGO028` 진단 스냅샷.
- 예제: root 레벨 `newTerminal`/`freeTerminal` 형태를 기존 third-party 예제(67/69에서 만든 것) 또는 신규 예제에 추가, cgo·purego 골든.

## Done When

- 메타로 짝지은 예제가 cgo·purego 통과, 진단 스냅샷 테스트 추가, 커밋.
