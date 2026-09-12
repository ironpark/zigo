---
completed_at: "2026-09-12T04:00:13Z"
depends_on:
- "192-go-functional-options#0"
perf_phase: false
status: done
---
> DONE-WHEN: `zigo.param.options(1, &.{ "cols", "rows" }, .{})`가 컴파일되고 문서에
> NEXT: none

# `zigo.param.options` authoring API

## Planned Work

- `src/param.zig`에 `options(index, fields, options)`를 추가한다. 계약은 `.flatten`과
  같게 lowering되고, Go 전용 의도만 `ParamGo`로 간다.
- `semantic.ParamGo`에 `options: ?OptionsSpec = null`을 추가한다. `OptionsSpec`은
  `type_name: ?[]const u8`과 `prefix: ?[]const u8`을 가진다. 둘 다 `null`이면
  타입 접두사 기본값을 쓴다. `ParamGo.compact`도 새 필드를 반영한다.
- `src/author.zig`, `src/declare.zig`, `src/normalize.zig`가 새 계약을 통과시키도록
  한다. `.flatten` 경로의 동작은 바꾸지 않는다.
- `zigo.param.flatten`으로 선언한 함수의 생성 결과가 그대로임을 지키는 테스트를 둔다.

## Done When

- `zigo.param.options(1, &.{ "cols", "rows" }, .{})`가 컴파일되고 문서에
  `go.options`가 나타난다.
- `.prefix`를 준 선언이 문서에 그 값을 싣는다.
- `.flatten` 선언의 `semantic.json`과 생성 Go가 변경 전과 동일하다.
