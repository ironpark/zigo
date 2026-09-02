# GOALS

## Problem and the end result from the user's point of view

계획 70이 `*std.Io.Writer`/`Reader` 파라미터를 Go `io.Writer`/`io.Reader`로 연동하며 "Go 쪽 error를 저장했다가 공개 함수에서 반환"하는 규칙을 만든다. 그 위에 네 가지를 얹는다.
1. 일반 callback은 i32만 돌려주고 Go error는 사라진다(`src/gen/validate.zig:16-47`, purego는 void/i32만). 70의 저장·재반환 규칙을 모든 callback으로 확장해 Go callback 타입이 `error`를 돌려줄 수 있게 한다.
2. 70의 Reader는 항상 콜백을 거친다. Go 값이 `*bytes.Reader`/`*bytes.Buffer`처럼 바이트를 통째로 낼 수 있으면 슬라이스 하나로 넘겨 shim이 `Reader.fixed`로 감싸면 경계 횟수가 0이다.
3. Zig 객체가 스트림을 내주는 방향(`fn writer(self) *std.Io.Writer`, `fn reader(self) *std.Io.Reader`)은 70의 비목표다. handle 메서드로 `Write`/`Read`를 생성해 Go `io.Writer`/`io.Reader`를 만족시키면 어댑터 수명 문제 없이 지원할 수 있다.
4. 긴 native 호출을 Go `context.Context`로 끊을 수단이 없다. Ultrasync가 `CancelToken`을 직접 만들었다. Zig 쪽 원자 플래그 폴링 규약과 Go 쪽 `ctx.Done()` 감시를 생성하는 `.cancel` 메타가 있으면 일반화된다.

작업 후: Go callback이 `error`를 반환하면 그 error가 호출자에게 돌아온다. 메모리 데이터를 파싱하는 가장 흔한 사용에서 콜백이 0회다. Zig가 내주는 스트림이 Go 인터페이스로 나온다. `.cancel = .{ .flag = "…" }`가 붙은 함수는 Go에서 `ctx context.Context`를 첫 인자로 받고 취소 시 `context.Canceled`를 돌려준다.

## Measurable goals

- Go callback 타입 `func(...) (int32, error)` fixture에서 callback이 돌려준 error가 `errors.Is`로 공개 함수에서 식별된다(cgo·purego).
- `*bytes.Reader`를 넘긴 Reader 파라미터 호출에서 콜백 호출 수가 0이라는 테스트.
- `fn writer(self) *std.Io.Writer` fixture가 `func (t *T) Write(p []byte) (int, error)`를 생성하고 `io.Copy(t, src)`가 동작한다.
- `.cancel` 함수가 `ctx`를 받고, 취소된 ctx로 호출하면 native가 폴링 지점에서 중단해 `context.Canceled`가 돌아온다.

## Supported scope and non-goals

지원: cgo·purego 양 백엔드, callback error, `[]byte` 무콜백 경로, Zig가 내주는 스트림의 `Write`/`Read`/`Flush`, 폴링 기반 취소.
비목표: 선점형 취소(native 스레드 강제 중단), `io.ReaderAt`/`Seeker`, `sendFile`, 취소 플래그가 없는 Zig 함수의 취소(규약을 만족하는 함수만).

## Reference source / commit / license

- 계획 70(스트림 어댑터, `CallbackState` 확장), 계획 69(`.io`/`.allocator` 주입). Ultrasync `CancelToken`은 사용자 보고. 저장소 내부 작업.

## Completion criteria for the whole plan

- 측정 목표 테스트 통과. `zig build test --summary all`, `zig fmt --check`, 예제 전부(11-io-streams 포함) cgo·purego 통과.
- `docs/bindings.md`(callback error, 스트림 반환, `.cancel`), `docs/limitations.md`, `docs/generated-code.md`, `docs/purego.md`, `CHANGELOG.md` Unreleased 갱신.
