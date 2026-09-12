# SCOPE

- `ZIGO061` hint 문구와 그 테스트.
- `docs/authoring/values-and-data.md`, `docs/reference/diagnostics.md`,
  `docs/reference/generated-go-api.md`의 옵션 설명.
- `examples/07-event-queue`의 `Terminal.init` 선언과 생성 Go 테스트.
- `tests/generator_cases`의 옵션 골든 케이스와 그 `expected` 트리.

제외: 생성기의 lowering·shim·방출 로직, `.flatten` 동작, Rust target, plugin 계약.

# CONTEXT

## Current implementation and bottlenecks

- 옵션 매개변수의 모든 필드는 기본값을 가져야 하고(`src/gen/validate/functions.zig:206`),
  나열되지 않은 필드도 기본값을 가져야 합니다(`src/reflect/walk.zig:1203`). 두 규칙이
  맞물려 "기본값 없는 필드를 옵션 구조체 안에 두는" 모든 형태가 거절됩니다.
- 그런데 `ZIGO061` hint는 "expose it as a positional parameter"라는, 위 규칙 안에서 실행
  불가능한 해법을 안내합니다.
- 필수 값을 옵션 구조체 밖 함수 매개변수로 옮기면 emitter가 가변 인자를 마지막에 붙이므로
  (`src/gen/emit/public.zig:1179-1197`) 원하는 혼합 시그니처가 그대로 나옵니다. 실측으로
  `func NewTerminal(initialCols uint16, opts ...Option) (*Terminal, error)`와
  `raw.TerminalInit(initialCols, cfg.rows, cfg.maxScrollbackBytes)` 생성을 확인했습니다.
- 골든은 `tests/generator_cases/<case>/{semantic.json,options.json,expected/}` 형태이고
  케이스 발견은 디렉터리 순회로 자동입니다(`build/tests.zig:900`). `tests/generator_cases`
  전체에 `func With`가 한 건도 없어 방출 경로는 예제의 `.prefix = ""` 경우로만 실행됐습니다.

## Target structure and invariants

- 규칙: 선택 값은 옵션 구조체에 기본값과 함께, 필수 값은 함수의 별도 매개변수로.
- 불변: flatten은 구조체 필드를 각각 ABI 매개변수로 내리므로 필수 필드를 구조체 밖으로
  옮겨도 C 매개변수의 개수와 순서가 같습니다. 따라서 `abi-check`는 차이를 보고하지 않습니다.
- 불변: 옵션 방출은 Go 표면에만 작용하며 shim·header·raw는 `.flatten`과 동일합니다.
