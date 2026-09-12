# SCOPE

건드리는 곳:

- `src/gen/ir/semantic.zig` -- `FlattenedField.default`, `ParamGo.options`
- `src/reflect/walk.zig` -- 선택 필드의 Zig 기본값 수집
- `src/param.zig`, `src/author.zig`, `src/declare.zig`, `src/normalize.zig` -- authoring API
- `src/gen/validate/functions.zig` -- 옵션 계약 진단
- `src/reflect/names.zig`, `src/gen/emit/common.zig` -- 옵션 타입·`With*` 이름과 충돌
- `src/gen/emit/public.zig` -- 시그니처, 옵션 적용 본문, 인자 포워딩
- `examples/07-event-queue` -- 인수 예제와 Go 테스트
- `docs/authoring/values-and-data.md`, `docs/reference/binding-api.md`,
  `docs/reference/generated-go-api.md`, `docs/reference/diagnostics.md`, `CHANGELOG.md`

건드리지 않는 곳: `src/gen/emit/shim.zig`, `header.zig`, `raw.zig`, `purego.zig`,
`src/gen/emit_rust/`, `src/gen/abi_diff.zig`의 판정 규칙.

# CONTEXT

## Current implementation and bottlenecks

`zigo.param.flatten(index, fields)`(`src/param.zig:23`)는 매개변수 계약을
`.flatten = fields`로 둡니다. reflection(`src/reflect/walk.zig:915`)이 선택 필드를
`semantic.FlattenedField`로 기록하고, 선택하지 않은 필드는 Zig 기본값이 있어야 한다고
검사합니다(`walk.zig:1160`). lowering(`src/gen/lower.zig:101`)이 필드마다 ABI 매개변수를
하나씩 만들고 `flatten_start`로 위치를 기록하며, shim(`src/gen/emit/shim.zig:828`)이
`Options{ .cols = cols, ... }`로 구조체를 되조립합니다. 공개 Go 계층
(`src/gen/emit/public.zig:374`, `:480`, `:896`)은 이 필드들을 그대로 위치 인자로 씁니다.

병목은 하나입니다. `semantic.FlattenedField`(`src/gen/ir/semantic.zig:468`)는
`name`, `type`, `atomic`만 가지고, reflection은 `default_value_ptr`를 존재 여부로만
확인한 뒤 버립니다. Go가 `With*`를 받지 않은 필드에도 ABI로 값을 보내야 하므로
기본값이 문서에 실리지 않으면 옵션 패턴을 만들 수 없습니다.

## Target structure and invariants

- 기본값은 `FlattenedField.default`로 `semantic.json`에 실립니다. 이름을 옮기지 않는
  순수 추가이고, `go.options`를 가진 문서는 기본값을 쓰는 generator만 만들 수 있으므로
  `ir_version`은 2에 머뭅니다. 옛 문서는 `default`가 없고 `go.options`도 없어
  지금과 같은 위치 인자 경로로 읽힙니다. migration 항목도 추가하지 않습니다.
- 옵션화 여부는 출력 언어 전용 정보이므로 `Parameter.go`(`ParamGo`)에 둡니다.
  ir_version 2가 세운 "Go 전용 필드는 `go` 객체로 모은다"는 관례를 그대로 따릅니다.
- ABI는 불변입니다. lowering, shim, header, raw, purego는 옵션 매개변수를 `.flatten`과
  구분하지 않습니다. 옵션 적용은 전적으로 공개 Go 함수 본문 안에서 끝납니다.
- 이름 기본값은 타입 접두사입니다: `TerminalOption`, `WithTerminalRows`. `.prefix`로
  짧은 형태(`Option`, `WithRows`)를 고를 수 있고, 충돌은 진단으로 잡습니다.
- 기본값이 있는 필드만 옵션이 됩니다. 기본값이 없는 필드는 위치 인자로 남고,
  옵션으로 지정하면 오류입니다.
