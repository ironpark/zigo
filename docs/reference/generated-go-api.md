# 생성 Go API 참조

이 문서는 생성된 공개 Go 패키지에서 반복되는 API 패턴을 설명합니다. 정확한 이름과
시그니처는 바인딩 선언, Zig 소스와 패키지 옵션에 따라 달라지므로 생성 diff와
`zig build go-report`가 최종 정본입니다.

## 이름

- Zig 함수와 타입은 exported Go identifier로 변환됩니다.
- `.name`이 있으면 해당 이름을 사용합니다.
- 생성자는 보통 `New<Type>`입니다.
- 소멸자는 핸들의 `Close() error`가 됩니다.
- Zig error 태그는 `Err<Tag>` sentinel이 됩니다.
- 생성 내부 identifier는 공개 패키지에서 `zigo` 접두사를 예약합니다.

## 함수 반환값

| Zig 결과 | Go 패턴 |
|---|---|
| `T` | `T` |
| `E!T` | `(T, error)` |
| `?T` | `(T, bool)` 또는 nil 가능한 타입 |
| `E!?T` | `(T, bool, error)` |
| 출력 버퍼 + count 결과 | `(n int, error)` 또는 해당 정수 형태 |

비표준 폭 정수 입력의 range check, invalid 핸들과 콜백 계약 때문에 원래 Zig
함수가 오류 유니온이 아니어도 Go 시그니처에 `error`가 추가될 수 있습니다.

## 오류 분류

문자열 대신 표준 라이브러리를 사용합니다.

```go
if errors.Is(err, mylib.ErrOutOfRange) { ... }

var native *mylib.NativePanicError
if errors.As(err, &native) { ... }
```

대표 sentinel:

- Zig error 태그별 `Err<Tag>`
- `ErrOutOfRange`
- `ErrInvalidHandle`, `ErrHandleInUse`
- `ErrNativePanic`
- `ErrCallbackFailed`, `ErrNilCallback`, `ErrCallbackPanic`
- purego의 `ErrLibraryLoad`

실제로 생성되는 오류는 바인딩 feature에 따라 달라집니다.

## 핸들

owned 네이티브 객체는 포인터 receiver Go 타입으로 생성됩니다.

```go
resource, err := mylib.NewResource(...)
if err != nil { return err }
defer resource.Close()
```

`Close`와 모든 메서드의 오류를 처리하세요. 자동 정리는 명시적 `Close`를 대신하지
않습니다. borrowed 객체는 `Ref` 타입처럼 별도 표현을 사용할 수 있고 부모보다 오래 사용할
수 없습니다.

## functional options

구조체 매개변수를 `zigo.param.options`로 선언하면 생성자 인자가 Go의 functional options
패턴으로 바뀝니다. 옵션 타입, 비공개 설정 구조체, 필드별 `With*` 생성자와 가변 인자
생성자가 함께 생성됩니다.

```go
type Option func(*options)

type options struct{ ... }

func WithRows(rows uint16) Option
func NewTerminal(initialCols uint16, opts ...Option) (*Terminal, error)
func MustNewTerminal(initialCols uint16, opts ...Option) *Terminal
```

옵션으로 바뀌지 않은 매개변수는 위치 인자로 남고 가변 인자는 마지막에 옵니다. 기본값이 없는
값은 옵션 구조체가 아니라 Zig 함수의 별도 매개변수로 두세요. 옵션 구조체의 필드는 모두
Zig 기본값을 가져야 합니다.

- 기본 접두사는 소유 타입 이름(자유 함수면 함수 이름)입니다. `.prefix`가 이를 대체하고,
  `.prefix = ""`는 `Option`·`With<Field>`처럼 접두사 없는 이름을 만듭니다.
- 옵션 타입 이름은 `<접두사>Option`이고 `.type_name`이 이를 대체합니다.
- 설정 구조체는 비공개입니다. 옵션 타입의 이름만 공개 API에 남습니다.
- 각 `With*`의 doc comment가 Zig 기본값을 `Default: <값>`으로 싣습니다.
- 생성자는 옵션을 주지 않은 호출에서 Zig 기본값을 그대로 네이티브로 보냅니다.
- 옵션 필드가 여러 개여도 Go 가변 인자는 하나이므로, 한 함수에 옵션 매개변수는 하나만
  둘 수 있습니다.

이 변환은 Go 계층에만 적용됩니다. C 심볼, shim 시그니처와 인자 순서는 `.flatten`과
동일하므로 ABI가 바뀌지 않습니다.

## 콜백

등록 콜백은 이름이 있는 Go 함수 타입이 됩니다. `.go_error` 호출 site에서는 마지막에
`error`가 추가됩니다. retained 콜백은 소유 핸들을 닫을 때까지 네이티브에서 호출될 수
있습니다.

Go 콜백 panic은 네이티브 호출 프레임을 빠져나온 뒤 `*CallbackPanicError`로 다시 panic합니다.
정상 애플리케이션 error는 panic하지 말고 콜백 `error`를 사용하세요.

## 열거형과 union

열거형은 이름이 있는 정수 타입과 상수를 생성합니다. text feature가 있으면 `String`, parse와
인코딩 메서드가 추가됩니다.

tagged union 핸들은 `Tag()`, variant별 `As*()`와 `Variant()`를 제공합니다. 스냅샷 access가
설정되면 `Snapshot()`과 독립 Go 스냅샷 타입도 생성됩니다. 스냅샷 접근자는
`Ticks()`처럼 variant 이름을 사용하며 핸들의 `AsTicks()`와 구분합니다.

## session 타입

`zigo.session`으로 선언한 조합마다 Go 타입 하나가 생성됩니다. 멤버 핸들은 이미 만들어져
있어야 하고, session은 그것을 보관하고 순서대로 닫습니다.

```go
type Session struct{ ... }

func NewSession(queue *EventQueue) *Session
func (s *Session) AddStream(streams ...*Stream) *Session
func (s *Session) EventQueue() *EventQueue // primary 접근자는 타입 이름이다
func (s *Session) Streams() []*Stream      // 자식 접근자는 복수형이다
func (s *Session) Close() error
```

- 생성자는 primary만 받습니다. 자식은 타입마다 생성되는 `Add<Type>`이 입양하며, 가변 인자로
  여러 개를 한 번에 받고 session을 돌려주어 호출을 이어 쓸 수 있습니다. `nil` 핸들은
  무시합니다.
- 자식 접근자는 입양한 순서대로 복사본을 돌려줍니다. 반환 slice를 바꿔도 session은 바뀌지
  않습니다.
- `Close`는 자식을 입양 역순으로 먼저, primary를 마지막에 닫습니다. 부모의 네이티브
  `Close`가 자식이 열려 있는 동안 거절하므로, 이 순서가 계약입니다.
- `Close`는 멱등이고 동시 호출에 안전합니다. 두 번째 호출은 첫 번째의 결과를 그대로
  돌려줍니다. 멤버 하나가 실패해도 나머지를 닫고 오류는 `errors.Join`으로 합쳐집니다.
- `Close`가 끝난 뒤 `Add<Type>`에 넘긴 핸들은 즉시 닫힙니다. 입양 시점을 놓친 핸들이
  누수되지 않게 하기 위한 것이며, 정상 경로는 아닙니다.
- 생성 파일은 `var _ io.Closer = (*Session)(nil)`을 함께 써서 계약이 깨지면 소비자 빌드가
  아니라 이 패키지의 빌드가 먼저 실패하게 합니다.
- primary 접근자는 타입 이름, 자식 접근자는 기준 이름에 `s`를 붙인 이름, 입양 메서드는
  기준 이름 앞에 `Add`를 붙인 이름입니다. 기준 이름은 자식 타입 이름이며 `.children`의
  `.name`이 대체합니다. 이 셋과 session 자신의 `Close`가 겹치면 `ZIGO024`가 나옵니다.

session은 Go 계층에만 존재합니다. 네이티브 호출을 하지 않으므로 C 심볼, shim과 헤더는
바뀌지 않습니다.

## 스트림과 context

Zig `std.Io` 매개변수는 Go `io.Reader` 또는 `io.Writer`, cancel flag는
`context.Context`로 나타납니다. cancellation은 cooperative하므로 context가 끝나도 네이티브
함수가 flag를 확인할 때까지 호출이 반환되지 않을 수 있습니다.

## purego loader

explicit 또는 automatic 정책은 다음 API를 생성할 수 있습니다.

```text
DefaultLibraryName
LoadLibrary(path string) error
LibraryLoaded() bool
```

`.automatic_internal`은 이 API를 공개 패키지에서 숨깁니다. 로드한 라이브러리는 프로세스
종료까지 유지됩니다.

## 사용자 확장 파일

같은 패키지에 `_gen.go`가 아닌 파일을 추가해 도우미나 메서드를 작성할 수 있습니다. 공개
생성 이름과 `zigo`로 시작하는 private identifier를 다시 정의하지 마세요. raw 패키지는 내부
구현이며 호환성 보장 대상이 아닙니다.
