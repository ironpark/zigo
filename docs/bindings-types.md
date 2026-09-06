# 값 타입과 결과 트리

Go에 값으로 전달할 타입을 선택하고 등록합니다. 선언의 기본 형태는 [`bindings.zig` 선언](bindings.md)을 참고하세요.

단순 값은 [extern struct](#extern-struct-값), 비트 필드는 [packed struct](#packed-struct-값),
포인터를 포함한 반환 트리는 [materialized](#materialized-결과-트리)를 사용합니다.
객체 수명은 [handle 문서](bindings-handles.md), union은 [tagged union 문서](bindings-unions.md)에 있습니다.

## 정수 폭

C는 8, 16, 32, 64비트 정수만 이름 붙일 수 있습니다. `u21`이나 `i24`처럼 그 밖의 폭은
파라미터·반환값·error union payload와 직접 slice 원소 자리에서 다음 폭으로 승격되어
건너갑니다.

| Zig | C | Go |
| --- | --- | --- |
| `i8`, `u8`, `i16`, `u16`, `i32`, `u32`, `i64`, `u64` | 같은 폭 | 같은 폭 |
| `u21` | `uint32_t` | `uint32` |
| `i24` | `int32_t` | `int32` |
| `usize`, `isize` | `size_t`, `ptrdiff_t` | `uint`, `int` |

`semantic.json`에는 원래 폭(`"bits": 21`)이 그대로 기록되므로 `abi-diff`는 21 → 32 변경을
여전히 breaking으로 봅니다.

### 입력 범위와 오류

승격된 파라미터가 하나라도 있으면 그 함수의 공개 Go 시그니처는 `error`를 하나 더 반환합니다.
범위 검사는 Go에서, cgo 호출 이전에 이뤄지므로 `u21`에 담기지 않는 값은 native를 건드리지도
않고 `*RangeError`로 돌아옵니다. `errors.Is(err, ErrOutOfRange)`로 판별하고, `errors.As`로
`Operation`, `Parameter`, `Type`(`"u21"`)을 읽습니다. native 호출이 없었으므로
`LastErrorMessage()`도 그대로입니다. shim도 같은 검사를 유지하지만, 그것은 raw 패키지를
직접 부르는 코드를 위한 두 번째 방어선입니다.

### 비표준 폭 정수의 slice

`[]const u21` 입력은 Go의 `[]uint32`가 되고 shim이 바인딩의 `.allocator`로 `[]u21` 임시
버퍼를 만들어 범위를 검사하며 원소별로 좁힙니다. `.direction = .out`인 `[]u21`도 같은 임시
버퍼를 사용하고, 성공한 호출 뒤 caller-owned Go slice로 원소별 승격 복사합니다. 따라서 이런
slice가 하나라도 있으면 바인딩에 `.allocator`가 필요하며, 없으면 설정 방법을 적은
`ZIGO045`가 발생합니다. 입력 slice의 범위 밖 원소는 scalar 파라미터와 같은
`*RangeError`(`ErrOutOfRange`)이고 raw 호출에서는 같은 native range panic입니다.

반환 `[]u21`은 `.returns = .caller`와 `.release`가 있는 경우에만 지원합니다. shim이 각 원소를
승격한 뒤 Go가 새 `[]uint32`로 복사하고 즉시 원래 release를 호출합니다. 안정적으로 승격해 둘
메모리가 없는 borrowed narrow slice 반환은 `ZIGO018`로 거부됩니다. sentinel/optional narrow
slice도 아직 지원하지 않습니다.

승격 가능한 slice는 정수 자체가 직접 원소인 경우뿐입니다. `extern struct` field와 value struct
안의 field, tagged union payload, callback 시그니처, 중첩 slice는 C로 정해진 배치를 그대로
비추므로 그 자리의 비정규 폭은 기존처럼 `ZIGO018`로 거부됩니다.

## 코드포인트

Zig 텍스트 코드는 유니코드 코드포인트를 `u21`이나 `u32`로 다루지만 Go의 관용 타입은
`rune`입니다. 파라미터의 `param_meta`나 함수 메타데이터에 `.semantic = .codepoint`를 붙이면
공개 Go 시그니처가 `rune`을 씁니다. raw 계층과 C ABI는 그대로 `uint32`이므로 헤더·shim·
`abi-check`의 심볼 시그니처는 바뀌지 않고, Go 표면 변경만 breaking으로 기록됩니다.

```zig
.{ .path = "root.codepointWidth", .params = .{"cp"}, .param_meta = .{ .cp = .{ .semantic = .codepoint } } },
.{ .path = "root.sumCodepoints", .params = .{"values"}, .param_meta = .{ .values = .{ .semantic = .codepoint } } },
.{ .path = "root.takeCodepoints", .returns = .caller, .release = "root.freeCodepoints", .semantic = .codepoint },
```

| 자리 | Zig | Go |
| --- | --- | --- |
| scalar 파라미터·반환값 | `u21`, `u32` (`!T`, 반환 `?T` 포함) | `rune`, `(rune, error)`, `(rune, bool)` |
| plain slice 파라미터(입력·`.out`)와 반환 | `[]const u21`, `[]u32`, ... | `[]rune` |
| `.repr = .value` extern struct의 `u32` 필드(`.field_meta`) | `u32` | `rune` |
| 등록 callback의 `u32` 파라미터·결과(`.param_semantics`, `.semantic`) | `u32` | `rune` ([콜백](bindings-callbacks.md#콜백-타입-이름)) |

`[]rune`과 `[]uint32`는 메모리 배치가 같아 slice는 복사 없이 같은 메모리를 다시 해석합니다.
`.out` slice는 호출자의 `[]rune`에 직접 쓰이고, caller-owned 반환은 Go가 복사해 둔
`[]uint32`를 `[]rune`으로 봅니다.

코드포인트 파라미터(스칼라와 입력 slice)는 폭과 무관하게 Unicode 범위 `0..0x10FFFF`로
검사됩니다. 음수 `rune`이나 `0x110000` 이상은 native를 부르지 않고
`*RangeError{Type: "codepoint"}`(`ErrOutOfRange`)로 돌아오며, 그래서 `u32` 코드포인트
파라미터가 있는 함수도 `error`를 하나 더 반환합니다. C ABI와 shim은 바뀌지 않습니다.

extern struct 필드는 등록 항목의 `.field_meta`로 지정합니다. mirror struct의 해당 필드가
`rune`이 되고, 크기·offset이 같으므로 struct와 그 slice는 여전히 복사 없이 건너갑니다. 필드에는
범위 검사가 없어 잘못된 `rune`이 그대로 `uint32`로 재해석됩니다.

```zig
.{ .type = text.Glyph, .repr = .value, .field_meta = .{ .cp = .{ .semantic = .codepoint } } },
```

힌트를 붙일 수 있는 자리는 위 표가 전부입니다. optional 파라미터, sentinel slice, packed·
materialized struct 필드, tagged union payload, flatten 필드, 주입 파라미터, 콜백의 slice나
`u32`가 아닌 자리에 붙이면 `ZIGO053`입니다.

### u21 자동 추론

Zig에서 `u21`은 거의 항상 코드포인트입니다. `zigo.define`에 `.codepoints = .infer_u21`을
주면 `u21` 스칼라와 plain slice 파라미터·반환값(`!`, `?` 안 포함)이 힌트 없이도 코드포인트가
됩니다. 정수로 남겨야 하는 자리는 `.semantic = .integer`로 opt-out합니다. 추론은 reflection
단계에서 끝나므로 `semantic.json`에는 항상 명시적 `codepoint`가 기록되고 `.integer`는
기록되지 않습니다. `u32`는 정수로 쓰이는 경우가 훨씬 많아 추론하지 않습니다.

```zig
pub const bindings = zigo.define(.{
    .root = text,
    .codepoints = .infer_u21,
    .functions = .{
        .{ .path = "root.width", .params = .{"cp"} }, // cp: u21 → rune
        .{ .path = "root.bits", .params = .{"mask"}, .param_meta = .{ .mask = .{ .semantic = .integer } } },
    },
});
```

## Enum 이름 지정

enum은 signature에 나타나기만 해도 자동으로 등록되며, 이름은 `@typeName`의 마지막 점 뒤
segment에서 옵니다. 보통은 그것이 곧 타입 이름이지만, comptime 함수가 만든 enum은
`@typeName`이 그것을 만든 식으로 끝나므로(ghostty의 `lib.Enum(...)`은
`lib.Enum(...[0..4])`가 됩니다) 이름이 될 수 없는 문자열이 나옵니다. 그런 타입은 `ZIGO021`로
거부되고, `.repr = .enumeration`으로 등록해 이름을 줍니다.

```zig
.types = .{
    .{ .name = "CursorStyle", .type = library.CursorStyle, .repr = .enumeration },
},
```

Go `CursorStyle`, C `zg_cursor_style`, `semantic.json`의 `"name": "CursorStyle"`이 모두 이
이름을 따릅니다. `.name`을 생략하면 자동 등록과 같은 이름을 쓰되, 등록 자체는 signature가
그 타입에 닿기 전에 이뤄집니다. 등록된 enum은 컨테이너로 walk되지 않으므로 `.discover`가
켜져 있어도 enum 안의 선언은 발견되지 않습니다. 예제는 `09-type-relations`에 있습니다.

등록된 enum은 `@typeName` 문자열이 아니라 Zig의 comptime 타입 identity로 signature와
연결됩니다. 따라서 comptime 생성기가 서로 다른 enum에 같은(잘린) `@typeName`을 주더라도
각 파라미터와 반환값은 등록한 Go 타입을 유지합니다. 이 경우 `semantic.json`의 진단용
`zig_path`에는 `#CursorStyle`처럼 등록 이름이 붙어 서로 구분됩니다. 같은 Zig 타입을 서로
다른 이름으로 두 번 등록하는 것은 여전히 허용되지 않습니다.

Zig enum이 `enum(u8) { below, above, _ }`처럼 non-exhaustive이면 자동 등록이나 보통의
`.enumeration` 등록은 `ZIGO002`로 거부됩니다. 이름 붙은 tag 밖의 정수도 API 계약에 포함하려면
등록 항목에 opt-in을 적습니다.

```zig
.types = .{
    .{
        .name = "EraseDisplay",
        .type = library.EraseDisplay,
        .repr = .enumeration,
        .exhaustive = false,
    },
},
```

이 옵션은 실제 Zig 타입도 non-exhaustive일 때만 유효합니다. exhaustive enum에 붙이면
`ZIGO029`이며, 생략한 기존 등록은 그대로 exhaustive 계약입니다. tagged union의 tag가
non-exhaustive인 경우에는 이 opt-in을 적용하지 않으며 계속 거부합니다.

## Enum 텍스트 인코딩

생성된 enum은 기본적으로 `String()`만 갖습니다. JSON, CLI 플래그, 설정 파일처럼 문자열에서
값을 복원해야 하면 등록 항목에 `.text = true`를 적습니다.

```zig
.types = .{
    .{ .type = library.QueueSignal, .repr = .enumeration, .exhaustive = false, .text = true },
},
```

Go에는 다음이 추가됩니다.

| 생성물 | 동작 |
|---|---|
| `ParseQueueSignal(text string) (QueueSignal, error)` | Zig tag 이름을 값으로 바꿉니다 |
| `func (QueueSignal) MarshalText() ([]byte, error)` | `String()` 결과를 돌려주며 실패하지 않습니다 |
| `func (*QueueSignal) UnmarshalText([]byte) error` | `ParseQueueSignal`로 값을 채웁니다 |
| `EnumParseError{Type, Text}` | 알 수 없는 문자열의 오류 타입. 패키지마다 하나 생성됩니다 |

`encoding.TextMarshaler`·`TextUnmarshaler`를 구현하므로 `encoding/json`이 enum을 tag 이름
문자열로 읽고 씁니다. `.exhaustive = false`인 open enum은 `String()`이 이름 없는 값에
`QueueSignal(42)`를 돌려주므로, `Parse`도 같은 철자를 받아들여 모든 `String()` 결과가
왕복합니다. 숫자는 tag 타입의 폭으로 검사해 범위를 벗어나면 거부합니다.

이 옵션은 `.repr = .enumeration` 항목에서만 유효합니다. 다른 repr에 붙이면 `bindings.zig`
컴파일 오류이고, `semantic.json`을 직접 편집한 경우에는 `ZIGO051`입니다. signature에서
자동 등록된 enum에 텍스트 인코딩을 붙이려면 명시적으로 등록하세요. `abi-check`는 인코딩
추가를 호환으로, 제거를 breaking으로 보고합니다. 예제는 `07-event-queue`의 `QueueSignal`에
있습니다.

## Extern struct 값

Go에서 struct를 값처럼 주고받으려면 Zig 타입을 `extern struct`로 선언하고 등록합니다.

```zig
.types = .{
    .{ .type = mylib.Config, .repr = .value },
},
```

```go
cfg := Config{Width: 120, Mode: ModeActive}
Configure(cfg)
current := DefaultConfig()
```

C 경계에서는 aggregate를 값으로 전달하지 않습니다. 파라미터는 `const T*`, 반환은 `T*`
out parameter로 낮추고 생성 코드가 주소를 관리합니다.

모든 field가 bool, 정수/부동소수 scalar, 등록 enum, 또는 다시 적격한 `extern struct`여야
합니다. slice, pointer, optional, error union, callback, 일반 struct field와 빈 struct는
`ZIGO012`로 거부됩니다. 이런 scalar-only struct는 직접 slice 원소로도 사용할 수 있습니다.
다만 callback signature 안에 값을 넣으면 `ZIGO013`입니다. `?ExternStruct`는 통째로
nullable pointer 하나로 내려가므로 매개변수·반환·error payload 자리에서 지원합니다. field
추가·삭제·재정렬·타입 변경은 모두 breaking ABI 변경입니다.

```zig
pub fn estimate(output: []Stats) !usize { /* ... */ }

// bindings.zig
.{
    .path = "Context.estimate",
    .params = .{"output"},
    .param_meta = .{ .output = .{ .direction = .out, .written = .@"return" } },
},
```

직접 slice 원소인 `extern struct`는 C에서 `const T*`/`T*`와 길이로 전달됩니다. Go public
API는 `[]T`를 받습니다. bool field가 없는 struct는 Go mirror가 C layout과 byte 단위로
같으므로 slice 주소를 그대로 넘깁니다 — 들어갈 때도 나올 때도 복사가 없고, native는
호출자의 버퍼에 직접 씁니다. 이 동일성은 생성된 compile 시점 layout 단정이 지키므로,
어긋나면 Go build가 실패합니다. bool field가 있는 struct만 원소별 복사 경로를 씁니다.
반환 slice는 어느 쪽이든 `[]T`의 새 사본이며 native 메모리를 alias하지 않습니다.
out slice로 선언하려면 해당 파라미터에 `param_meta.direction = .out`을 명시해야 합니다.

### Go 타입 어댑터

생성된 mirror struct 대신 사용자가 고른 Go 타입으로 값을 주고받으려면 등록 항목에 `.go`를
적습니다. `image.Point`처럼 이미 쓰는 타입이나 `time.Duration` 같은 표준 타입을 API 표면에
바로 드러낼 수 있습니다.

```zig
.types = .{
    .{ .type = mylib.Point, .repr = .value, .go = .{
        .type = "image.Point",
        .import = "image",
        .to_raw = "pointToRaw",
        .from_raw = "pointFromRaw",
    } },
},
```

| 필드 | 역할 |
|---|---|
| `type` | 공개 API가 쓰는 Go 타입 철자. `pkg.Name` 또는 같은 패키지의 `Name` |
| `import` | `type`의 한정자가 가리키는 import 경로. 같은 패키지 타입이면 생략 |
| `to_raw` | `type` 값을 raw mirror(`raw.PointData`)로 바꾸는 함수 이름 |
| `from_raw` | raw mirror를 `type`으로 바꾸는 함수 이름 |

두 변환 함수는 사용자가 공개 패키지에 직접 씁니다. raw 패키지는 같은 모듈 안이라 import할
수 있습니다.

```go
package mylib

import (
    "image"

    "example.com/mylib/go/internal/raw"
)

func pointToRaw(p image.Point) raw.PointData { return raw.PointData{X: int16(p.X), Y: int16(p.Y)} }
func pointFromRaw(p raw.PointData) image.Point { return image.Point{X: int(p.X), Y: int(p.Y)} }
```

생성기는 `Point` mirror struct를 만들지 않고, 파라미터·반환·slice·optional·다른 struct의
필드에서 `image.Point`를 그대로 씁니다. 내부 변환 헬퍼 `zigoPointToRaw`/`FromRaw`는 두
함수를 호출하는 한 줄이 되며, 필요한 파일마다 `import`가 추가됩니다. 어댑터 타입은 raw와
레이아웃을 공유하지 않으므로 slice는 언제나 원소별로 변환됩니다.

같은 `.go`를 `.repr = .enumeration` 항목에도 붙일 수 있습니다. 그러면 enum 타입·상수·`String()`이
생성되지 않고 사용자 타입이 그 자리에 쓰이며, 변환 함수는 raw 정수(`uint8` 등)와 사용자
타입 사이를 오갑니다. tagged union의 tag enum에는 적용할 수 없습니다.

```zig
.{ .type = mylib.Speed, .repr = .enumeration, .go = .{
    .type = "Mode", .to_raw = "modeToRaw", .from_raw = "modeFromRaw",
} },
```

scalar에는 타입이 아니라 사용 지점에 붙입니다. 함수 메타의 `.go`는 반환값을, `param_meta`의
`.go`는 파라미터 하나를 바꿉니다. bool, 실수, 8·16·32·64비트 정수와 usize를 그대로 넘기는
자리에서만 쓸 수 있고, optional·slice·flatten 필드·범위 검사가 붙는 좁은 정수(`u21` 등)에는
쓸 수 없습니다.

```zig
.{
    .path = "root.elapsed",
    .params = .{"since"},
    .go = .{ .type = "time.Duration", .import = "time", .to_raw = "durationToRaw", .from_raw = "durationFromRaw" },
    .param_meta = .{ .since = .{ .go = .{ .type = "time.Duration", .import = "time", .to_raw = "durationToRaw", .from_raw = "durationFromRaw" } } },
},
```

```go
func durationToRaw(d time.Duration) uint64 { return uint64(d) }
func durationFromRaw(v uint64) time.Duration { return time.Duration(v) }
```

이 옵션은 `extern struct` 값, enum, 그리고 사용 지점의 plain scalar에만 유효합니다. packed
struct와 union, optional·slice·좁은 정수에는 적용할 수 없고 어긋나면 `ZIGO052`입니다.
`abi-check`는 어댑터의 추가·제거·변경을 breaking으로 보고합니다. 예제는
`09-type-relations`의 `Point`(struct)와 `LiveObjects`(반환 scalar)에 있습니다.

## Packed struct 값

정수 backing을 명시한 packed struct도 같은 `.repr = .value`로 등록합니다.

```zig
const Flags = packed struct(u16) {
    enabled: bool,
    level: u3,
    mode: Mode,
    reserved: u10,
};

.types = .{
    .{ .type = Mode, .repr = .enumeration },
    .{ .type = Flags, .repr = .value },
},
```

Go에는 필드가 있는 `Flags` mirror와 `func (Flags) Backing() uint16`,
`func FlagsFromBacking(uint16) Flags`가 생깁니다. C 경계에서는 struct layout을 공유하지 않고
항상 backing 정수 하나로 전달합니다. 따라서 scalar가 허용되는 직접 파라미터와 반환,
error payload, optional, extern struct field, `.fields` accessor, `.flatten` field, callback
파라미터에 같은 타입을 쓸 수 있습니다. bool, 정수, 등록 enum, 다시 등록한 정수-backed
packed struct만 필드가 될 수 있으며 그 밖의 필드는 이름을 포함한 `ZIGO044`로 거부됩니다.

`abi-diff`는 backing 폭을 유지한 채 끝에 필드를 추가하는 변경을 compatible로 봅니다.
필드 삭제·재정렬·폭/타입 변경과 backing 폭 변경은 breaking입니다.

## Atomic 값 scalar

`std.atomic.Value(T)`의 `T`가 bool, 정수, 부동소수 또는 등록 enum이면, 값이 허용되는 자리에서
Go에는 평범한 `T`로 보입니다. `.fields` getter와 setter는 각각
`load(.seq_cst)`와 `store(value, .seq_cst)`를 호출하므로 각 접근은 원자적입니다.

```zig
const Stats = struct {
    requests: std.atomic.Value(u64) = .init(0),
};

.types = .{
    .{ .type = Stats, .repr = .@"opaque", .fields = .{
        .{ .path = "requests", .set = true },
    } },
},
```

같은 규칙은 `param_meta.<name>.flatten`, `.repr = .value`인 `extern struct` field, 값 tagged
union payload, 함수의 값 파라미터와 반환에도 적용됩니다. shim은 경계에서 `.raw`로 풀고
`.init(value)`로 다시 감싸며 C와 Go 표면에는 scalar만 남깁니다. atomic field가 있는
`extern struct` slice는 주소를 재해석하지 않고 원소별로 복사합니다.

여러 field를 담은 struct나 union의 snapshot 전체가 한 번에 원자적인 것은 아닙니다. 원자성은
각 atomic field를 읽거나 쓰는 한 번의 접근에만 적용됩니다.

### 호출 범위 atomic 포인터

함수 파라미터의 `*std.atomic.Value(T)` 또는 `*const std.atomic.Value(T)`는 T가 `u32`, `i32`,
`u64`, `i64`일 때 각각 Go의 `*atomic.Uint32`, `*atomic.Int32`, `*atomic.Uint64`,
`*atomic.Int64`가 됩니다. 별도 메타데이터는 필요 없습니다.

```zig
pub fn increment(counter: *std.atomic.Value(u64)) void {
    _ = counter.fetchAdd(1, .seq_cst);
}
```

```go
var counter atomic.Uint64
Increment(&counter)
fmt.Println(counter.Load())
```

주소는 호출 동안만 native에 빌려줍니다. cgo는 호출 인자를 그동안 pin하고 purego 생성물은
`runtime.Pinner`로 같은 보장을 만들며, 둘 다 호출 뒤 `runtime.KeepAlive`까지 유지합니다.
native 함수는 주소를 저장하거나 호출이 끝난 뒤 다른 스레드에서 사용하면 안 됩니다.
`.retention = .retained`와 bool·8/16비트 정수·부동소수 같은 다른 atomic scalar는
`ZIGO043`입니다. `.cancel`의 `ctx` 변환과 전용 `*const std.atomic.Value(u32)` 계약은 이 기능과
별개이며 기존 동작을 그대로 유지합니다.

## Materialized 결과 트리

`.repr = .materialized`로 등록한 struct는 native handle이나 field accessor 대신 공개 Go
struct로 생성됩니다. 반환값, error-union payload, `[]T` 반환은 트리 전체를 하나의 버퍼로
직렬화하고 Go에서 `string`, `[]T`, `*T` 필드로 해독합니다. 배치 `[]T`도 항목마다 호출하지
않고 전체 slice에 버퍼 하나만 사용합니다.

```zig
pub const bindings = zigo.define(.{
    .root = library,
    .allocator = .c_allocator,
    .types = .{
        .{ .type = library.Result, .repr = .materialized },
        .{ .type = library.Child, .repr = .materialized },
    },
    .functions = .{
        .{ .path = "root.probeMany", .returns = .caller, .release = "root.release" },
        .{ .path = "root.release", .params = .{"buffer"} },
    },
});
```

함수는 등록 allocator와 `.returns = .caller`, `[]u8`을 받는 `.release`를 사용해야 합니다.
scalar, bool, 등록 enum, string, 중첩 materialized struct, materialized struct pointer와 optional
pointer, 그리고 scalar/string/materialized struct slice를 지원합니다. `?i32`·`?Status` 같은
optional scalar와 `?[]const u8` optional string 필드도 지원하며 Go에서는 `*int32`, `*string`처럼
포인터로 노출되어 nil이 없음을 뜻합니다. optional slice(`?[]T`)와 optional 원소(`[]?T`), 순환,
opaque pointer, callback, union은 `ZIGO048`과 해당 field path로 거부됩니다.

위 예제는 `probeMany`가 `Result`를 반환하고 `release`가 버퍼를 해제하는 라이브러리를
가정합니다. 실행 가능한 전체 구현은 [12-materialized](../examples/12-materialized)에 있습니다.

`.direction = .out`인 `[]T` 파라미터는 `.written = .@"return"`과 함께 사용할 수 있습니다.
Go slice의 capacity만 native에 전달하고 Zig 임시 slice에 결과를 만든 뒤 작성된 prefix 전체를
한 버퍼로 직렬화하므로 Go pointer가 materialized tree 안으로 넘어가지 않습니다.

## Generic 타입과 Zig 선언 경로

구체화된 generic 타입마다 고유한 Go 이름을 지정합니다.

```zig
.types = .{
    .{ .name = "FloatBuffer", .type = mylib.Buffer(f32), .repr = .@"opaque" },
    .{ .name = "IntBuffer", .type = mylib.Buffer(i32), .repr = .@"opaque" },
},
```

generic 함수는 구체화 전에는 signature가 없으므로 직접 노출할 수 없습니다.

### 생성 코드가 Zig 타입을 찾는 경로

shim은 root module을 `target`으로 import하고 등록 타입을
반영된 Zig 경로로 적습니다. root 안의 타입(`root.Terminal.Options`)은 `target.Terminal.Options`,
dependency module의 타입은 경로가 접두사로 겹치는 가장 가까운 등록 조상을 거쳐 적습니다.
등록 조상이 없는 dependency module 타입은 root가 다시 내보낸 이름으로 닿습니다. 등록
`.name`이 Zig 이름과 같으면 `target.<name>` 하나이고, 다르면(`.type = lib.ProbeReader,
.name = "Probe"`) shim이 module 아래 경로 → Zig 타입 이름 → 등록 이름 순으로 root가 `pub`으로
내보내는 첫 선언을 comptime에 고릅니다. 어느 것도 없으면 후보를 나열한 컴파일 에러가 납니다.
`.opaque`, `.value`, `.materialized` 모두 같은 규칙입니다.
