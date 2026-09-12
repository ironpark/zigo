---
perf_phase: false
status: in-progress
---
> DONE-WHEN: `zigo.session(.{ .name = "Session", .primary = EventQueue.typeRef(), .children = &.{Stream.typeRef()} })`가
> NEXT: none

# 선언 표면과 관계 검증

## Planned Work

- `src/author.zig`에 `Session` 옵션 구조체와 `zigo.session(options)` entry 생성자를
  추가한다. 필드는 `name`, `primary`, `children`, `doc`이다. `src/dsl.zig`에서 내보낸다.
- `src/normalize.zig`가 새 entry를 걷고, `semantic.zig`에 session 선언을 싣는다.
  `abi.zig`에는 렌더링이 필요한 만큼만 옮긴다.
- 진단을 추가한다: `children`이 빈 목록, 같은 타입 중복, primary와 자식이 같음,
  자식이 primary의 dependent child가 아님, 멤버가 서로 다른 생성 패키지에 있음,
  멤버가 `Close`를 갖지 않음(borrowed 뷰나 `Ref`).
- 새 진단 코드를 `docs/reference/diagnostics.md`에 등록한다.
- 각 규칙의 단위 테스트를 둔다.

## Done When

- `zigo.session(.{ .name = "Session", .primary = EventQueue.typeRef(), .children = &.{Stream.typeRef()} })`가
  컴파일되고 문서에 선언이 나타난다.
- 위 여섯 가지 잘못된 선언이 각각 오류 진단을 내고 hint가 고치는 방법을 말한다.
- 유효한 선언이 진단 없이 통과하고, session 선언이 없는 바인딩의 출력은 그대로다.
