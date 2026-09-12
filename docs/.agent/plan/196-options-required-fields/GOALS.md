# GOALS

## Problem and the end result from the user's point of view

`zigo.param.options`는 나열된 모든 필드가 Zig 기본값을 가질 것을 요구합니다(`ZIGO061`).
그래서 기본값이 옳지 않은 값(터미널의 `cols`·`rows`처럼 부를 사람만 아는 값)과 기본값이
있는 값을 한 구조체에 담은 라이브러리는 `.options`를 쓸 수 없습니다. 소비자는 `.flatten`으로
내려가 모든 필드를 위치 인자로 늘어놓거나, 필수 값만 `.flatten`으로 건네고 나머지 선택 값은
포기합니다. `ZIGO061`의 hint는 "그 값을 함수의 별도 매개변수로 옮기라"고 안내하지만 소비자는
바인딩 대상 라이브러리의 Zig 시그니처를 바꿀 수 없습니다.

이 계획이 끝나면 한 `.options` 선언이 두 가지를 동시에 합니다: 기본값이 없는 필드는 Go
함수의 위치 인자로, 기본값이 있는 필드는 `With*` 옵션으로 나옵니다.

```zig
zigo.param.options(2, &.{ "cols", "rows", "max_scrollback_bytes", "max_scrollback_lines" }, .{})
```

가 `func NewTerminal(cols uint16, rows uint16, opts ...TerminalOption) (*Terminal, error)`를
냅니다.

## Measurable goals

- 기본값 없는 필드를 나열한 `.options` 선언이 `ZIGO061` 없이 생성된다. 단 기본값을 가진
  필드가 하나도 없으면 지금처럼 `ZIGO061`이 나고 `.flatten`을 안내한다.
- 생성된 Go에서 기본값 없는 필드는 위치 인자로, 기본값 있는 필드만 옵션 설정 구조체와
  `With*` 생성자에 나타난다. 위치 인자는 선언한 필드 순서를 지키고 `opts ...`는 마지막이다.
- C ABI는 `.flatten`과 같다. 필수 필드를 위치 인자로 올려도 심볼·매개변수 타입·순서·개수가
  바뀌지 않는다.
- 혼합 선언을 담은 generator case 골든이 시그니처·기본값 적용·range check를 고정한다.
- 기존 `functional_options`·`flattened_options` 골든과 `examples/07-event-queue`의 결과는
  바뀌지 않는다.

## Supported scope and non-goals

`.options`가 이미 다루는 flatten leaf 타입(bool, 정수, 실수, 등록된 enum, optional scalar)
안에서만 지원합니다.

non-goal:

- 나열되지 않은 필드의 기본값 규칙 완화. 나열되지 않은 필드는 지금처럼 Zig 기본값을
  가져야 하고, 그 검사는 그대로 둡니다.
- Rust target의 옵션 표면.
- `.flatten` 단독 동작, 옵션 이름 규칙(`resolveOptionsNamesAlloc`)과 접두사 계산 변경.
- 위치 인자의 순서를 필드 순서와 다르게 고르는 선언 옵션.

## Reference source / commit / license

외부 소스를 가져오지 않습니다. 저장소 안의 기존 구현을 참조합니다.

- `src/gen/validate/functions.zig:194` -- `.options` 필드의 기본값 검사
- `src/gen/emit/public.zig:251` -- `functionOptions`가 고르는 옵션 매개변수와 필드 목록
- `src/gen/emit/public.zig:407` -- 설정 구조체 초기화와 `With*` 생성자
- `src/gen/emit/public.zig:1150` -- 공개 시그니처가 옵션 매개변수를 건너뛰는 지점
- `src/gen/emit/public.zig:676` -- raw 호출 인자를 `cfg.<field>`로 쓰는 지점
- `src/gen/emit/public_writers.zig:209` -- 옵션 필드의 range check
- `src/gen/validate/names.zig:970` -- `With*` 이름 충돌 검사
- `src/gen/abi_diff.zig:630` -- Go 시그니처 비교가 옵션 매개변수를 세는 방식

## Completion criteria for the whole plan

모든 phase가 done이고 `zig build test`가 통과하며, 혼합 선언이 진단·방출·골든·문서 네 곳에서
같은 모양을 말합니다.
