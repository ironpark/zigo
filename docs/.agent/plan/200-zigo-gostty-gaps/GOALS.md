# GOALS

## Problem and the end result from the user's point of view

gostty를 쓰면서 zigo에 기능이 없어 우회한 자리 일곱 군데를 없앤다. 바인딩 작성자가 겪는 것은
이것이다: Go 문서에 `corresponds to the Zig field ...` 플레이스홀더가 353줄 깔려 있고,
`std.log` 진단이 embedder에 닿지 않고, `Search`의 session 접근자가 `Searchs`가 되고,
호출자 버퍼의 앞부분을 돌려주는 함수마다 래퍼 Zig 함수를 손으로 쓰고, 실패할 수 없는 필드
읽기 42개가 Go 메서드 84개가 되고, 한 핸들에 생성자를 하나밖에 못 달고, tagged union이
slice 원소와 error union 자리에 못 온다. 끝나면 이 우회들이 바인딩 선언 한 줄로 대체된다.

## Measurable goals

- 생성된 shim이 `std_options`를 타겟 root에서 전달해 embedder가 `logFn`을 걸 수 있다.
- `SessionChild.plural`이 `Searches` 같은 불규칙 복수를 접근자 이름에 쓴다.
- 리플렉터가 컨테이너 멤버의 `///` doc을 `fields[].doc`으로 싣고, 생성된 Go enum 상수와
  값 struct 필드가 플레이스홀더 대신 그 문서를 단다.
- `ValueField.doc`과 `Enum.fields[].doc`으로 바인딩이 멤버 문서를 직접 쓸 수 있다.
- `.written = .returned_slice`가 반환 slice의 길이를 written으로 취해 래퍼 없이 통과한다.
- 플러그인이 생성기의 public 메서드를 억제하고 자신의 것으로 대체할 수 있다.
- 한 핸들에 생성자를 여러 개 달 수 있고, 두 번째부터는 `.name`으로 Go 이름을 가른다.
- tagged union 값이 out slice 원소와 error union payload 자리에 올 수 있다.

## Supported scope and non-goals

지원: 위 여덟 항목, 진단·문서·CHANGELOG·릴리즈. 비지원: union을 in slice로 받는 경로,
멤버 doc의 Rust 백엔드 반영, `must` 내장 플러그인의 per-declaration 옵션 신설,
생성자 여러 개에 대응하는 destructor 여러 개.

## Reference source / commit / license

src/declare.zig, src/reflect/names.zig, src/reflect/walk.zig, src/gen/ir/semantic.zig,
src/gen/emit/shim.zig, src/gen/emit/public_types.zig, src/gen/lower.zig,
src/gen/validate/functions.zig, src/plugin.zig, src/gen/plugins/must.zig. MIT.

## Completion criteria for the whole plan

`zig build test` 통과, generator case 골든 갱신, docs·CHANGELOG 반영, 버전 태그 커밋.
