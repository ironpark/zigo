# GOALS

## Problem and the end result from the user's point of view

(A) `lib.Enum(.zig, ...)` 같은 comptime 생성 enum은 Zig가 `@typeName`을 잘라내 서로 다른 타입이 같은 문자열을 갖는다. reflection은 `zig_path == @typeName(T)`(`walk.zig:889, 905, 916`)로 등록 타입을 찾으므로 `Charset`, `CharsetSlot`, `CursorStyle`(모두 4-tag)이 먼저 등록된 하나로 접힌다. 결과는 **컴파일되는 잘못된 Go**다: `ConfigureCharset(slot CursorStyle, set CursorStyle)`. 진단이 없어 가장 심각하다. (B) `ZIGO021`이 enum tag `80_cols`를 단독 식별자로 검사해 거부하지만 실제 emit 이름은 `DeccolmMode80Cols`로 유효하다.

끝난 뒤: 등록 타입 판별은 comptime 타입 동일성(`entry.type == T`)으로 이루어져 같은 철자의 타입이 섞이지 않고, `@typeName`이 겹치는 등록 타입은 semantic.json에서도 구분된다. 숫자로 시작하는 tag는 `<Type><Pascal(tag)>`가 유효하면 통과한다.

## Measurable goals

- 같은 모양(4-tag, 같은 `@typeName`)의 comptime enum 두 개를 등록하고 각각을 파라미터로 받는 함수가 서로 다른 Go 타입으로 생성되는 walk 단위 테스트와 골든.
- `enum { @"80_cols", @"132_cols" }`가 `DeccolmMode80Cols`로 생성되고, 정말 유효하지 않은 경우(예: tag가 Pascal 변환 후에도 비어 있음)만 ZIGO021.
- 기존 예제 생성물 바이트 동일.

## Supported scope and non-goals

- 범위: `walk.zig` 타입 판별(enum, value struct, tagged union, callback), semantic.json의 `zig_path` 유일성, `validate.zig` 식별자 검사, 골든, 문서, CHANGELOG.
- 비범위: `@typeName` 잘림 자체를 복원하는 것.

## Reference source / commit / license

`src/reflect/walk.zig:883-920`(typeNode의 등록 타입 매칭), `:1043-1055`(callback 매칭), `src/gen/validate.zig:715-745`(식별자 검사), gostty `docs/zigo-findings.md` A·B. 라이선스 변경 없음.

## Completion criteria for the whole plan

모든 phase done, `zig build test`·`zig fmt --check`·전 예제 cgo+purego 녹색, CHANGELOG Unreleased Fixed 두 건.
