---
depends_on:
- "193-composite-session-handles#0"
perf_phase: false
status: planned
---
> DONE-WHEN: 선언한 세션마다 Go 파일이 생성되고 구조체, 생성자, 접근자가 들어 있다.
> NEXT: none

# Session 타입과 접근자 방출

## Planned Work

- 내장 플러그인 `SESSION`을 만들고 `src/gen/plugins/builtins.zig`에 등록한다.
  구조는 `src/gen/plugins/interfaces.zig`를 따른다: 선언 key, 전용 파일 entry,
  자체 진단 접두사, `analyze`에서 계산하고 렌더링은 읽기만.
- 선언마다 Go 파일 하나를 쓴다. 내용은 멤버를 담는 구조체, 멤버 순서대로 받는
  `New<Name>` 생성자, 멤버마다의 접근자다.
- 접근자 이름은 멤버 타입 이름을 쓰고, 충돌하면 진단한다. `src/reflect/names.zig`의
  공개 이름 공간에 타입 이름과 접근자 이름을 등록한다.
- doc comment에 닫는 순서를 명시한다. 소비자가 생성 코드만 읽고도 계약을 알아야 한다.
- 골든 테스트를 추가한다.

## Done When

- 선언한 세션마다 Go 파일이 생성되고 구조체, 생성자, 접근자가 들어 있다.
- 접근자 이름이 같은 패키지의 다른 이름과 겹치면 진단이 나오고 어느 둘인지 말한다.
- shim, header, raw, purego 골든이 변하지 않는다.
