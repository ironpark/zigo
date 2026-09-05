# 콜백과 Go 오류 처리

Go 함수를 Zig에 넘길 때의 수명, 오류 반환과 panic 전달을 설명합니다. 선언의 기본 형태는 [`bindings.zig` 선언](bindings.md)을 참고하세요.

콜백은 [이름과 수명](#콜백-타입-이름)을 먼저 정하고, 실패를 반환하려면
[`go_error`](#콜백이-돌려주는-go-error)를 지정하세요.
호출 결과는 [오류 분류](#생성된-go-error-판별)로 확인합니다.

## 콜백 타입 이름

콜백 파라미터마다 Go 함수 타입이 하나씩 생깁니다. 이름은 기본적으로 소유 타입이나 함수와
파라미터 이름에서 파생되므로(`ContextCallback`, `ApplyCallback`), 같은 Zig 시그니처를 여러
함수가 받으면 Go 타입도 여러 개가 됩니다. Zig의 `pub const Observer = *const fn (...)`은
alias라 reflection이 이름을 알 수 없으니, 하나의 이름을 원하면 `types`에 등록합니다.

```zig
.types = .{
    .{ .name = "Observer", .type = mylib.Observer, .repr = .callback },
},
```

같은 시그니처의 모든 콜백 파라미터가 `Observer` 하나로 생성됩니다. 시그니처가 같은 alias
둘을 등록하면 먼저 등록한 이름이 둘 다에 쓰입니다 — Zig에게는 같은 타입입니다.

콜백 반환은 scalar뿐 아니라 `void`도 지원합니다. `*const fn (..., userdata: usize)
callconv(.c) void`는 Go에서 반환값 없는 `func(...)`가 되고, cgo와 purego 모두 native 호출이
돌아온 뒤 같은 panic 전달과 수명 규칙을 적용합니다.

콜백이 호출 중 바인딩을 다시 부를 수 있는지와 어떤 thread에서 불리는지는 파라미터별
계약으로 기록할 수 있습니다. 둘 다 생략이 기본이며, 생성기의 동작은 바뀌지 않고 생성된
콜백 타입과 그 콜백을 받는 함수의 Go doc에만 나타납니다.

```zig
.param_meta = .{
    .observer = .{
        .retention = .retained,
        .reentrancy = .forbidden,
        .thread = .any,
    },
},
```

`reentrancy`는 `.allowed` 또는 `.forbidden`, `thread`는 호출을 시작한 thread만 허용하는
`.caller` 또는 임의의 native thread를 허용하는 `.any`입니다. 이 값은 native 라이브러리가
지켜야 할 문서 계약입니다. zigo는 `runtime.LockOSThread`를 추가하거나 thread를 고정하지
않으며, 콜백이 아닌 파라미터에 두 값을 쓰면 기존 callback metadata 오용 진단인
`ZIGO025`로 거부합니다.

## 콜백이 돌려주는 Go error

기본적으로 Go 콜백은 Zig 시그니처가 말하는 값만 돌려줍니다. `param_meta.<이름>.go_error`를
켜면 Go 타입이 `error`를 하나 더 돌려주고, 그 error가 공개 함수의 반환값으로 나옵니다.

```zig
.{
    .path = "CallbackContext.create",
    .params = .{ "callback", "userdata" },
    .param_meta = .{ .callback = .{ .retention = .retained, .go_error = true } },
}
```

생성되는 API:

```text
type Observer func(int32) (int32, error)

func Apply(value int32, callback Observer) (int32, error)
```

Zig 콜백의 반환 타입은 `i32`여야 합니다(`ZIGO025`). error를 알리는 데 결과 자리를 쓰기
때문입니다: 콜백이 `err != nil`을 돌려주면 trampoline은 그 error를 저장하고 native 쪽에
**`-5`**를 돌려줍니다. `-3`(panic), `-4`(삭제된 토큰)와 구별되는 값이므로 Zig 함수는 셋을
가려낼 수 있습니다. Zig 쪽은 `-5`를 자기 규약대로 처리하면 되고(대개 error 반환), 그것이
무엇이었든 공개 Go 함수는 저장된 error를 우선해 `*CallbackError`로 돌려줍니다.

```go
var errRefused = errors.New("refused")
_, err := Apply(7, func(int32) (int32, error) { return 0, errRefused })
errors.Is(err, errRefused)       // true — Unwrap이 원래 error를 내준다
errors.Is(err, ErrCallbackFailed) // true — 분류용 sentinel

var callbackErr *CallbackError
errors.As(err, &callbackErr)     // Operation, Callback, Err
```

retained 콜백도 오류를 해당 handle에 저장합니다. 호출 중 동기적으로 발생한 오류는 그 호출의
오류 확인 단계에서 전달될 수 있고, 호출 사이에 발생한 오류는 그 handle의 다음 호출에서
전달될 수 있습니다. panic도 같은 방식으로 확인합니다. 전달한 오류 상태는 지웁니다.

C ABI는 바뀌지 않습니다 — `go_error`는 Go 표면만 넓힙니다. 다만 Go 콜백 타입이 바뀌므로
`abi-diff`는 이것을 breaking으로 봅니다.

> **`go_error`는 파라미터가 아니라 시그니처의 성질입니다.** 한 바인딩 안에서 같은 ABI
> 시그니처는 Go 타입 하나(그리고 purego에서는 dispatcher 하나)를 공유하므로, 한 곳에
> `.go_error = true`를 켜면 그 시그니처를 쓰는 모든 콜백 파라미터가 `error`를 돌려주는
> 타입이 됩니다.

## 콜백 실패 반환값 (`on_callback_failure`)

기본 dispatcher는 `i32` 콜백의 panic에 `-3`, 삭제된 userdata token에 `-4`, Go error에
`-5`를 반환합니다. 이 값들이 native 도메인의 정상 값과 겹치거나, 도메인이 별도의 정지 값을
요구하면 callback 타입 항목에 실패 반환값을 선언할 수 있습니다.

```zig
.types = .{
    .{
        .name = "Observer",
        .type = mylib.Observer,
        .repr = .callback,
        .on_callback_failure = .{ .result = 0 },
    },
},
```

한 함수의 callback에만 적용하려면 파라미터 메타데이터에 같은 값을 둡니다.

```zig
.param_meta = .{
    .callback = .{ .on_callback_failure = .{ .result = 0 } },
},
```

이 설정은 **native에 돌려주는 값만** 바꿉니다. dispatcher는 panic이나 Go error를 여전히
callback state에 기록하고, 생성된 공개 함수는 native 호출이 끝난 뒤 `*CallbackPanicError`로
다시 panic하거나 `*CallbackError`를 반환합니다. `.cancel`도 함께 있으면 실패 반환 전에 취소
플래그를 먼저 세웁니다. cgo와 purego가 같은 값을 사용합니다.

`.result`는 callback 반환 타입에 들어가야 하고 void callback에는 쓸 수 없습니다
(`ZIGO046`). 이 메타데이터는 callback ABI나 공개 Go 함수 타입을 바꾸지 않으므로 `abi-diff`는
추가·변경·제거를 compatible로 분류합니다. 설정하지 않은 callback의 `-3`/`-4`/`-5`와 생성
출력은 그대로입니다.

## 생성된 Go error 판별

분류에는 내보낸 sentinel과 `errors.Is`를 사용하고, 세부 정보가 필요할 때만 `errors.As`를
사용합니다. 생성 오류의 sentinel로 종류를 구분하고, 콜백·스트림·로더 오류의 원인은
`errors.Is`·`errors.As`로 함께 확인할 수 있습니다.

| `errors.Is` 대상 | 뜻 | 세부 타입 |
|---|---|---|
| `ErrInvalidHandle` | nil·closed·부모가 닫힌 handle | `*HandleError` |
| `ErrNativePanic` | Zig panic | `*NativePanicError` |
| `ErrNativeStatus` | 알려지지 않은 native status | `*StatusError` |
| `ErrLibraryLoad` | purego library·symbol load 실패 | `*LibraryError` |
| `ErrCallbackPanic` | Go 콜백 panic; 오류 반환이 아니라 다시 panic | `*CallbackPanicError` |
| `ErrCallbackFailed` | `.go_error` 콜백이 돌려준 error | `*CallbackError` |
| `Err<ZigError>` | Zig error set의 오류 | `*Error` |

`Operation`은 오류가 발생한 호출 이름입니다. 아래는 `err`를 받은 뒤 분류하는 코드이며,
생성된 타입·오류 이름은 실제로 import한 패키지 이름을 붙여 사용하세요.

```go
switch {
case errors.Is(err, ErrInvalidHandle):
    // 객체가 유효한지, 이미 닫혔는지 확인합니다.
case errors.Is(err, ErrNativePanic):
    // 작업을 중단하고 관련 handle을 재사용하지 않습니다.
case errors.Is(err, ErrOutOfMemory):
    // 라이브러리의 메모리 부족 오류를 처리합니다.
}

var panicErr *NativePanicError
if errors.As(err, &panicErr) {
    log.Print(panicErr.Operation, panicErr.Message)
}

var zigErr *Error
if errors.As(err, &zigErr) {
    log.Print(zigErr.Operation, zigErr.Name) // 예: "Pipeline.Process", "Disabled"
}
```

`Err*` sentinel은 `==`가 아니라 `errors.Is`로 비교합니다. 반환되는 값은 호출 이름을 담은
새 `*Error`이고, `Is`는 stable code로 판별합니다.

panic하는 `Must*` method에서 복구한 값도 `error`이면 같은 규칙으로 판별할 수 있습니다.

### Go 콜백의 panic

Go 콜백이 native 호출 안에서 panic하면 trampoline이 그것을 복구합니다 — panic은 native
frame을 풀 수 없기 때문입니다. native 쪽은 부호 있는 32비트 결과에서 기본값 `-3` 또는
`on_callback_failure.result`를 받아 스스로 정리하고 반환할 수 있고, 그 호출이 돌아온 직후 생성된 함수가 **같은 goroutine에서 panic을
다시 일으킵니다**. 다시 일어난 값은 `*CallbackPanicError`이며 원래 panic 값(`Value`)과 복구
시점의 stack(`Stack`)을 담습니다. `Unwrap`은 `Value`가 `error`일 때 그것을 돌려주므로
`errors.Is`·`errors.As`가 원인까지 닿습니다.

```go
defer func() {
    if recovered := recover(); recovered != nil {
        var panicErr *CallbackPanicError
        if err, ok := recovered.(error); ok && errors.As(err, &panicErr) {
            log.Print(panicErr.Operation, panicErr.Value, string(panicErr.Stack))
            return
        }
        panic(recovered)
    }
}()
```

이 규칙은 콜백을 인자로 받은 호출과, 콜백을 retained로 보유한 handle의 모든 method에
적용됩니다. native 코드가 실패 반환값을 자기 error로 바꿔 반환하더라도 Go 호출자는 그 error가
아니라 panic을 봅니다 — 콜백의 panic은 호출자 자신의 Go 코드가 실패한 것이고, 생성된 호출은
그것이 복구 가능한지 판단할 수 없기 때문입니다.

```go
defer func() {
    if err, ok := recover().(error); ok && errors.Is(err, ErrInvalidHandle) {
        // handle use-after-close
    }
}()
```

전체 타입 적격 조건과 runtime 주의사항은 [지원 범위와 제한사항](limitations.md)이 정본입니다.

## `Must*` 동반 API

`addGoBindings`에 `.go_must_variants = true`를 지정하면 생성된 Go 시그니처가 `error`를
반환하는 모든 공개 함수와 메서드에 `Must<Name>`이 함께 생깁니다. 생성자는 최종 공개 이름
`New<Type>`을 기준으로 `MustNew<Type>`이 되고, `Close`에는 동반 API를 만들지 않습니다.
단일 값은 값만, optional 같은 다중 값은 오류를 뺀 값들을 반환하며, 오류 전용 함수는 반환값이
없습니다. 실패 시 checked API가 만든 동일한 `*HandleError`, `*NativePanicError`, 생성
오류 등을 panic 값으로 사용합니다. 생성 이름이 기존 공개 이름과 겹치면 `ZIGO024`입니다.

옵션 기본값은 `false`이므로 켜지 않은 binding의 생성 파일은 바뀌지 않습니다.
