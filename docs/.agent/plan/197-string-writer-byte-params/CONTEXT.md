# SCOPE

`src/gen/plugins/implements.zig`, `src/gen/validate/functions.zig`의 관련 테스트,
`tests/generator_cases/implements_std{,_purego}`, `examples/11-io-streams`,
`docs/authoring/streams-and-cancellation.md`, `docs/reference/binding-api.md`,
`docs/reference/diagnostics.md`, `CHANGELOG.md`.

# CONTEXT

## Current implementation and bottlenecks

`implementsIssue`는 kind마다 하나의 `shape_ok` 식을 가집니다. `.string_writer`는
`semantic.isTextHint(data.semantic)`을 요구하고, 바이트 매개변수에는 "`.utf8_string`이나
`.c_string`을 주거나 `.writer`를 쓰라"는 hint를 냅니다. 그 조건이 묻는 것은 "매개변수가 Go
`string`에 도달하는가"입니다.

래퍼 방출(`renderImplementsWrapper`)은 그 전제 위에 있습니다. `.string_writer` 가지는 인자
`s`를 그대로 메서드에 넘깁니다 -- 메서드의 Go 매개변수가 이미 `string`이기 때문입니다.
바이트 매개변수에서는 메서드가 `[]byte`를 받으므로 이 호출이 컴파일되지 않습니다.

## Target structure and invariants

조건이 물어야 할 것은 "빌려 온 읽기 전용 바이트인가"입니다. `.string_writer`는 두 입력을
받습니다.

- string semantic이 있는 `[]const u8` -- 지금과 같습니다. 래퍼가 `s`를 그대로 넘깁니다.
- string semantic이 없는 `[]const u8` -- 래퍼가 문자열의 바이트를 빌려 넘깁니다.

불변:

- 두 경우 모두 래퍼는 복사를 만들지 않습니다. 그것이 이 kind의 존재 이유입니다.
- 빌린 슬라이스는 호출 동안만 삽니다. 래퍼는 그것을 메서드 호출 밖으로 내보내지 않습니다.
- 빈 문자열은 길이 0의 슬라이스가 됩니다. `unsafe.Slice(p, 0)`은 `nil` 슬라이스이고,
  `.writer`가 빈 `p`에 대해 하는 것과 같습니다.
- `.writer`의 조건은 바뀌지 않습니다. string semantic이 붙은 `.writer`는 계속 거절됩니다.
- `unsafe` import는 본문이 그 qualifier를 쓸 때만 추가됩니다. 기존 import 결정 방식을
  그대로 쓰므로 바이트 `.string_writer`가 없는 파일의 import 블록은 바뀌지 않습니다.
