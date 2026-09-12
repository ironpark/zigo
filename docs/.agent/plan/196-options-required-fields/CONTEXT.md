# SCOPE

`src/gen/validate/functions.zig`, `src/gen/validate/names.zig`, `src/gen/abi_diff.zig`,
`src/gen/emit/public.zig`, `src/gen/emit/public_writers.zig`, 새 generator case,
`docs/authoring/values-and-data.md`, `docs/reference/diagnostics.md`,
`docs/reference/generated-go-api.md`, `CHANGELOG.md`.

lowering(`src/gen/lower.zig`)과 shim은 건드리지 않습니다. 나열된 필드는 이미 각각 ABI
매개변수를 가지므로 필요한 변경은 Go 공개 표면에만 있습니다.

# CONTEXT

## Current implementation and bottlenecks

`.options`는 `.flatten`과 같은 lowering을 씁니다. 나열된 필드마다 ABI 매개변수가 하나씩
생기고(`src/gen/lower.zig:101`), shim이 그 매개변수들로 구조체를 다시 조립합니다. `.options`가
더하는 것은 Go 표면뿐입니다: 공개 시그니처에서 필드를 감추고(`public.zig:1150`), 설정 구조체와
`With*`를 내고, 호출 인자를 `cfg.<field>`로 씁니다.

그 Go 표면이 필드를 둘로 나누지 못합니다. `is_options`라는 하나의 bool이 매개변수 전체를
옵션으로 취급하고(`public.zig:560`, `public.zig:678`, `public_writers.zig:209`), 검증은 기본값이
없는 필드를 아예 거절합니다(`functions.zig:207`). 그래서 필수 값을 가진 구조체는 `.options`로
들어올 수 없습니다.

## Target structure and invariants

나누는 기준은 필드의 `default` 하나입니다.

- `field.default == null` -- 위치 인자. Go 이름은 `.flatten`이 쓰는 것과 같은
  `flattenedGoNameAlloc(abi_parameter.name)`이고, 값의 출처는 그 Go 매개변수입니다.
- `field.default != null` -- 옵션. 설정 구조체 필드와 `With*` 생성자가 생기고, 값의 출처는
  `cfg.<field>`입니다.

불변:

- ABI는 필드 분류와 무관합니다. 어떤 필드가 위치 인자가 되어도 C 시그니처는 그대로입니다.
- 옵션 필드가 하나도 없는 `.options`는 계속 `ZIGO061`입니다. 그 선언이 원하는 것은
  `.flatten`이고, hint가 그렇게 말합니다.
- 위치 인자의 순서는 선언한 필드 순서입니다. 옵션 가변 인자는 언제나 마지막입니다.
- 기본값이 있는 필드만 `With*` 이름을 만들므로 이름 충돌 검사도 그 필드만 봅니다.
