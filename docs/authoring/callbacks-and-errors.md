# 콜백과 오류

이 가이드는 Go 함수를 Zig에 전달하고 callback의 수명, 오류와 panic 경계를 선언하는 방법을
설명합니다.

## callback 타입 등록

Zig의 function pointer alias를 callback으로 등록합니다.

```zig
api.callback("Observer", .{
    .on_failure = .{ .result = 0 },
})
```

callback parameter와 반환값에 별도 의미가 있으면 원래 callback signature index로
지정합니다.

```zig
api.callback("Logger", .{
    .params = &.{
        .{ .index = 1, .semantic = .utf8_string },
    },
})
```

userdata가 첫째나 마지막이 아닌 위치에 있으면 `.userdata = .{ .index = n }`으로
지정합니다. 일반적인 trailing `usize` userdata는 signature에서 추론할 수 있습니다.

## 호출 지점의 계약

같은 callback 타입도 함수마다 보관 방식이 다를 수 있습니다.

```zig
api.func("apply", .{ .params = &.{
    zigo.param.callback(1, .{
        .retention = .borrowed,
        .go_error = true,
    }),
} })
```

| option | 의미 |
|---|---|
| `.retention = .borrowed` | native 호출이 끝나기 전에 callback 사용도 끝남 |
| `.retention = .retained` | native 객체가 이후 호출에서도 callback을 보관 |
| `.reentrancy` | callback에서 같은 binding으로 재진입 가능한지 선언 |
| `.thread` | 호출자 thread만 또는 임의 native thread에서 호출 가능한지 선언 |
| `.go_error = true` | Go callback이 `error`를 반환 |
| `.userdata` | callback token parameter의 원래 Zig index |

retained callback은 이를 보관하는 handle의 수명과 함께 registry에서 유지됩니다. callback을
바꾸거나 handle을 닫을 때 native 코드가 이전 callback을 더 이상 호출하지 않는 계약이
필요합니다.

## Go callback이 오류를 반환하기

`.go_error = true`이면 생성 callback은 마지막 결과로 Go `error`를 받습니다.

```text
func(value int32) (int32, error)
```

오류가 발생하면 zigo는 callback 호출을 실패로 기록하고 Zig callback에는
`on_failure.result` 값을 돌려줍니다. 해당 호출이 끝난 뒤 public wrapper는 `CallbackError`를
반환합니다.

```go
if err != nil {
    if errors.Is(err, mylib.ErrCallbackFailed) {
        // callback이 반환한 원래 오류도 errors.Is/errors.As로 도달합니다.
    }
}
```

retained callback이 다른 native thread에서 실패해 즉시 돌려줄 public 호출이 없다면 오류는
같은 binding의 다음 안전한 호출에서 관찰될 수 있습니다.

## nil callback

nil을 허용하는 Zig pointer 타입이라도 공개 Go API에서 nil 의미가 분명해야 합니다. 생성
wrapper는 잘못된 nil callback을 `ErrNilCallback`으로 분류합니다. 오류 반환이 없는 Go
signature에서는 호출 전에 panic할 수 있으므로 optional callback은 명시적인 설정 API로
모델링하는 편이 안전합니다.

## panic 경계

panic은 언어 경계를 직접 unwind하지 않습니다.

- Go callback panic은 trampoline이 recover하고 native 호출이 돌아온 뒤
  `*CallbackPanicError`로 다시 panic합니다.
- Zig panic은 native boundary에서 포착 가능한 경로라면 `*NativePanicError`로 반환됩니다.
- panic 도중 변경된 handle은 안전을 위해 poison 상태가 될 수 있습니다.

Go에서는 sentinel과 상세 타입을 모두 사용할 수 있습니다.

```go
var panicErr *mylib.NativePanicError
if errors.As(err, &panicErr) {
    log.Print(panicErr.Message)
}
```

callback이 호출자와 다른 thread에서 실행되거나 reentrant하면 shared Go state와 native state의
동기화는 애플리케이션 책임입니다.

## Zig error union

Zig error union 함수는 별도 annotation 없이 Go `error`를 반환합니다.

```text
func Divide(a int32, b int32) (int32, error)
```

각 Zig error tag는 생성된 `Err<Tag>` sentinel에 대응합니다.

```go
value, err := calculator.Divide(10, 0)
if errors.Is(err, calculator.ErrDivideByZero) {
    // expected failure
}
```

범위 검사, invalid handle, callback failure와 native panic도 각각 생성된 sentinel과 구조화된
오류 타입으로 분류됩니다. 문자열 비교 대신 `errors.Is`와 `errors.As`를 사용하세요.

실행 예제는 [02-errors](../../examples/02-errors/README.md)와
[04-callback](../../examples/04-callback/README.md)를 참고하세요.
