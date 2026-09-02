# GOALS

## Problem and the end result from the user's point of view

남의 라이브러리(예: `vt.Terminal`)를 바인딩할 때 타입에 메서드를 더할 수 없으므로 root 레벨 `newTerminal`/`freeTerminal`을 생성자/소멸자로 짝지을 방법이 없다. 이름 규칙(`init/create/new/open`, `deinit/destroy/close`)과 `receiver == 타입` 조건이 유일한 관문이고, `.returns = .caller`는 이미 짝이 있어야 하므로(ZIGO015) 탈출구가 아니다. 이름 규칙을 억지로 맞추면 shim이 `target.Terminal.new(...)`처럼 root 함수를 타입 경로로 호출해 컴파일이 깨진다. 또 `.allocator`/`.io` 주입 파라미터가 `.params` 인덱싱과 `.release` 시그니처 매칭에서 여전히 자리를 차지해, `.params` 길이가 짧으면 zigo 내부 comptime 인덱스 에러로 터지고 allocator를 주입받는 release 함수는 항상 ZIGO016이다.

끝난 뒤 사용자는 `.constructs = "Terminal"` / `.destroys = "Terminal"` 메타로 어떤 이름·위치의 함수든 짝지을 수 있고, `.params`에는 Go에 보이는 파라미터 이름만 적으며, release 함수도 allocator를 주입받을 수 있다.

## Measurable goals

- root 레벨 `fn newTerminal(...) !*Terminal` + `fn freeTerminal(*Terminal) void`를 `.constructs`/`.destroys`로 짝지은 예제가 cgo·purego 모두 통과.
- 주입 파라미터를 뺀 `.params`가 통과하고, 길이 불일치는 내부 에러가 아니라 `ZIGO027` 진단.
- `fn free(gpa: Allocator, s: []const u8) void`를 `.release`로 지정할 수 있고 shim이 allocator를 주입한 채 호출.

## Supported scope and non-goals

- 범위: `walk.zig` 짝짓기·arity, `validate.zig` release 매칭·새 진단, `emit.zig` shim 호출 경로, 문서·CHANGELOG·예제·골든.
- 비범위: 이름 규칙 자체를 없애는 것(fallback으로 유지), 다중 소멸자, 소멸자가 값을 반환하는 형태.

## Reference source / commit / license

`src/reflect/walk.zig:104-116, 199-209`, `src/gen/validate.zig:1182-1197`, `src/gen/emit.zig:694-701`, `docs/bindings.md:560-620`. 라이선스 변경 없음.

## Completion criteria for the whole plan

모든 phase done, `zig build test`·`zig fmt --check`·전 예제 cgo+purego 녹색, CHANGELOG Unreleased에 Added/Fixed 기재.
