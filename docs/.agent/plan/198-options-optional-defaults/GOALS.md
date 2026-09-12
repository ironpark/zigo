# GOALS

## Problem and the end result from the user's point of view

`.options`의 필드가 `?usize = 10000`처럼 **optional이면서 null이 아닌 Zig 기본값**을 가지면
생성된 Go가 컴파일되지 않습니다. 설정 구조체의 필드는 포인터(`*uint`)인데 초기화는 값
리터럴을 그대로 씁니다.

```go
type terminalOptions struct {
	maxLines *uint
}

cfg := terminalOptions{
	maxLines: 10000, // cannot use 10000 (untyped int constant) as *uint value
}
```

0.24.0이 `.options`에서 기본값 없는 필드를 열어 주면서 소비자가 실제 옵션 구조체 전체를
나열하기 시작했고, 그때 이 조합이 처음 드러났습니다. ghostty의 `Terminal.Options`에서
가장 쓸모 있는 두 필드(`max_scrollback_bytes`, `default_cursor_blink`)가 바로 이 모양이라
소비자는 `.options` 적용 자체를 되돌렸습니다.

이 계획이 끝나면 optional 필드의 기본값이 null이든 아니든 생성된 Go가 컴파일되고, 옵션을
주지 않은 호출이 그 기본값을 그대로 네이티브로 보냅니다.

## Measurable goals

- optional 필드에 null이 아닌 기본값(정수, 실수, bool, 등록된 enum)이 있는 `.options`
  선언의 생성 Go가 `go build`와 golden 비교를 통과한다.
- 옵션을 주지 않은 호출이 그 기본값을 네이티브로 보내고, `With*`로 `nil`을 주면 값이
  전달되지 않는다.
- `= null` 기본값과 기본값 없는 필드, 그리고 non-optional 필드의 출력은 바뀌지 않는다.
- 같은 조합을 담은 generator case 골든이 이 모양을 고정한다.

## Supported scope and non-goals

`.options`의 flatten leaf 타입 안에서만 다룹니다.

non-goal:

- `.flatten` 단독 경로. 그쪽은 기본값을 읽지 않으므로 이 문제가 없습니다.
- optional 필드의 ABI·shim 표현 변경.
- 옵션 이름 규칙, 접두사 계산, 위치 인자 분류 규칙 변경.

## Reference source / commit / license

외부 소스를 가져오지 않습니다.

- `src/gen/emit/public.zig:366` -- `formatGoDefaultAlloc`가 만드는 기본값 표현
- `src/gen/emit/public.zig:405` -- `With*`가 쓰는 공개 Go 타입
- `src/gen/emit/public.zig:428` -- `cfg` 초기화
- `tests/generator_cases/options_required_fields` -- 0.24.0이 더한 혼합 선언 골든

## Completion criteria for the whole plan

모든 phase가 done이고 `zig build test`가 통과하며, 골든이 세 가지 기본값 모양(없음, `null`,
값)을 한 케이스 안에서 함께 보여 줍니다.
