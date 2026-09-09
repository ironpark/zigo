# 생성 Go API 참조

이 문서는 생성된 public Go package에서 반복되는 API pattern을 설명합니다. 정확한 이름과
signature는 binding 선언, Zig source와 package option에 따라 달라지므로 생성 diff와
`zig build go-report`가 최종 정본입니다.

## 이름

- Zig function과 type은 exported Go identifier로 변환됩니다.
- `.name`이 있으면 해당 이름을 사용합니다.
- constructor는 보통 `New<Type>`입니다.
- destructor는 handle의 `Close() error`가 됩니다.
- Zig error tag는 `Err<Tag>` sentinel이 됩니다.
- 생성 내부 identifier는 public package에서 `zigo` prefix를 예약합니다.

## function result

| Zig 결과 | Go pattern |
|---|---|
| `T` | `T` |
| `E!T` | `(T, error)` |
| `?T` | `(T, bool)` 또는 nil 가능한 타입 |
| `E!?T` | `(T, bool, error)` |
| output buffer + count result | `(n int, error)` 또는 해당 정수 형태 |

비표준 폭 integer input의 range check, invalid handle과 callback contract 때문에 원래 Zig
함수가 error union이 아니어도 Go signature에 `error`가 추가될 수 있습니다.

## error 분류

문자열 대신 standard library를 사용합니다.

```go
if errors.Is(err, mylib.ErrOutOfRange) { ... }

var native *mylib.NativePanicError
if errors.As(err, &native) { ... }
```

대표 sentinel:

- Zig error tag별 `Err<Tag>`
- `ErrOutOfRange`
- `ErrInvalidHandle`, `ErrHandleInUse`
- `ErrNativePanic`
- `ErrCallbackFailed`, `ErrNilCallback`, `ErrCallbackPanic`
- purego의 `ErrLibraryLoad`

실제로 생성되는 오류는 binding feature에 따라 달라집니다.

## handle

owned native object는 pointer receiver Go type으로 생성됩니다.

```go
resource, err := mylib.NewResource(...)
if err != nil { return err }
defer resource.Close()
```

`Close`와 모든 method의 오류를 처리하세요. finalizer cleanup은 명시적 `Close`를 대신하지
않습니다. borrowed object는 `Ref` type처럼 별도 표현을 사용할 수 있고 부모보다 오래 사용할
수 없습니다.

## callback

등록 callback은 named Go function type이 됩니다. `.go_error` call site에서는 마지막에
`error`가 추가됩니다. retained callback은 소유 handle을 닫을 때까지 native에서 호출될 수
있습니다.

Go callback panic은 native frame을 빠져나온 뒤 `*CallbackPanicError`로 다시 panic합니다.
정상 application error는 panic하지 말고 callback `error`를 사용하세요.

## enum과 union

enum은 named integer type과 constant를 생성합니다. text feature가 있으면 `String`, parse와
encoding method가 추가됩니다.

tagged union handle은 `Tag()`, variant별 `As*()`와 `Variant()`를 제공합니다. snapshot access가
설정되면 `Snapshot()`과 독립 Go snapshot type도 생성됩니다.

## stream과 context

Zig `std.Io` parameter는 Go `io.Reader` 또는 `io.Writer`, cancel flag는
`context.Context`로 나타납니다. cancellation은 cooperative하므로 context가 끝나도 native
함수가 flag를 확인할 때까지 호출이 반환되지 않을 수 있습니다.

## purego loader

explicit 또는 automatic policy는 다음 API를 생성할 수 있습니다.

```text
DefaultLibraryName
LoadLibrary(path string) error
LibraryLoaded() bool
```

`.automatic_internal`은 이 API를 public package에서 숨깁니다. 로드한 library는 process
종료까지 유지됩니다.

## 사용자 확장 파일

같은 package에 `_gen.go`가 아닌 파일을 추가해 helper나 method를 작성할 수 있습니다. public
생성 이름과 `zigo`로 시작하는 private identifier를 다시 정의하지 마세요. raw package는 내부
구현이며 호환성 보장 대상이 아닙니다.
