# SCOPE

`src/features.zig`, `src/author.zig`, `src/declare.zig`, `src/normalize.zig`,
`src/reflect/walk.zig`, `src/gen/ir/semantic.zig`, `src/gen/plugins/implements.zig`,
`src/gen/validate/names.zig`, `src/gen/validate/functions.zig`,
`tests/generator_cases/implements_std{,_purego}`, `examples/11-io-streams`,
`docs/authoring/streams-and-cancellation.md`, `docs/reference/binding-api.md`,
`CHANGELOG.md`.

# CONTEXT

## Current implementation and bottlenecks

`.implements`는 선언에서 semantic까지 단수로 흐릅니다. 플러그인 옵션의 `kind`가
`Extension.builtin`에 담기고, normalize가 그것을 `declare.Function.implements`에 넣고,
walk가 `FnGo.implements`에 옮깁니다. 방출과 검증은 그 하나를 읽습니다.

막는 것은 두 곳입니다. `.use`가 같은 플러그인의 두 번째 부착을 컴파일 타임에 거절하고,
옵션 타입에 kind가 하나뿐입니다. 앞의 규칙은 플러그인 옵션 조회가 첫 항목만 본다는 사실에
기대고 있으므로 풀 수 없습니다. 그래서 목록은 옵션 안에 있어야 합니다.

## Target structure and invariants

- 플러그인 옵션은 `kind`(하나)와 `kinds`(목록)를 함께 가지며 정확히 하나를 써야 합니다.
  둘 다 주거나 아무것도 주지 않으면 컴파일 오류입니다.
- 선언·schema·semantic의 `implements`는 모두 목록입니다. 단수 spelling은 `kind`뿐입니다.
- `semantic.json`의 `go.implements`는 문자열 배열입니다. 문자열 하나로 적힌 옛 문서는
  `migrate`가 한 원소 배열로 옮깁니다. 규칙은 모양에 기대므로 멱등입니다.
- 방출은 나열된 순서대로 래퍼를 냅니다. 검증도 같은 순서로 각 kind를 따로 봅니다.
- 한 함수의 kind 목록에 같은 kind가 두 번 오면 거절합니다. 래퍼 이름이 같아지기 때문입니다.
