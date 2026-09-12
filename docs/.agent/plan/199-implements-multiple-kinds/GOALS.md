# GOALS

## Problem and the end result from the user's point of view

한 메서드에 `.implements`를 두 번 붙일 수 없습니다. `.use`는 플러그인당 한 항목만 허용하고
(`zigo duplicate plugin attachment: IMPLEMENTS`), 옵션도 `kind` 하나뿐입니다. 그래서 바이트를
받는 메서드 하나가 `io.Writer`와 `io.StringWriter`를 함께 만족시킬 방법이 없습니다.

0.24.0이 `.string_writer`의 바이트 매개변수를 열어 준 뒤 이것이 남은 벽이 되었습니다.
`Stream.feed` 같은 메서드는 이미 `.writer`로 `fmt.Fprintf`를 받고 있어서, 복사 없는
`WriteString`을 더하려면 `.writer`를 포기하거나 손으로 써야 합니다. 소비자는 손으로 썼습니다.

이 계획이 끝나면 한 선언이 kind 목록을 받아, 같은 메서드 위에 래퍼를 여러 개 냅니다.

```zig
Stream.func("feed", .{}).use(zigo.features.implements, .{ .kinds = &.{ .writer, .string_writer } }),
```

## Measurable goals

- `.kinds`로 두 개 이상의 kind를 선언한 메서드가 각 kind의 래퍼를 모두 얻는다.
- `.kind` 하나를 쓰는 기존 선언의 생성 출력이 한 글자도 바뀌지 않는다.
- 각 kind는 지금과 같은 규칙으로 따로 검증된다. 한 kind가 shape에 맞지 않으면 그 kind를
  가리키는 `ZIGO058`이 난다.
- 같은 메서드에서 나온 래퍼 이름이 겹치거나 이미 있는 Go 메서드와 겹치면 `ZIGO024`가 난다.
  같은 kind를 두 번 나열하는 것도 거절한다.
- `semantic.json`의 `go.implements`가 배열이 되고, 문자열로 적힌 기존 문서도 그대로 읽힌다.
- 예제 하나가 메서드 하나로 `io.Writer`와 `io.StringWriter`를 함께 만족시킨다.

## Supported scope and non-goals

`.implements`가 이미 아는 다섯 kind의 조합만 지원합니다.

non-goal:

- 플러그인을 한 함수에 두 번 붙일 수 있게 하는 일반 규칙. `.use`의 중복 금지는 그대로입니다.
- `.iterator`나 다른 built-in의 다중 부착.
- `implements` 변화를 ABI diff가 Go 표면 변경으로 보고하는 일. 지금도 보지 않으며 별도
  작업입니다.
- Rust target.

## Reference source / commit / license

외부 소스를 가져오지 않습니다.

- `src/features.zig:8` -- 플러그인 옵션 `kind`
- `src/author.zig:237` -- `.use`가 built-in 페이로드로 옮기는 자리
- `src/normalize.zig:196` -- 선언에서 schema로
- `src/reflect/walk.zig:1165` -- schema에서 semantic으로
- `src/gen/ir/semantic.zig:765` -- `FnGo.implements`
- `src/gen/ir/semantic.zig:1279` -- `migrate`가 옛 문서를 옮기는 자리
- `src/gen/plugins/implements.zig` -- 검증과 래퍼 방출
- `src/gen/validate/names.zig:122` -- 래퍼 이름 충돌 검사

## Completion criteria for the whole plan

모든 phase가 done이고 `zig build test`가 통과하며, 예제가 메서드 하나로 두 인터페이스를
만족시키는 것을 cgo·purego 양쪽에서 보여 줍니다.
