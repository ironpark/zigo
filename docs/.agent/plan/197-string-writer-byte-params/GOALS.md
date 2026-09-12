# GOALS

## Problem and the end result from the user's point of view

`.implements = .string_writer`는 매개변수가 Go `string`에 도달할 때만 허용됩니다
(`ZIGO058`). 그래서 UTF-8이 보장되지 않는 바이트를 받는 메서드 -- pty에서 온 VT 바이트처럼
`.semantic = .opaque_bytes`가 옳은 매개변수 -- 는 `.writer`만 가질 수 있습니다.

그런데 `.writer`만 있으면 `io.WriteString(w, s)`는 `[]byte(s)` 복사본을 만듭니다.
`.string_writer`가 존재하는 이유가 그 복사를 없애는 것인데, 복사가 실제로 일어나는 쪽이
거절당합니다. 소비자는 대신 손으로 씁니다.

```go
func (s *Stream) WriteString(str string) (int, error) {
	p := unsafe.Slice(unsafe.StringData(str), len(str))
	if err := s.Feed(p); err != nil { return 0, err }
	return len(str), nil
}
```

이 계획이 끝나면 `.opaque_bytes` 바이트 매개변수에도 `.string_writer`를 붙일 수 있고,
생성기가 위의 두 줄을 대신 냅니다. 네이티브는 `[]const u8`을 호출 동안만 읽으므로 문자열의
불변 메모리를 빌려주는 것이 안전하고, 이는 `.writer`가 `p []byte`에 대해 이미 맺은 계약과
같습니다.

## Measurable goals

- string semantic이 없는 `[]const u8` 매개변수에 `.string_writer`를 붙인 선언이 `ZIGO058`
  없이 생성된다.
- 그 선언의 `WriteString` 래퍼가 `unsafe.Slice(unsafe.StringData(...), len(...))`로 바이트를
  빌려 메서드를 부르고, `[]byte(...)` 변환을 만들지 않는다.
- string semantic을 가진 매개변수의 기존 `.string_writer` 출력은 한 바이트도 바뀌지 않는다.
- `.writer`에 string semantic을 붙였을 때의 `ZIGO058`은 그대로 남는다.
- `examples/11-io-streams`가 바이트 매개변수 `.string_writer`를 하나 보여주고, cgo와 purego
  양쪽 `go test`가 통과한다.

## Supported scope and non-goals

`.implements = .string_writer`의 입력 조건만 넓힙니다.

non-goal:

- `.reader`의 거울 격인 "string reader". Go 표준에 대응 인터페이스가 없습니다.
- `.writer`에 string semantic을 허용하는 것. `Write(p []byte)`는 바이트를 넘기므로 string
  힌트는 여전히 복사를 부르고, 그 진단은 남습니다.
- 매개변수를 네이티브가 호출 뒤에도 붙잡는 경우의 지원. 빌린 바이트는 호출 동안만
  유효하고, 그 계약은 `.writer`와 같습니다.
- 슬라이스 materialization이나 소유 규칙 변경.

## Reference source / commit / license

외부 소스를 가져오지 않습니다. 저장소 안의 기존 구현을 참조합니다.

- `src/gen/plugins/implements.zig:74` -- `.string_writer` 래퍼 방출
- `src/gen/plugins/implements.zig:216` -- 기대 shape와 `ZIGO058` 조건
- `src/gen/emit/public.zig:1002` -- 본문이 쓰는 qualifier로 import를 정하는 목록
- `docs/authoring/streams-and-cancellation.md:105` -- 두 kind의 구분 설명
- `examples/11-io-streams/src/bindings.zig:25` -- 현재 string semantic 선언

## Completion criteria for the whole plan

모든 phase가 done이고 `zig build test`가 통과하며, 11 예제의 cgo·purego 테스트가 통과하고,
문서가 새 조건을 말합니다.
