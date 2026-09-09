# 콜백과 오류

이 가이드는 Go 함수를 Zig에 전달하고 콜백의 수명, 오류와 panic 경계를 선언하는 방법을
설명합니다.

선언 조각은 별도 표시가 없으면 `src/bindings.zig`의 `zigo.define` 안에 있는
`.declarations` 목록에 넣습니다. `api`와 공통 import는 [최소 선언](README.md)을 사용합니다.
Go 호출 조각은 함수 본문용이며, 전체 import와 실행 방법은 연결된 예제를 참고하세요.

## 호출 동안 사용하는 콜백

[04-콜백의 Zig 구현](../../examples/04-callback/src/root.zig)은 함수 포인터와
그 호출에 필요한 `userdata`를 받습니다.

```zig
pub const Observer = *const fn (value: i32, userdata: usize) callconv(.c) i32;

pub fn apply(value: i32, callback: Observer, userdata: usize) i32 {
    return callback(value, userdata);
}
```

다음 두 선언을 함께 등록합니다.

```zig
api.callback("Observer", .{ .on_failure = .{ .result = 0 } }),
api.func("apply", .{ .params = &.{
    zigo.param.callback(1, .{ .retention = .borrowed, .go_error = true }),
} }),
```

Go에서는 `userdata`를 직접 만들지 않습니다. 생성 API는 다음과 같습니다.

```go
type Observer func(value int32) (int32, error)
func Apply(value int32, callback Observer) (int32, error)
```

[Go 호출 예제](../../examples/04-callback/go/example_test.go)는 콜백의 원래 오류가
호출자에게 전달되는지 확인합니다.

```go
rejected := errors.New("application rejected the value")
_, err := callback.Apply(7, func(value int32) (int32, error) {
    return 0, rejected
})
fmt.Println(errors.Is(err, rejected)) // true
```

`.borrowed`이므로 Zig는 `apply`가 반환한 뒤 콜백이나 `userdata`를 보관하지 않습니다.
실패하면 Zig에는 `0`이 반환되며, 네이티브 실행이 끝난 뒤 Go 호출자가 오류를 받습니다.

## 콜백 타입 등록

Zig의 함수 포인터 alias를 콜백으로 등록합니다.

```zig
api.callback("Observer", .{
    .on_failure = .{ .result = 0 },
})
```

콜백 매개변수와 반환값에 별도 의미가 있으면 원래 콜백 시그니처 index로
지정합니다.

```zig
api.callback("Logger", .{
    .params = &.{
        .{ .index = 1, .semantic = .utf8_string },
    },
})
```

userdata가 첫째나 마지막이 아닌 위치에 있으면 `.userdata = .{ .index = n }`으로
지정합니다. 일반적인 trailing `usize` userdata는 시그니처에서 추론할 수 있습니다.

## 호출 지점의 계약

같은 콜백 타입도 함수마다 보관 방식이 다를 수 있습니다.

```zig
api.func("apply", .{ .params = &.{
    zigo.param.callback(1, .{
        .retention = .borrowed,
        .go_error = true,
    }),
} })
```

| 옵션 | 의미 |
|---|---|
| `.retention = .borrowed` | 네이티브 호출이 끝나기 전에 콜백 사용도 끝남 |
| `.retention = .retained` | 네이티브 객체가 이후 호출에서도 콜백을 보관 |
| `.reentrancy` | 콜백에서 같은 바인딩으로 재진입 가능한지 선언 |
| `.thread` | 호출자 스레드만 또는 임의 네이티브 스레드에서 호출 가능한지 선언 |
| `.go_error = true` | Go 콜백이 `error`를 반환 |
| `.userdata` | 콜백 token 매개변수의 원래 Zig index |

retained 콜백은 이를 보관하는 핸들의 수명과 함께 registry에서 유지됩니다. 콜백을
바꾸거나 핸들을 닫을 때 네이티브 코드가 이전 콜백을 더 이상 호출하지 않는 계약이
필요합니다.

## Go 콜백이 오류를 반환하기

`.go_error = true`이면 생성 콜백은 마지막 결과로 Go `error`를 받습니다.

```text
func(value int32) (int32, error)
```

오류가 발생하면 zigo는 콜백 호출을 실패로 기록하고 Zig 콜백에는
`on_failure.result` 값을 돌려줍니다. 해당 호출이 끝난 뒤 공개 래퍼는 `CallbackError`를
반환합니다.

```go
if err != nil {
    if errors.Is(err, mylib.ErrCallbackFailed) {
        // callback이 반환한 원래 오류도 errors.Is/errors.As로 도달합니다.
    }
}
```

retained 콜백이 다른 네이티브 스레드에서 실패해 즉시 돌려줄 공개 호출이 없다면 오류는
같은 바인딩의 다음 안전한 호출에서 관찰될 수 있습니다.

## nil 콜백

nil을 허용하는 Zig 포인터 타입이라도 공개 Go API에서 nil 의미가 분명해야 합니다. 생성
래퍼는 잘못된 nil 콜백을 `ErrNilCallback`으로 분류합니다. 오류 반환이 없는 Go
시그니처에서는 호출 전에 panic할 수 있으므로 optional 콜백은 명시적인 설정 API로
모델링하는 편이 안전합니다.

## panic 경계

panic은 언어 경계를 직접 unwind하지 않습니다.

- Go 콜백 panic은 trampoline이 recover하고 네이티브 호출이 돌아온 뒤
  `*CallbackPanicError`로 다시 panic합니다.
- Zig panic은 네이티브 호출 경계에서 포착 가능한 경로라면 `*NativePanicError`로 반환됩니다.
- panic 도중 변경된 핸들은 안전을 위해 poison 상태가 될 수 있습니다.

Go에서는 sentinel과 상세 타입을 모두 사용할 수 있습니다.

```go
var panicErr *mylib.NativePanicError
if errors.As(err, &panicErr) {
    log.Print(panicErr.Message)
}
```

콜백이 호출자와 다른 스레드에서 실행되거나 reentrant하면 shared Go 상태와 네이티브 상태의
동기화는 애플리케이션 책임입니다.

## Zig 오류 유니온

Zig 오류 유니온 함수는 별도 annotation 없이 Go `error`를 반환합니다.

```text
func Divide(a int32, b int32) (int32, error)
```

각 Zig error 태그는 생성된 `Err<Tag>` sentinel에 대응합니다.

```go
value, err := calculator.Divide(10, 0)
if errors.Is(err, calculator.ErrDivideByZero) {
    // expected failure
}
```

범위 검사, invalid 핸들, 콜백 failure와 네이티브 panic도 각각 생성된 sentinel과 구조화된
오류 타입으로 분류됩니다. 문자열 비교 대신 `errors.Is`와 `errors.As`를 사용하세요.

실행 예제는 [02-errors](../../examples/02-errors/README.md)와
[04-콜백](../../examples/04-callback/README.md)를 참고하세요.
