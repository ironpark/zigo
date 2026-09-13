---
completed_at: "2026-09-13T08:10:53Z"
perf_phase: false
status: done
---
> DONE-WHEN: 한 핸들이 `NewTerminal`과 `TerminalFromSnapshot`을 함께 낸다.
> NEXT: none

# Multiple constructors per handle

## Planned Work

- 한 타입에 `.constructs`가 둘 이상인 것을 허용하고, 모두 같은 destructor에 짝지운다.
- 두 번째부터는 Go 이름이 갈리도록 요구하고, 겹치면 진단으로 거절한다.
- `constructors`를 타입으로 조회하던 자리들이 여러 항목을 견디는지 확인한다.
- generator case로 두 생성자를 가진 핸들을 고정한다.

## Done When

- 한 핸들이 `NewTerminal`과 `TerminalFromSnapshot`을 함께 낸다.
- 생성자가 하나인 기존 골든이 변하지 않는다.
