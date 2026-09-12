# 값과 데이터

이 가이드는 Zig 스칼라, 열거형, 구조체, 문자열, 슬라이스와 중첩 결과를 Go 값으로 표현하는 방법을
설명합니다. 전체 지원 조건은 [타입 대응 참조](../reference/type-mapping.md)가 정본입니다.

선언 조각은 별도 표시가 없으면 `src/bindings.zig`의 `zigo.define` 안에 있는
`.declarations` 목록에 넣습니다. `api`와 공통 import는 [최소 선언](README.md)을 사용합니다.
Go 호출 조각은 함수 본문용이며, 전체 import와 실행 방법은 연결된 예제를 참고하세요.

## 기본 스칼라

지원되는 스칼라는 등록 없이 함수 시그니처에서 변환됩니다.

```zig
pub fn add(a: i32, b: i32) i32 {
    return a + b;
}
```

```text
func Add(a int32, b int32) int32
```

`api.func("add", .{})`를 등록한 뒤 `calculator.Add(2, 3)`으로 호출합니다. 전체 흐름은
[함수와 패키지](functions-and-packages.md)에 있습니다. 오류를 반환하는 함수는
[콜백과 오류](callbacks-and-errors.md)의 Zig 오류 유니온 절을 참고하세요.

## 값의 의미 지정하기

같은 정수나 바이트 포인터라도 API 의미에 따라 Go 표현이 달라집니다.

```zig
api.func("echo", .{
    .params = &.{.{ .index = 0, .semantic = .utf8_string }},
    .returns = .{ .semantic = .utf8_string },
})
```

지원 semantic은 다음과 같습니다.

| semantic | Go에서의 의미 |
|---|---|
| `.utf8_string` | UTF-8 `string` |
| `.c_string` | sentinel C 문자열 |
| `.opaque_bytes` | 의미를 해석하지 않는 `[]byte` |
| `.codepoint` | Go `rune` |
| `.integer` | 코드포인트 자동 추론을 막는 정수 |

프로젝트 전체에서 u21과 sentinel 바이트 슬라이스를 각각 codepoint와 UTF-8로 취급한다면 기본값을
설정할 수 있습니다.

```zig
.defaults = .{
    .codepoints = .infer_u21,
    .strings = .infer_utf8,
},
```

명시적인 함수 또는 필드 semantic이 기본값보다 우선합니다.

## 열거형

```zig
api.enumType("Mode", .{})
```

생성 Go 패키지에는 이름이 있는 정수 타입과 Zig 태그에 대응하는 상수가 생깁니다.
알려지지 않은 값도 왕복해야 하는 open 열거형은 `.exhaustive = false`로 등록합니다.

```zig
api.enumType("Signal", .{ .exhaustive = false })
    .use(zigo.features.text, .{})
```

`features.text`는 parse, `MarshalText`와 `UnmarshalText`를 추가합니다.

## extern·packed 구조체 값

ABI가 값 전달에 적합한 구조체는 `val`로 등록합니다.

```zig
api.val("Point", .{})
```

`extern struct`의 `u32` 필드를 Go `rune`으로 나타내려면 의미를 지정합니다.
예를 들어 Zig 타입이 `pub const Codepoint = extern struct { value: u32 };`인 경우:

```zig
api.val("Codepoint", .{ .fields = &.{
    .{ .name = "value", .semantic = .codepoint },
} })
```

일반 Zig 구조체는 임의로 값 ABI에 넣지 않습니다. `extern struct`나 지원되는 `packed struct`
조건을 만족하지 않으면 핸들 또는 materialized 결과를 선택하세요.

값 전달은 다음처럼 Zig 입력과 Go 출력을 연결합니다. `Point`를 `api.val("Point", .{})`로,
`echoPoint`를 `api.func("echoPoint", .{})`로 등록합니다.

```zig
pub const Point = extern struct { x: i32, y: i32 };
pub fn echoPoint(value: Point) Point {
    return value;
}
```

공개 API는 `func EchoPoint(value Point) Point`이며, Go 호출은
`mylib.EchoPoint(mylib.Point{X: 2, Y: 3})`입니다. Go 값의 변경은 원래 Zig 객체를
변경하지 않습니다. 실제 값·배열 전달 검증은
[이벤트 큐 예제](../../examples/07-event-queue/README.md)에 있습니다.

## 옵션 구조체와 functional options

기본값을 가진 필드를 포함하는 Zig 구조체 매개변수는 `zigo.param.options`를 통해 Go의 functional options 생성자 패턴으로 노출할 수 있습니다.

### 대상

Zig에서 설정이나 옵션을 전달할 때 기본값이 있는 struct를 매개변수로 받는 패턴입니다.

```zig
pub const TerminalOptions = struct {
    cols: u16 = 80,
    rows: u16 = 24,
    max_scrollback_bytes: usize = 1024 * 1024,
};

pub fn init(gpa: std.mem.Allocator, options: TerminalOptions) error{Invalid}!Terminal {
    // ...
}
```

> [!IMPORTANT]
> `zigo.param.options`로 지정된 모든 필드는 반드시 Zig 기본값을 가져야 합니다. 기본값이 없는 필드는 오류(`ZIGO061`)가 발생하므로 위치 매개변수(`.flatten`)로 분리하거나 Zig에서 기본값을 지정해야 합니다.

### 선언 조각

바인딩에서 `zigo.param.options`를 사용해 펼칠 필드와 옵션 사양을 선언합니다.

```zig
Terminal.define(&.{
    Terminal.func("init", .{
        .params = &.{
            zigo.param.options(1, &.{ "cols", "rows", "max_scrollback_bytes" }, .{ .prefix = "" }),
        },
    }),
})
```

- `.prefix`: `With*` 함수 이름 및 옵션 타입 접두사입니다. 생략 시 소유 타입(`Terminal`) 이름이 사용되며, `""`를 주면 접두사 없이 `Option`, `WithCols` 등으로 방출됩니다.
- `.type_name`: 방출할 옵션 함수 타입의 이름입니다.

### 생성 Go

공개 Go API에는 `Option` 타입, `With*` 함수들, 그리고 가변 인자(`opts ...Option`)를 받는 생성자가 생성됩니다.

```go
// Option configures NewTerminal.
type Option func(*options)

type options struct {
	cols               uint16
	rows               uint16
	maxScrollbackBytes uint
}

// WithCols configures cols. Default: 80.
func WithCols(cols uint16) Option { ... }

// WithRows configures rows. Default: 24.
func WithRows(rows uint16) Option { ... }

// WithMaxScrollbackBytes configures max_scrollback_bytes. Default: 1048576.
func WithMaxScrollbackBytes(maxScrollbackBytes uint) Option { ... }

func NewTerminal(opts ...Option) (*Terminal, error) {
	cfg := options{
		cols:               80,
		rows:               24,
		maxScrollbackBytes: 1048576,
	}
	for _, opt := range opts {
		opt(&cfg)
	}
	// ...
}
```

### 호출 예

Go 호출자는 옵션을 생략하거나, 필요한 옵션만 지정하거나, 전체를 지정할 수 있습니다.

```go
// 1. 기본값으로 생성 (cols: 80, rows: 24, maxScrollbackBytes: 1MiB)
term1, err := event_queue.NewTerminal()

// 2. 일부 옵션만 변경
term2, err := event_queue.NewTerminal(event_queue.WithRows(50))

// 3. 모든 옵션 지정
term3, err := event_queue.NewTerminal(
	event_queue.WithCols(120),
	event_queue.WithRows(40),
	event_queue.WithMaxScrollbackBytes(8<<20),
)
```

이 패턴은 Go 계층에서만 펼쳐지며, C ABI와 네이티브 shim 함수 시그니처는 `.flatten`과 완전히 동일하게 유지됩니다(ABI 불변). 실제 동작은 [이벤트 큐 예제](../../examples/07-event-queue/README.md)를 참고하세요.

## Go 타입 어댑터

공개 Go API에서 기존 타입을 사용하려면 변환 함수와 함께 어댑터를 선언합니다.

```zig
api.val("Point", .{ .go = .{
    .type = "image.Point",
    .import = "image",
    .to_raw = "pointToRaw",
    .from_raw = "pointFromRaw",
} })
```

`to_raw`와 `from_raw` 함수는 사용자가 관리하는 같은 Go 패키지 파일에 구현합니다. zigo는
함수 이름과 import를 생성하지만 사용자 변환 코드의 의미까지 검증하지는 않습니다.

## 문자열과 슬라이스 입력

Go 문자열과 슬라이스 입력은 호출 동안 네이티브 코드에 빌려 줍니다. 네이티브 코드가 호출 뒤에도
포인터를 보관하면 안 됩니다. 장기 보관이 필요하면 Zig 쪽에서 복사하고 그 객체의 해제
경로를 따로 설계하세요.

버퍼 방향을 명시해야 할 때 도우미를 사용합니다.

```zig
api.func("transform", .{ .params = &.{
    zigo.param.input(0),
    zigo.param.output(1, .result),
} })
```

| 도우미 | 의미 |
|---|---|
| `param.input(index)` | 읽기 전용 입력 버퍼 |
| `param.output(index, .all)` | 호출 성공 시 전체 버퍼가 채워짐 |
| `param.output(index, .result)` | 함수 결과가 채운 원소 수 |
| `param.inout(index, written)` | 입력을 읽고 같은 버퍼에 결과 작성 |

`.result`를 사용하면 원래 Zig 반환값은 Go에서 `n`으로 소비되어야 하며 범위를 벗어난 값은
오류가 됩니다.

## caller-owned 결과

네이티브 할당을 반환하는 슬라이스나 문자열에는 해제 함수를 연결합니다.

```zig
const owned = zigo.result.releasedBy(api.ref("release"));

api.func("snapshot", .{ .returns = owned }),
api.func("release", .{}),
```

공개 래퍼는 결과를 Go 메모리로 복사하고 네이티브 해제를 호출합니다. 해제 함수는
공개 Go API에 노출되지 않을 수 있지만 바인딩 선언에는 포함되어야 합니다.

## optional

지원되는 `?T`는 Go API의 형태에 따라 포인터, `value, ok`, 또는 nil 가능한 슬라이스·핸들로
표현됩니다. 오류 유니온과 결합하면 `value, ok, error`가 될 수 있습니다. 구체적인 생성
시그니처는 `zig build go-report`와 생성 diff로 확인하세요.

## materialized 결과

중첩 포인터, 슬라이스와 문자열을 포함한 일반 구조체 결과를 한 번의 네이티브 호출로 복사하려면
`materialized`로 등록합니다.

```zig
api.materialized("Leaf", .{}),
api.materialized("Probe", .{ .fields = &.{
    .{ .name = "raw", .semantic = .opaque_bytes },
} }),
api.func("snapshot", .{
    .returns = zigo.result.releasedBy(api.ref("release")),
}),
```

결과 트리는 하나의 버퍼에 직렬화되고 Go 디코더가 독립된 Go 값으로 만듭니다. 자주
접근하는 변경 가능한 네이티브 객체에는 핸들 접근자가 더 적합할 수 있습니다.

[12-materialized의 Zig 구현](../../examples/12-materialized/src/root.zig)은
`pub fn snapshot() Probe`에서 중첩 `Probe` 값을 반환합니다.
[전체 바인딩](../../examples/12-materialized/src/bindings.zig)은 `.allocator = .c_allocator`,
관련 타입 등록과 `api.func("release", .{})`도 포함합니다. 위 선언 조각만으로는 충분하지 않습니다.
생성 Go API는 `func Snapshot() Probe`입니다.

```go
value := materialized.Snapshot()
fmt.Println(value.Name, value.Child.Value, value.Maybe == nil)
// materialized 42 true
```

Go 결과에는 `Close`가 필요 없습니다. 여기서 해제 계약은 직렬화 버퍼를 해제하는 것이며,
원래 Zig 결과 트리의 모든 포인터를 재귀적으로 해제한다는 뜻은 아닙니다.
전체 호출은 [Go 사용 예제](../../examples/12-materialized/go/materialized/example_test.go)를
확인하세요.

실행 예제는 [02-errors](../../examples/02-errors/README.md),
[07-event-queue](../../examples/07-event-queue/README.md)와
[12-materialized](../../examples/12-materialized/README.md)를 참고하세요.
