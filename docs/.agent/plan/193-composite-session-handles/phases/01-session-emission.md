---
completed_at: "2026-09-12T05:36:08Z"
depends_on:
- "193-composite-session-handles#0"
perf_phase: false
status: done
---
> DONE-WHEN: 선언한 세션마다 Go 파일이 생성되고 구조체, 생성자, 접근자가 들어 있다.
> NEXT: none

# Session 타입과 접근자 방출

## Planned Work

- 내장 플러그인 `SESSION`을 만들고 `src/gen/plugins/builtins.zig`에 등록한다.
  구조는 `src/gen/plugins/interfaces.zig`를 따른다: 선언 key, 전용 파일 entry,
  자체 진단 접두사, `analyze`에서 계산하고 렌더링은 읽기만.
- 패키지마다 Go 파일 하나에 그 패키지의 모든 세션을 쓴다. 내용은 멤버를 담는 구조체,
  멤버 순서대로 받는 `New<Name>` 생성자, 멤버마다의 접근자다.
  (계획은 "선언마다 파일 하나"를 적었지만 `Plugin.source_files`는 comptime 고정 목록이라
  선언 수만큼 파일을 늘릴 수 없습니다. 인터페이스 플러그인과 같은 방식으로 패키지당 파일
  하나를 씁니다.)
- 접근자 이름은 멤버 타입 이름을 쓴다. 공개 이름 검사는 `src/gen/validate/names.zig`와
  `src/plugin/interfaces.zig`의 선례를 따라 `src/plugin/session.zig`의 `collisionIssue`가
  맡는다: 세션 이름과 `New<Name>` 생성자가 같은 패키지의 타입·함수와 겹치는지, 멤버의
  접근자가 세션이 스스로 선언하는 `Close`와 겹치는지.
- doc comment에 닫는 순서를 명시한다. 소비자가 생성 코드만 읽고도 계약을 알아야 한다.
- 골든 테스트를 추가한다.

## Done When

- 선언한 세션이 Go 파일에 구조체, 생성자, 접근자로 나타나고, 멤버 필드 이름이 Go 규칙을
  따른다(`Queue` → `queue`).
- 접근자나 생성자 이름이 같은 패키지의 다른 이름과 겹치면 진단이 나오고 어느 둘인지 말한다.
- shim, header, raw, purego 골든이 변하지 않는다.
