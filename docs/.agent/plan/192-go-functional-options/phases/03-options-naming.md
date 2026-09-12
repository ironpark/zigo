---
completed_at: "2026-09-12T04:07:44Z"
depends_on:
- "192-go-functional-options#1"
perf_phase: false
status: done
---
> DONE-WHEN: 기본 선언이 `TerminalOption`, `WithTerminalRows`를 만든다.
> NEXT: none

# 옵션 타입과 `With*` 이름

## Planned Work

- 옵션 타입 이름과 `With*` 함수 이름을 만드는 단일 진입점을 둔다. 기본값은
  `<Type>Option`과 `With<Type><Field>`이고, `.prefix`가 접두사를 대체한다.
  `.prefix = ""`는 `Option`, `With<Field>`를 뜻한다.
- 생성자가 타입에 속하지 않는 free 함수인 경우의 기본 접두사를 정한다.
- `src/reflect/names.zig`의 공개 이름 공간에 생성 이름을 등록해 다른 타입,
  함수, 메서드, `Must` 변형과의 충돌을 기존 경로에서 잡는다. 충돌 진단은
  `src/gen/plugins/must.zig:36`의 `ZIGO024` 보고 방식을 따른다.
- 이름 생성과 충돌 각각에 단위 테스트를 둔다.

## Done When

- 기본 선언이 `TerminalOption`, `WithTerminalRows`를 만든다.
- `.prefix = ""`가 `Option`, `WithRows`를 만든다.
- 같은 패키지의 다른 선언과 이름이 겹치면 진단이 나오고 어느 두 선언인지 말한다.
