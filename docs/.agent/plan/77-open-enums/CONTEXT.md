# SCOPE

- 타입 등록 `.{ .name, .type, .repr = .enumeration, .exhaustive = false }`. `walk.zig`가 이를 `TypeDecl`에 반영(예: `open: ?bool` 또는 기존 `exhaustive`와 별도의 opt-in 필드). semantic.json에는 opt-in이 있을 때만 필드가 나타난다.
- `validate.zig`: opt-in이 있으면 ZIGO002를 내지 않는다. exhaustive enum에 opt-in이 달리면 새 진단(다음 빈 코드).
- emit: 비exhaustive enum의 Go 타입 doc에 "open enum; values outside the named constants are valid"를 적는다. shim의 `@enumFromInt`는 비exhaustive에서 항상 유효하므로 변경 없음. Go `String()`의 `default`는 이미 있다.
- abi_diff: exhaustive ↔ open 전환은 breaking으로 보고.
- 예제(09-type-relations 또는 01)에 open enum 케이스와 미지의 값 round-trip Go 테스트 추가. 골든 케이스 추가.
- 문서: `docs/bindings.md`(등록 옵션), `docs/limitations.md`(ZIGO002 문구, tagged union tag 제외), `docs/generated-code.md`, `CHANGELOG.md`.

# CONTEXT

## Current implementation and bottlenecks

- `walk.zig`는 `info.is_exhaustive`를 `TypeDecl.exhaustive`에 그대로 적고 `validate.zig:268`이 false면 ZIGO002.
- 생성된 Go enum은 `type Name <int>` + `const (...)` + `String()`으로, `default` 분기가 `Name(N)`을 돌려준다. 열린 값을 이미 표현할 수 있다.
- shim은 파라미터를 `@enumFromInt`로, 반환을 `@intFromEnum`으로 바꾼다. exhaustive enum에서 범위 밖 값은 safety-check 패닉이지만 비exhaustive에서는 정의된 동작이다.

## Target structure and invariants

- opt-in은 타입 등록에 둔다(함수 메타가 아님). Zig 타입이 실제로 비exhaustive여야 하고, 그렇지 않으면 진단.
- semantic.json 스키마: 기존 `exhaustive: bool`은 유지하고 opt-in 필드를 추가하되 기본값이면 생략해 기존 문서가 바뀌지 않게 한다.
- Go 표면은 exhaustive enum과 동일한 형태(타입·상수·`String()`)이며 doc 문구만 다르다. 이름 충돌 검사(ZIGO024)는 그대로 적용된다.
- 비exhaustive tag를 가진 tagged union은 계속 ZIGO002 계열로 거부한다. 이유: snapshot/projection이 tag별 분기를 전제한다.
