---
completed_at: "2026-09-05T08:34:35Z"
depends_on:
- "112-112-explicit-interfaces#0"
perf_phase: false
status: done
---
> DONE-WHEN: `zig build test` 녹색, golden 불변.
> NEXT: none

# Structural validation

## Planned Work

- `validate/interfaces.zig`에 `interfaceIssue` 규칙을 추가하고 규칙 표에서 `names.publicNameCollisionIssue`
  뒤에 둔다. 순서: (1) 이름이 Go 식별자, (2) `.types` 각 이름이 등록 opaque 타입이고 중복이 없다,
  (3) 각 타입이 `.methods`의 각 이름을 receiver 메서드로 노출한다, (5) `.closer`인데 생성자 짝이 없는
  타입, (6) 하위 패키지가 있을 때 인터페이스와 모든 타입이 같은 패키지. 모두 ZIGO049.
- 이름 충돌: 인터페이스 이름이 같은 패키지의 등록 타입, receiver 없는 함수의 공개 이름, 다른
  인터페이스와 겹치면 기존 ZIGO024 경로에서 보고한다.
- `snapshot_tests.zig`에 ZIGO049 각 규칙과 ZIGO024 인터페이스 충돌 스냅샷을 추가한다.

## Done When

- `zig build test` 녹색, golden 불변.
- 스냅샷 테스트가 규칙별로 하나씩 있다.
