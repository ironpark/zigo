# `bindings.zig` 선언

`bindings.zig`는 Zig 구현을 수정하지 않고 Go에 노출할 API와 reflection만으로 알 수 없는
의미를 선언하는 파일입니다. 빌드 연결은 [빌드 설정](configuration.md), 지원하지 않는 타입은
[지원 범위와 제한사항](limitations.md)을 참고하세요.

## 기본 구조

```zig
const zigo = @import("zigo");
const mylib = @import("mylib");

pub const bindings = zigo.define(.{
    .root = mylib,
    .types = .{
        .{ .type = mylib.Context, .repr = .@"opaque" },
    },
    .functions = .{
        .{ .path = "Context.create", .params = .{"name"} },
        .{ .path = "Context.deinit" },
        .{ .path = "root.version" },
    },
});
```

| 그룹 | 역할 |
|---|---|
| `root` | 경로를 해석할 기준 module. 항상 필요 |
| `types` | opaque handle, extern struct 값, enum, tagged union, callback 등록 |
| `functions` | 노출할 함수와 추가 메타데이터 |

`root.<name>`은 module 자유 함수를, `<Type>.<name>`은 등록 타입의 함수를 가리킵니다. 경로가
공개 함수를 가리키지 않으면 compile error입니다. 함수 항목의 `.name`은 경로가 아니라 생성할
Go 이름만 바꿉니다.

경로는 임의 깊이의 namespace struct를 따라갑니다. 루트에 `pub fn` 없이 API를 struct로
묶는 module은 Zig 호출자가 쓰는 것과 같은 철자를 그대로 씁니다.

```zig
.functions = .{
    .{ .path = "root.unicode.codepointWidth", .params = .{"cp"} },
    .{ .path = "root.osc.parser.parse" },
},
```

마지막 segment 앞의 모든 segment는 공개 container 타입(struct, union, enum, opaque)이어야
합니다. 첫 segment만 `root` 또는 등록된 `.types` 항목 이름으로 해석되고, 나머지는 그 안의
공개 선언입니다. namespace는 `semantic.json`에 점으로 이어진 경로(`"unicode"`,
`"osc.parser"`)로 기록되며 여기서 나머지 이름이 모두 파생됩니다.

| 경로 | C 심볼 | raw Go | ABI identity |
|---|---|---|---|
| `root.version` | `zg_version` | `Version` | `version` |
| `Context.create` | `zg_context_create` | `ContextCreate` | `Context.create` |
| `root.unicode.codepointWidth` | `zg_unicode_codepoint_width` | `UnicodeCodepointWidth` | `unicode.codepointWidth` |
| `root.osc.parser.parse` | `zg_osc_parser_parse` | `OscParserParse` | `osc.parser.parse` |

공개 Go 함수 이름은 namespace를 붙이지 않고 함수 이름만 씁니다(`CodepointWidth`). 서로 다른
namespace에 같은 이름의 함수가 있다면 `.name`으로 하나를 바꿉니다.

### 공개 Go 이름 충돌

receiver가 없는 함수(namespace 함수와 최상위 함수)는 모두 같은 이름 공간을 나눠 쓰고, 등록된
타입 이름도 여기 포함됩니다. 메서드는 receiver별로 별도의 이름 공간을 가지므로 다른 receiver의
같은 메서드 이름은 충돌이 아닙니다(`Counter.reset`과 `Timer.reset`은 둘 다 `Reset` 메서드가
됩니다). 같은 enum의 두 tag가 PascalCase로 변환했을 때 같은 이름이 되는 경우도 같은 검사를
받습니다.

생성기는 이런 충돌을 생성 시점에 `ZIGO024`로 거부하며, 메시지에 충돌하는 두 Zig 경로를 모두
적습니다. 함수는 `.name`으로, 타입은 `.types`의 `.name`으로 한쪽 이름을 바꿔 충돌을 없앱니다.

## 명시 목록과 자동 발견

안정적인 공개 API가 중요하다면 `functions`에 함수를 명시하세요. 목록에 없는 함수는 노출되지
않으므로 Zig의 새 `pub fn`이 의도치 않게 Go ABI에 들어오지 않습니다.

Zig 공개 API 전체가 바인딩 API인 큰 module은 자동 발견을 선택할 수 있습니다.

```zig
pub const bindings = zigo.define(.{
    .root = mylib,
    .discover = .public,
    .types = .{
        .{ .type = mylib.Context, .repr = .@"opaque" },
    },
    .functions = .{
        // 자동 발견된 함수에 메타데이터를 보강합니다.
        .{ .path = "Context.name", .semantic = .utf8_string },
    },
    .exclude = .{"Context.debugState"},
});
```

`.discover = .public`은 한 단계만 봅니다. namespace struct 안까지 내려가려면
`.discover = .recursive`를 씁니다. 기본값을 바꾸지 않는 이유는 기존 바인딩의 노출 표면이
조용히 넓어지지 않게 하기 위해서입니다. 재귀 발견은 container 안에 **작성된** 선언만
따라가므로 `@This()` alias나 다시 내보낸 import를 건너뜁니다. 중첩 경로도 `exclude`에
같은 철자로 적습니다(`"root.osc.internalHelper"`).

자동 발견은 등록한 타입의 공개 함수, 이어서 `root` module의 공개 함수를 찾습니다.
`functions`는 발견 대상을 제한하지 않고 메타데이터를 붙이며, `exclude`가 제외 대상을
지정합니다. 존재하지 않거나 중복된 경로, `functions`와 `exclude`의 충돌은 compile
error입니다.

자동 발견에서는 새 `pub fn`이 C/Go API에도 추가됩니다. 생성물 `go-check`와 독립 배포
계약이 있다면 `abi-check`를 함께 사용하세요.

## 함수 메타데이터

| 필드 | 역할 |
|---|---|
| `path` | `root.<name>` 또는 `<Type>.<name>` 선언 경로 |
| `name` | 공개 Go 함수 이름 override |
| `params` | Go가 넘기는 파라미터의 이름 목록 |
| `constructs` | 이 함수가 만드는 opaque 타입 이름 |
| `destroys` | 이 함수가 없애는 opaque 타입 이름 |
| `param_meta` | 파라미터별 `semantic`, `retention`, `direction`, `written`, `buffer` |
| `semantic` | 반환값 의미. 예: `.utf8_string` |
| `returns` | 반환 pointer의 ownership |

문자열 의미, 반환 pointer ownership, retained pointer와 callback 수명은 타입만으로 결정할 수
없으므로 명시해야 합니다.

```zig
.{
    .path = "Context.create",
    .params = .{ "name", "callback", "userdata" },
    .param_meta = .{
        .name = .{ .semantic = .utf8_string },
        .callback = .{ .retention = .retained },
    },
}
```

`params`에는 **Go가 넘기는 파라미터만** 적습니다. receiver(`self`)와 주입 파라미터
(`std.mem.Allocator`, `std.Io`)는 C에도 Go에도 나타나지 않으므로 이름을 붙일 자리가
없습니다. `fn freeString(gpa: Allocator, str: []const u8) void`의 `params`는
`.{"str"}` 하나입니다. 개수가 맞지 않으면 reflection 단계에서 `ZIGO027`로 거부됩니다.

`param_meta`의 field는 파라미터 이름과 일치해야 합니다. 해당 이름을 reflection 단계에서
확실히 식별하려면 같은 항목에 `params`도 적으세요. 이름은 명시적 `params`, 대상 source AST,
`p0` fallback 순으로 결정됩니다.

### 콜백 타입 이름

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

### 콜백이 돌려주는 Go error

기본적으로 Go 콜백은 Zig 시그니처가 말하는 값만 돌려줍니다. `param_meta.<이름>.go_error`를
켜면 Go 타입이 `error`를 하나 더 돌려주고, 그 error가 공개 함수의 반환값으로 나옵니다.

```zig
.{
    .path = "CallbackContext.create",
    .params = .{ "callback", "userdata" },
    .param_meta = .{ .callback = .{ .retention = .retained, .go_error = true } },
}
```

```go
type Observer func(int32) (int32, error)   // .go_error = false 였다면 func(int32) int32

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

retained 콜백의 error는 그것이 일어난 호출이 이미 끝났으므로 **그 handle을 건드리는 다음
호출**에서 나옵니다. panic 규칙과 같습니다. 한 번 반환되면 지워지므로 그다음 호출은 다시
깨끗합니다.

C ABI는 바뀌지 않습니다 — `go_error`는 Go 표면만 넓힙니다. 다만 Go 콜백 타입이 바뀌므로
`abi-diff`는 이것을 breaking으로 봅니다.

> **`go_error`는 파라미터가 아니라 시그니처의 성질입니다.** 한 바인딩 안에서 같은 ABI
> 시그니처는 Go 타입 하나(그리고 purego에서는 dispatcher 하나)를 공유하므로, 한 곳에
> `.go_error = true`를 켜면 그 시그니처를 쓰는 모든 콜백 파라미터가 `error`를 돌려주는
> 타입이 됩니다.

## 정수 폭

C는 8, 16, 32, 64비트 정수만 이름 붙일 수 있습니다. `u21`이나 `i24`처럼 그 밖의 폭은
파라미터·반환값·error union payload 자리에 한해 다음 폭으로 승격되어 건너갑니다.

| Zig | C | Go |
| --- | --- | --- |
| `i8`, `u8`, `i16`, `u16`, `i32`, `u32`, `i64`, `u64` | 같은 폭 | 같은 폭 |
| `u21` | `uint32_t` | `uint32` |
| `i24` | `int32_t` | `int32` |
| `usize`, `isize` | `size_t`, `ptrdiff_t` | `uint`, `int` |

`semantic.json`에는 원래 폭(`"bits": 21`)이 그대로 기록되므로 `abi-diff`는 21 → 32 변경을
여전히 breaking으로 봅니다.

승격된 파라미터가 하나라도 있으면 그 함수의 공개 Go 시그니처는 `error`를 하나 더 반환합니다.
범위 검사는 Go에서, cgo 호출 이전에 이뤄지므로 `u21`에 담기지 않는 값은 native를 건드리지도
않고 `*RangeError`로 돌아옵니다. `errors.Is(err, ErrOutOfRange)`로 판별하고, `errors.As`로
`Operation`, `Parameter`, `Type`(`"u21"`)을 읽습니다. native 호출이 없었으므로
`LastErrorMessage()`도 그대로입니다. shim도 같은 검사를 유지하지만, 그것은 raw 패키지를
직접 부르는 코드를 위한 두 번째 방어선입니다.

승격은 값 하나가 shim을 지나갈 때만 가능합니다. `extern struct` 필드, slice 원소(`[]u21`),
콜백 시그니처는 C로 바이트 그대로 비추므로 그 자리의 비정규 폭은 `ZIGO018`로 거부됩니다.

## 슬라이스 반환 소유권

슬라이스를 반환하는 함수는 호출 시점에 native 메모리에서 Go가 소유한 새 사본을 만듭니다.
따라서 반환된 `[]T`는 다음 native 호출이나 원본 객체의 `Close`와 독립적이며, 호출자는
반환된 사본만 수정할 수 있습니다. tagged-union의 숫자 slice payload도 같은 복사 계약을
따릅니다. 이 복사가 부담이라면 결과를 `.direction = .out` 파라미터로 받는
[`...Into(dst)` 패턴](#큰-결과는-out-파라미터로)을 쓰세요.

실패할 수 있는 slice 반환(`![]T`)도 같은 방식으로 내려갑니다. C 시그니처는 정수 코드를
반환하고 `T** out_result_ptr, size_t* out_result_len`을 그대로 받으며, 공개 Go는
`([]T, error)`가 됩니다. 오류일 때 생성된 코드는 out 파라미터를 읽지 않고 `nil`과 오류를
돌려주므로, native가 아무것도 기록하지 않은 상태를 그대로 안전하게 표현합니다. 원소는
스칼라·enum·`extern struct`만 쓸 수 있고 `![]string`이나 `!?[]T`는 지원하지 않습니다.

## Sentinel C 문자열

Zig API가 NUL 종료 포인터를 쓴다면 `[*:0]const u8`를 그대로 노출할 수 있습니다. 이 타입은
별도 `.semantic` 메타데이터 없이 `string`으로 반영됩니다.

```zig
pub fn echoCString(text: [*:0]const u8) [*:0]const u8 {
    return text;
}
```

cgo raw는 호출 중 `C.CString`을 만들고 호출이 끝나면 `free`하며, purego raw는 NUL을 붙인
Go byte buffer를 호출 동안만 native에 전달합니다. 반환 문자열도 호출 시점에 Go `string`으로
복사합니다. 따라서 Go 포인터가 native 메모리로 넘어가지 않습니다. mutable `[*:0]u8`,
0이 아닌 sentinel, 기타 many-pointer는 지원하지 않습니다.

## 문자열 slice 매개변수

여러 문자열을 입력으로 넘길 때는 `[]const []const u8`에 `.utf8_string`을 지정하거나,
element를 `[:0]const u8` 또는 `[*:0]const u8`로 선언할 수 있습니다. 세 형태 모두 public
Go에서는 `[]string`이 됩니다. 일반 unsentinel 형태는 sidecar에서 의미를 지정해야 합니다.

```zig
pub fn extractPaths(paths: []const []const u8) usize { /* ... */ }

// bindings.zig
.{
    .path = "Context.extractPaths",
    .params = .{"paths"},
    .param_meta = .{ .paths = .{ .semantic = .utf8_string } },
},
```

native ABI는 `paths_data`, `paths_data_len`, `paths_lens`, `paths_count` 네 scalar 인자로
내려갑니다. 각 문자열의 바이트 뒤에 NUL을 하나 붙이고 `paths_lens`에는 NUL을 제외한 길이를
기록합니다. cgo와 purego 모두 pointer-free Go 배열 하나씩만 만들어 호출 중 빌려주며
문자열별 malloc은 하지 않습니다. 빈 `[]string`과 빈 문자열 원소도 지원합니다. `[]string`
반환은 지원하지 않습니다.

## 타입 등록 선택

`repr`은 타입의 ABI 표현을, `access`는 tagged union 내용을 Go에서 읽는 방법을 선택합니다.
enum 항목의 `exhaustive = false`는 Zig의 non-exhaustive enum을 그대로 공개하는 opt-in입니다.

| `repr` | 용도 |
|---|---|
| `.@"opaque"` | pointer handle과 수명주기 |
| `.value` | 적격한 `extern struct`의 Go 값 mirror |
| `.tagged_union` | pointer handle을 통한 tagged union 접근 |
| `.enumeration` | enum에 Go 타입 이름을 부여. `.name` 선택 |
| `.callback` | `*const fn` alias에 Go 타입 이름을 부여. `.name` 필수 |

| `access` | 용도 |
|---|---|
| `.projection` | variant별 tag/payload accessor. 기본값 |
| `.snapshot` | tag와 scalar payload를 한 native 호출로 복사. projection도 유지 |

generic 타입은 구체화한 타입에 고유 이름을 붙여 등록합니다.

```zig
.types = .{
    .{ .name = "FloatBuffer", .type = mylib.Buffer(f32), .repr = .@"opaque" },
    .{ .name = "IntBuffer", .type = mylib.Buffer(i32), .repr = .@"opaque" },
},
```

generic 함수는 구체화 전에는 signature가 없으므로 직접 노출할 수 없습니다.

### Allocator와 Io 주입

`std.mem.Allocator`와 `std.Io`는 C로 표현할 수 없습니다. 바인딩이 값을 한 번 정하면
그 파라미터는 C와 Go 시그니처에서 빠지고 shim이 채웁니다.

```zig
pub const bindings = zigo.define(.{
    .root = library,
    .allocator = .smp_allocator, // 또는 .c_allocator, .page_allocator, 또는 "gpa" 같은 선언 경로
    .io = "io", // 선언 경로만 받습니다. std에는 기본 Io가 없습니다
    // ...
});
```

`fn open(gpa: Allocator, name: []const u8) !*Store`는 C에서
`int32_t zg_store_open(const uint8_t *name_ptr, size_t name_len, zg_store **out_result)`,
Go에서 `NewStore(name string) (*Store, error)`가 됩니다. 문자열 값(`"gpa"`)은 바인딩된
루트 모듈 기준으로 해석되며, `.functions`의 경로와 같은 기준입니다.

주입 파라미터는 `.params`에도, `param_meta`에도 나오지 않습니다. release 함수도
마찬가지입니다: `fn freeString(gpa: Allocator, str: []const u8) void`는 slice 하나만 받는
release 함수로 취급되고, shim이 호출할 때 allocator를 채웁니다.

기본값은 없습니다. 설정 없이 그런 파라미터를 만나면 `ZIGO022`로 거부합니다 — 어떤 메모리를
쓸지는 zigo가 대신 정할 문제가 아닙니다. 주입 파라미터는 `semantic.json`에
`"injected": "allocator"`로 남고, 주입 여부가 바뀌면 `abi-diff`가 breaking으로 봅니다.

### `std.Io` 스트림 파라미터

`*std.Io.Writer`와 `*std.Io.Reader` 파라미터는 Go의 `io.Writer`와 `io.Reader`가 됩니다.
등록도 메타데이터도 필요 없습니다 — 타입 자체가 결정합니다.

```zig
// Zig
pub fn dump(self: *Document, w: *std.Io.Writer) error{WriteFailed}!void { ... }
pub fn load(self: *Document, r: *std.Io.Reader) error{ReadFailed}!usize { ... }
```

```go
// Go
func (d *Document) Dump(w io.Writer) error
func (d *Document) Load(r io.Reader) (uint, error)
```

shim이 파라미터마다 어댑터를 만들어 대상 함수에 넘깁니다. 어댑터는 staging 버퍼를 들고
있고, 버퍼가 찰 때만 Go의 `Write`/`Read`를 부릅니다. Zig 쪽이 한 줄씩 `writeAll`을 해도
경계를 넘는 횟수는 버퍼 크기가 정합니다: 총 `N` 바이트를 쓰면 `Write` 호출은
`ceil(N / 버퍼)`회를 넘지 않습니다. 함수가 돌아오기 전에 shim이 `flush`하므로 대상 함수가
직접 flush하지 않아도 남은 바이트가 나갑니다.

버퍼 크기는 `param_meta.<name>.buffer`로 바꿉니다. 기본값 65536, 최소 4096, 최대 16 MiB이며,
범위 밖은 `ZIGO023`으로 거부합니다. 262144바이트를 넘으면 스택 배열 대신 힙에서 잡습니다 —
바인딩이 `.allocator`를 정했으면 그 allocator, 아니면 `std.heap.c_allocator`입니다.

```zig
.{ .path = "Document.load", .params = .{"r"}, .param_meta = .{ .r = .{ .buffer = 4096 } } }
```

**실패와 panic.** Go `Write`가 error를 반환하면 그 error가 저장되고, native 호출이 끝난 뒤
공개 함수가 `*StreamError`로 감싸 돌려줍니다. native 결과보다 우선합니다: 출력이 도착하지
않은 작업에 라이브러리가 성공을 보고했더라도 호출자가 원하는 것은 자기 error입니다.
`Unwrap`이 원래 error를 내주므로 `errors.Is`가 그대로 통합니다. short write는
`io.ErrShortWrite`입니다. Go `Read`가 `0, io.EOF`를 주면 스트림 끝이고, 그 외의 error는
`*StreamError`로 돌아옵니다. Go 쪽이 panic하면 기존 콜백 경로와 같이
`*CallbackPanicError`로 재전파되며, 어댑터는 panic한 프레임을 두 번 부르지 않습니다.
`nil` 스트림은 native를 부르기 전에 `ErrNilStream`을 감싼 `*StreamError`로 거부합니다.

스트림 파라미터가 있는 함수는 Zig 반환 타입과 무관하게 Go에서 `error`를 함께 반환합니다.

**`[]byte` 무콜백 경로.** `io.Reader` 인자가 남은 바이트를 통째로 내줄 수 있으면 zigo는
슬라이스 하나를 그대로 넘기고, shim은 `std.Io.Reader.fixed`로 감쌉니다. 이때 경계를 넘는
콜백은 **0회**입니다. 자격이 있는 타입은 두 가지입니다.

- `Bytes() []byte`를 가진 타입 — 표준 라이브러리의 `*bytes.Buffer`가 여기 해당합니다.
  관례상 "아직 읽지 않은 바이트"를 뜻하는 메서드입니다.
- `zigoBytes() []byte`를 가진 타입 — 직접 정의한 타입을 이 경로에 넣는 공개 훅입니다.
  두 메서드가 다 있으면 `zigoBytes()`가 이깁니다.

그 밖의 모든 `io.Reader`(`*bytes.Reader`, 파일, 소켓, `io.LimitReader` 등)는 예전처럼
트램폴린으로 한 덩어리씩 읽습니다. `*bytes.Reader`에는 내부 슬라이스를 내주는 메서드가
없으므로 빠른 경로에 들어가지 않습니다.

빈 슬라이스도 "없음"이 아니라 "비어 있음"입니다: 빈 `*bytes.Buffer`는 빠른 경로로 즉시
스트림 끝이 되고, 콜백으로 되돌아가지 않습니다.

> **주의.** 이 경로를 타면 zigo는 Go reader를 **전진시키지 않습니다**. ABI가 native가
> 몇 바이트를 읽었는지 보고하지 않기 때문입니다. 호출 뒤에도 `*bytes.Buffer`에는 같은
> 바이트가 그대로 남아 있습니다. 한 reader를 여러 호출에 나눠 쓰면서 소비 위치가
> 중요하다면 `bytes.NewReader(...)`처럼 빠른 경로에 들어가지 않는 타입을 쓰십시오.

**스레드.** 콜백은 native 호출 안에서 같은 스레드로 동기 호출되므로, Go 값은 호출한
goroutine이 계속 소유합니다. 대상 함수가 어댑터를 다른 스레드로 넘겨 호출이 끝난 뒤에도
쓰면 동작은 정의되지 않습니다.

**허용되지 않는 위치.** 어댑터가 호출 스택에 살기 때문에 스트림은 파라미터 자리에서만,
그리고 call-scoped로만 쓸 수 있습니다. extern struct 필드, 콜백 시그니처, 슬라이스 원소,
optional, `.retention = .retained`는 각각 이유를 담은 `ZIGO023`으로 거부합니다. 반환 위치는
아래의 규칙을 따릅니다.

### Zig가 내주는 스트림

메서드가 스트림을 **내줄** 수도 있습니다. 포인터 자체는 Go로 건너가지 않습니다 — 그것은
객체의 것이고, 객체보다 오래 사는 Go 값은 안전하게 만들 수 없기 때문입니다. 대신 Go가
그 스트림에 실제로 원하는 것, 즉 `io.Writer`·`io.Reader`가 요구하는 메서드를 handle에
생성합니다.

```zig
// Zig
pub fn writer(self: *Sink) *std.Io.Writer { return &self.inner.writer; }
pub fn reader(self: *Source) *std.Io.Reader { return &self.inner; }
```

```go
// Go
func (s *Sink) Write(bytes []byte) (int, error)
func (s *Sink) Flush() error
func (s *Source) Read(buffer []byte) (int, error)

io.Copy(sink, src)   // 둘 다 그대로 표준 인터페이스다
io.Copy(dst, source)
```

메서드마다 shim이 `writer()`/`reader()`를 **다시 부릅니다**. 포인터를 어디에도 보관하지
않으므로 상하지 않고, 수명 질문은 receiver handle의 기존 획득/해제/poison 규칙이 그대로
답합니다 — 닫힌 handle의 `Write`는 다른 메서드와 똑같이 `ErrInvalidHandle`입니다.

`Read`는 `io.Reader` 규약을 따릅니다: 스트림 끝은 0바이트가 아니라 `io.EOF`입니다. Zig 쪽은
`readSliceShort`가 짧은 개수로 끝을 알리고, 그 0을 Go가 `io.EOF`로 옮깁니다.

규칙: 스트림 반환은 **메서드**여야 하고(생성된 연산이 receiver에게 다시 물어야 하므로),
**파라미터가 없어야 하며**(`Write`/`Read`/`Flush`에 그것을 실을 자리가 없습니다), error
union이나 optional 안이 아니라 **반환 타입 그 자체**여야 합니다. 셋 다 `ZIGO023`입니다.
한 타입이 writer 하나와 reader 하나를 함께 낼 수는 있지만, 같은 방향을 둘 내면 Go 이름이
겹쳐 `ZIGO024`가 됩니다.

`semantic.json`에는 Zig 메서드(`Sink.writer`)가 그대로 기록되고, 연산으로의 확장은 파싱과
lowering 사이에서 일어납니다. `abi-diff`가 비교하는 것은 Zig 표면입니다.

## 취소 (`.cancel`)

긴 native 호출을 Go의 `context.Context`로 끊을 수 있습니다. 함수 메타 `.cancel`이 어느
파라미터가 취소 플래그인지 말하면, 그 파라미터는 Go 시그니처에서 사라지고 대신
`ctx context.Context`가 **첫 인자**로 들어옵니다.

```zig
// Zig — 플래그를 폴링하는 것은 대상 함수의 책임이다.
pub const ReduceError = error{ Empty, Canceled };

pub fn reduce(self: *Hub, rounds: u32, cancel: *const std.atomic.Value(u32)) ReduceError!f64 {
    var round: u32 = 0;
    while (round < rounds) : (round += 1) {
        if (cancel.load(.monotonic) != 0) return error.Canceled;
        // ... 실제 작업 ...
    }
    return total;
}
```

```zig
.{
    .path = "Hub.reduce",
    .params = .{ "rounds", "cancel" },
    .cancel = .{ .param = "cancel" },
}
```

```go
func (h *Hub) Reduce(ctx context.Context, rounds uint32) (float64, error)

ctx, cancel := context.WithTimeout(context.Background(), time.Second)
defer cancel()
total, err := hub.Reduce(ctx, 1 << 30)
errors.Is(err, context.DeadlineExceeded) // true
```

**설계.** 플래그는 **Go가 소유하는 `uint32` 한 워드**입니다. 폴링 함수 포인터를 넘기는
방식과 비교해 이쪽을 골랐습니다: 폴링은 원자적 load 하나라 경계를 넘지 않고, 아무리 촘촘히
검사해도 공짜입니다. 함수 포인터라면 폴링마다 Go로 되돌아가야 하고, 그것은 취소 검사에
정확히 어울리지 않는 비용입니다. purego에도 새 dispatcher가 필요 없습니다.

**타입은 `*const std.atomic.Value(u32)`입니다.** `Value(bool)`이 아닌 이유는 Go 쪽입니다:
플래그는 native가 읽는 동안 다른 goroutine이 씁니다. Go의 `sync/atomic`은 32비트에서
시작하므로 1바이트를 원자적으로 쓸 방법이 없습니다. `extern struct { raw: u32 }`와 Go의
`uint32`는 지원하는 모든 타깃에서 같은 4바이트라, 어느 쪽도 레이아웃을 짐작하지 않습니다.
C 시그니처는 `const uint32_t *`입니다.

**생성되는 Go.** 호출마다 워드를 하나 만들고, `ctx.Done()`을 기다리는 goroutine이 그것을
`atomic.StoreUint32`로 세웁니다. goroutine은 호출이 끝나면 `defer close`로 정리되고,
`context.Background()`처럼 취소될 수 없는 ctx는 goroutine을 만들지 않습니다. 이미 취소된
ctx는 호출 전에 플래그를 세우므로 native가 첫 폴링 지점에서 곧장 멈춥니다. 주소는 호출
동안만 유효하며, cgo는 C에 넘긴 Go 포인터를 호출 동안 고정해 주고 purego 백엔드는
`runtime.Pinner`로 직접 고정합니다.

**error 매핑.** 대상 함수의 error set에 `Canceled`가 있어야 합니다(`ZIGO026`). native가
`error.Canceled`를 돌려주고 `ctx.Err() != nil`이면 공개 함수는 `ctx.Err()`를 반환합니다 —
`context.Canceled` 또는 `context.DeadlineExceeded`, 호출자의 ctx가 말하는 것 그대로입니다.
ctx가 멀쩡한데 native가 `Canceled`를 돌려줬다면 그것은 라이브러리의 error이므로 `ErrCanceled`가
그대로 나옵니다.

**검증(`ZIGO026`).** `.cancel`이 없는 파라미터를 가리키거나, 그 파라미터 타입이
`*const std.atomic.Value(u32)`가 아니거나, error set에 `Canceled`가 없거나, 반대로 플래그
파라미터가 있는데 `.cancel`이 그것을 가리키지 않으면 거부합니다.

C ABI는 `.cancel`이 붙은 함수에만 파라미터가 하나 늘어나므로, 붙지 않은 함수의 생성물은
바이트 그대로입니다. `abi-diff`는 `.cancel`이 붙거나 떨어지는 것을 breaking으로 봅니다 —
Go 시그니처의 `ctx`가 생기거나 사라지기 때문입니다.

### 값으로 반환하는 `init`

`pub fn init(gpa: Allocator, options: Options) !Terminal`처럼 값을 반환하는 생성자는 C로
표현할 수 없습니다. `.allocator`가 설정되어 있고 반환 타입이 `.repr = .@"opaque"`로 등록된
struct라면, zigo가 그 값을 상자에 담습니다: shim이 `alloc.create(T)`로 저장 공간을 만들고
`T.init(...)`의 결과를 거기에 넣어 포인터를 돌려주며, 짝이 되는 `deinit` 래퍼가 Zig
`deinit`을 부른 뒤 `alloc.destroy`까지 합니다. Go에서는 다른 생성자와 똑같이
`NewTerminal(...) (*Terminal, error)`와 `Close()`입니다.

상자에 담는 데 필요한 할당은 zigo 자신의 것이므로, 실패는 Zig 함수가 선언하지 않은 error를
지어내는 대신 panic으로 보고합니다 — 생성자는 언제나 `error`를 반환하므로 Go에는
`*NativePanicError`로 도착합니다.

`.allocator`가 없으면 이 변환은 일어나지 않고, 반환 struct는 지금까지처럼 값 struct로
판정되어 그 자리에서 거부됩니다. 저장 공간의 수명을 정하는 것은 바인딩 작성자의 몫입니다.

### Enum 이름 지정

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

## Opaque handle

일반 Zig struct나 상태를 가진 객체는 pointer handle로 등록합니다.

```zig
.types = .{
    .{ .type = mylib.Context, .repr = .@"opaque" },
},
```

caller-owned pointer를 반환하는 생성 함수와 대응 deinitializer가 있으면 공개 Go API에
constructor와 멱등 `Close() error`가 생성됩니다. 반환 error는 항상 nil이며 handle이
`io.Closer`를 만족시키기 위한 것입니다. 모든 receiver와 handle 인자는 native 호출 전에
nil·closed 상태를 검사합니다. 검사 결과는 항상 반환값으로 전달되며, 오류 반환 자리가
없던 메서드에는 `error` 결과가 추가됩니다.

`init`/`create`/`new`/`open` 이름을 쓰지 않는 factory도 `.returns = .caller`를 붙이면
같은 owned handle을 돌려줍니다. 이름이 아니라 ownership metadata가 기준이므로,
`clone`이나 `openChild` 같은 메서드도 `newX` helper를 거쳐 cleanup과 retained callback
등록을 그대로 받습니다. 다만 이것은 **그 타입에 이미 짝지어진 생성자와 소멸자가 있을 때**의
이야기입니다(없으면 `ZIGO015`). 짝 자체를 만드는 것은 아래의 `.constructs`/`.destroys`입니다.

```zig
.{
    .path = "EventQueue.clone",
    .params = .{ "observer", "userdata" },
    .param_meta = .{ .observer = .{ .retention = .retained } },
    .returns = .caller,
},
```

### 다른 handle의 메서드인 생성자

생성 함수가 새 타입 안에 있을 필요는 없습니다. 주입 파라미터를 건너뛴 첫 handle 파라미터는
평소처럼 receiver가 되고, `.constructs`는 반환값을 어느 타입의 생성자로 소유할지 정합니다.

```zig
pub fn newStream(gpa: std.mem.Allocator, terminal: *Terminal) !*Stream { ... }

.{ .path = "Terminal.newStream", .constructs = "Stream" },
.{ .path = "root.freeStream", .destroys = "Stream" },
```

Go에는 `func (t *Terminal) NewStream() (*Stream, error)`가 생깁니다. 호출 중에는 `Terminal`을
다른 메서드와 똑같이 acquire/release하고 native panic이면 그 receiver를 poison합니다. 반환된
`Stream`은 별개의 caller-owned handle이며 cleanup과 멱등 `Close()`를 등록하고 `freeStream`으로
해제됩니다. `semantic.json`은 두 관계를 섞지 않고 `receiver: "Terminal"`,
`go_owner: "Stream"`으로 기록합니다.

### 타입 밖에 선언된 생성자와 소멸자

이름 규칙과 `.returns = .caller`는 모두 **타입 안에 선언된** 짝을 전제합니다. 남의
라이브러리처럼 선언을 더할 수 없는 코드에서는 생성자와 소멸자가 타입 옆의 자유 함수로
있기 마련이고, 그때는 어느 타입의 짝인지를 직접 적습니다.

```zig
// mylib: 타입 안에는 아무것도 없고, 옆에 free 함수만 있는 형태
pub const Ticker = struct { interval: u32 };
pub fn newTicker(interval: u32) !*Ticker { ... }
pub fn freeTicker(ticker: *Ticker) void { ... }

// bindings.zig
.{ .path = "root.newTicker", .params = .{"interval"}, .constructs = "Ticker" },
.{ .path = "root.freeTicker", .destroys = "Ticker" },
```

Go에는 `NewTicker(interval uint32) (*Ticker, error)`와 `(*Ticker).Close()`가 생기고,
shim은 선언이 있는 자리 그대로 `target.newTicker(...)`를 부릅니다. 즉 Go에서의 소속과
Zig에서의 호출 경로는 서로 다른 축이며, `semantic.json`은 전자를 `go_owner`, 후자를
`zig_path`로 적습니다(둘 다 기본값과 다를 때만 나타납니다).

- `.constructs`와 `.destroys`는 `.types`에 등록된 opaque 타입 이름을 받습니다.
- `.constructs`를 붙인 함수는 그 타입의 pointer(또는 `!*T`)를 반환해야 하고,
  `.destroys`를 붙인 함수는 그 타입의 pointer를 첫 파라미터로 받고 아무것도 반환하지
  않아야 합니다. 주입 파라미터(`std.mem.Allocator`, `std.Io`)는 세지 않으므로
  `fn freeTerminal(gpa: Allocator, self: *Terminal) void`도 됩니다. 이는 메서드 판정
  일반에 적용되는 규칙입니다: 주입 파라미터를 건너뛴 첫 파라미터가 handle이면 receiver이고,
  shim은 `self`를 Zig가 선언한 자리에 넣어 부릅니다.
- 한 타입에 대해 둘 다 있어야 짝이 됩니다. 한쪽만 있거나, 같은 타입에 둘이 겹치거나,
  시그니처가 위 조건에 맞지 않으면 `ZIGO028`입니다.
- 메타를 적지 않은 함수에는 `init`/`create`/`new`/`open` + `deinit`/`destroy`/`close`
  이름 규칙이 그대로 fallback으로 남습니다. 메타가 있으면 이름은 보지 않습니다.

`.allocator`가 설정되어 있으면 값으로 반환하는 생성자를 상자에 담는 규칙도 `.constructs`를
따릅니다 — 이름이 `init`이 아니어도 됩니다.

감쌀 handle이 없는 `.returns = .caller`는 `ZIGO015`로 거부됩니다(slice 반환은 아래의
`ZIGO016` 규칙을 따릅니다). 반환 타입이 opaque
pointer가 아니거나, 그 타입에 constructor와 deinitializer가 등록되어 있지 않은
경우입니다.

## 호출자 소유 slice 반환

slice 반환은 `.returns = .caller`로 소유권을 넘길 수 있습니다. 이때는 감쌀 handle 대신
버퍼를 되돌려줄 함수가 필요하므로 `.release`로 그 함수의 경로를 함께 지정합니다. release
함수는 반환된 slice와 같은 원소 타입의 slice 하나만 받고 아무것도 반환하지 않아야 합니다.

```zig
pub fn extractSamples(self: *EventQueue) []f32 { /* 새 버퍼를 할당해 반환 */ }
pub fn freeSamples(_: *EventQueue, samples: []f32) void { /* 버퍼 해제 */ }

// bindings.zig
.{
    .path = "EventQueue.extractSamples",
    .returns = .caller,
    .release = "EventQueue.freeSamples",
},
.{ .path = "EventQueue.freeSamples", .params = .{"samples"} },
```

생성된 raw 계층은 native가 채운 `ptr, len`을 먼저 Go slice로 복사한 뒤 곧바로 release
심볼을 같은 `ptr, len`으로 호출합니다. 따라서 반환된 slice는 항상 Go 메모리이고, 호출자가
따로 해제할 것이 없습니다. release 함수는 공개 Go API에 나타나지 않습니다. 이미 복사된
Go slice를 다시 넘기는 실수를 막기 위해서입니다.

`![]T` 반환에도 같은 조합을 쓸 수 있습니다. 이때 복사와 release는 모두 성공했을 때에만
일어납니다. 오류 코드가 돌아오면 생성된 코드는 out 파라미터를 읽지 않고 release도 부르지
않은 채 `nil`과 오류를 돌려주므로, 아무것도 넘겨받지 않은 실패 경로에서 존재하지 않는
버퍼를 해제하는 일이 없습니다.

```zig
pub fn extractSamplesChecked(self: *EventQueue) ProcessError![]f32 { /* 실패 또는 새 버퍼 */ }

// bindings.zig
.{
    .path = "EventQueue.extractSamplesChecked",
    .returns = .caller,
    .release = "EventQueue.freeSamples",
},
```

release 함수가 allocator를 받아도 됩니다. `fn freeSamples(gpa: Allocator, samples: []f32) void`는
주입 파라미터를 빼고 slice 하나만 받는 함수로 판정되며, shim이 호출할 때 바인딩이 정한
allocator를 채웁니다.

`.release`가 없거나, 이름이 가리키는 함수가 없거나, 그 함수의 매개변수가 반환 slice와
맞지 않으면 `ZIGO016`으로 거부됩니다. `![]T`는 payload slice의 원소 타입으로 비교합니다.
slice가 아닌 반환에 `.release`를 붙여도 같은 코드입니다. abi-check는 release 함수가 바뀌면
breaking으로 봅니다.

`?*T`/`?*const T` 매개변수는 nil을 받을 수 있는 handle 인자가 됩니다. Go에서 nil을
넘기면 native 쪽에는 NULL이 전달되고 `*HandleError`는 발생하지 않습니다. 다만 optional은
"인자가 없어도 된다"는 뜻이지 "닫힌 handle을 넘겨도 된다"는 뜻은 아니므로, nil이 아닌 채
이미 닫힌 handle은 여전히 `*HandleError`입니다.

### optional

`?T`는 매개변수, 반환값, error union payload 이 세 자리에서만 쓸 수 있습니다. `T`로는
bool, 정수(승격 대상인 좁은 정수 포함), 부동소수, 등록 enum, `extern struct`, 그리고
선언된 opaque type의 pointer를 지원합니다.

| Zig | C | Go |
| --- | --- | --- |
| 매개변수 `?T` (scalar·bool·enum) | `const T *x` (NULL = 부재) | `*T` (nil = 부재) |
| 매개변수 `?ExternStruct` | `const T *x` (NULL = 부재) | `*T` (nil = 부재) |
| 매개변수 `?*Handle` | `T *x` | `*Handle` |
| 반환 `?T` | `bool` 반환 + `T *out_result` | `(T, bool)` |
| 반환 `E!?T` | `int32_t` 상태 + `bool *out_result_has` + `T *out_result` | `(T, bool, error)` |
| 매개변수 `?[]T` | `const T *x_ptr, size_t x_len` (`x_ptr == NULL` = 부재) | `*[]T` |
| 매개변수 `?[]const u8`(utf8)·`?[:0]const u8` | 같음 / `const char *x` | `*string` |
| 반환 `?[]T` | `T **out_result_ptr, size_t *out_result_len` (NULL = 부재) | `([]T, bool)` |
| 반환 `?[]const u8`(utf8) | 같음 | `(string, bool)` |

```zig
pub fn shiftPoint(origin: ?Point, delta: i16) ?Point { /* ... */ }
```

```go
origin := Point{X: 1, Y: 2}
shifted, ok := ShiftPoint(&origin, 2) // ok == true
_, ok = ShiftPoint(nil, 2)            // ok == false
```

슬라이스·문자열 optional은 presence 플래그를 따로 두지 않습니다. 슬라이스가 이미 포인터를
갖고 있으므로 그 포인터가 NULL인 것이 부재이고, 길이 0인 **존재하는** 슬라이스와 구별됩니다.
Go에서 `[]T`나 `string`이 아니라 `*[]T`·`*string`인 이유도 같습니다 — nil 슬라이스와 빈
슬라이스는 Go에서 이 구별을 표현하지 못합니다. 반환 `?[]T`는 기존 슬라이스 반환의 소유권
규칙(`.release` 포함)을 그대로 따르고 presence만 더합니다.

부재와 "값이 0인 present"는 서로 다릅니다. 값 자체가 아니라 presence 플래그가 그것을
가리므로, `DoubleWidth(&zero)`는 `0, true`를, `DoubleWidth(nil)`은 `_, false`를
돌려줍니다. error union과 결합할 때도 마찬가지로 error·부재·값이 각각 구별됩니다.

scalar optional을 Go에서 `*T`로 적는 것은 의도한 선택입니다. 제네릭 `Optional[T]` 래퍼를
두는 대신 언어가 이미 가진 nil 포인터를 그대로 씁니다.

`abi-check`는 `T`와 `?T` 사이의 변경을 breaking으로 봅니다. C 시그니처가 통째로 달라지기
때문입니다.

`extern struct`의 field, callback signature, slice 원소(`[]?T`), optional의
optional(`??T`), `.out` 슬라이스 매개변수(버퍼는 호출자가 잡습니다), 슬라이스의
슬라이스(`?[][]const u8`), `extern struct` 슬라이스(`?[]Point`)에는 presence를 실을 자리가
없어 `ZIGO019`(구조체가 걸린 경우 `ZIGO013`)로 거부됩니다. reflection이
표현할 수 없는 child(slice, tagged union 등)는 그보다 앞선 컴파일 오류입니다.

retained callback이나 pointer는 소유 객체의 `Close`까지 유효해야 합니다.

생성된 handle은 모두 같은 수명주기를 씁니다. 종류에 따라 달라지지 않습니다.

- 모든 메서드와 tagged-union projection(`Tag`/`As*`/`Snapshot`/`Variant`), borrowed
  `Ref`의 모든 호출은 native 호출 전에 handle을 **획득**하고(`zigoAcquire`) 돌아온 뒤
  놓습니다(`zigoRelease`). 획득은 handle의 `sync.Mutex` 아래에서 진행 중 호출 수를
  하나 늘리는 것뿐이고, 그 잠금은 native 호출 동안 잡혀 있지 않습니다. `Ref`는 부모
  사슬을 따라 부모를 획득합니다. 이미 닫힌 handle을 쓰는 호출은 use-after-free 대신
  `*HandleError`를 돌려받습니다.
- `Close`는 기다리지 않습니다. handle을 닫힘으로 표시하고, 그 순간 native 안에 있는
  호출이 없으면 바로 해제하며, 있으면 그 호출들 중 마지막으로 돌아오는 것이 해제합니다.
  `Close` 이후의 호출은 진행 중인 호출 뒤에서 기다리지 않고 즉시 `*HandleError`를
  받습니다. 그래서 어느 goroutine의 `Close`도 다른 goroutine의 호출을 막지 못합니다.
  긴 native 호출이 handle을 쓰는 동안 다른 스레드가 `cancel` 같은 메서드를 부르는 타입에
  특히 중요합니다. 동시에 여러 번 불러도 해제는 한 번만 일어납니다.
- native 호출이 Zig panic으로 끝나면(`*NativePanicError`) 그 호출이 닿은 모든 handle,
  즉 receiver와 handle 인자, projection의 소유자가 **poison** 됩니다. panic은 `longjmp`로
  native 프레임을 건너뛰어 그 안의 `defer`/`errdefer`가 실행되지 않았으므로 handle 뒤의
  상태는 알 수 없습니다. 이후 그 handle의 모든 호출은 처음 panic한 작업과 메시지를 담은
  `*NativePanicError`를 돌려주고(`errors.Is(err, ErrNativePanic)`), `Close`와 cleanup
  안전망은 native deinit을 부르지 않고 객체를 **누수**시킵니다. 반쯤 바뀐 상태를
  해제하다 fault를 내는 것보다 누수가 낫기 때문입니다. retained callback 등록은 그래도
  해제됩니다.
- 생성자가 만든 handle은 만들어질 때 `runtime.AddCleanup`을 등록합니다. `Close`를 잊고
  handle을 버려도 GC가 회수하는 시점에 native 메모리와 retained callback 등록이 함께
  풀립니다. `Close`가 먼저 실행되면 `cleanup.Stop()`으로 이 안전망을 떼어냅니다.
- 콜백을 받는 생성자를 가진 타입만 `callbackHandles`를 들고 다닙니다.

안전망은 실행 시점을 보장하지 않으므로 명시적 `Close`를 대체하지 않습니다. 획득은
receiver뿐 아니라 handle **인자**에도 걸리므로, 인자로 넘긴 handle을 다른 goroutine이
그 사이에 닫아도 native 메모리는 호출이 돌아온 뒤에 해제됩니다. 다만 그 `Close`는 호출자
관점에서 여전히 계약 위반이고, 이후의 호출이 `*HandleError`를 받는 것으로 드러납니다.

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

### 얼마나 채워졌는가: `written`

`.direction = .out`인 slice는 기본값 `.written = .all`로, 호출이 끝나면 버퍼 전체가
채워진 것으로 봅니다. `.written = .@"return"`을 붙이면 함수가 반환한 개수만큼만
채워진 것으로 보고, **그 뒤의 원소는 호출 전 값 그대로**입니다 — `io.Reader`와 같은
모양입니다. 오류로 끝난 호출은 0을 보고하므로 버퍼는 전혀 건드려지지 않습니다.

`.@"return"`은 반환 payload가 `usize`(또는 `!usize`)일 때만 쓸 수 있고, `.out`이 아닌
파라미터에 붙이면 `ZIGO017`로 거부됩니다.

`written`은 C 시그니처의 일부입니다. `.all`인 out slice는 `{name}_written`
(`size_t *`) 출력 파라미터를 하나 더 받지만, `.@"return"`은 개수를 함수의 반환값으로
알리므로 그 파라미터가 없습니다. 따라서 `.all`과 `.@"return"` 사이를 오가는 변경은
어느 방향이든 breaking이고, `abi-check`는 이를
`parameter written hint changed (C signature)`로 보고합니다.

### 큰 결과는 out 파라미터로

slice를 반환하면 호출마다 Go 쪽 할당과 복사가 한 번씩 일어납니다. 결과가 크거나 호출이
잦다면 호출자가 버퍼를 재사용하는 `...Into(dst)` 모양이 낫습니다.

```zig
pub fn extractSamplesInto(self: *Queue, dst: []f32) usize {
    const wanted = self.items.len + 1;
    if (dst.len < wanted) return 0;
    // ... dst[0..wanted] 를 채운다
    return wanted;
}

// bindings.zig
.{
    .path = "Queue.extractSamplesInto",
    .params = .{"dst"},
    .param_meta = .{ .dst = .{ .direction = .out, .written = .@"return" } },
},
```

```go
buf := make([]float32, 1024) // 한 번 할당해 계속 재사용
n, err := queue.ExtractSamplesInto(buf)
// buf[:n] 이 이번 호출의 결과, buf[n:] 는 그대로
```

## Tagged union projection

기본 표현은 union을 pointer handle로 유지하고 variant별 accessor를 생성합니다.

```zig
.types = .{
    .{ .type = mylib.Value, .repr = .tagged_union },
},
```

생성되는 주요 API는 다음과 같습니다.

- `ValueTag`, `Tag() (ValueTag, error)`, `MustTag()`
- payload variant별 `As<Variant>() (payload, bool, error)`
- payload variant별 `MustAs<Variant>() (payload, bool)`

active tag가 다르면 accessor는 `(zero, false, nil)`을 반환하고 payload를 읽지
않습니다. 기본 이름은 handle, native panic과 예기치 않은 status를 error로 반환합니다.
`Must*` 변형은 같은 typed error로 panic합니다.

지원 payload는 `void`, bool, 정수, float, enum, 등록 handle pointer, 숫자 slice입니다.
숫자 slice는 호출마다 Go memory로 복사하고, handle payload는 union wrapper에 수명이 묶인
borrowed `*TRef`입니다. union 자체를 함수 값으로 직접 전달하면 `ZIGO006`이며 pointer로
노출해야 합니다.

기존 순서·tag·payload를 보존한 끝부분 variant 추가는 compatible append입니다. 삭제,
재정렬, 이름·tag·payload 변경은 breaking입니다.

### Variant 타입과 type switch

같은 union에 sealed interface 표현도 함께 생성됩니다. `Tag()` 뒤에 맞는 `As*`를
찾아 부르는 대신 type switch 하나로 읽습니다.

- sealed interface `ValueVariant`
- variant별 concrete type `Value<Variant>`. payload는 exported field `Value`이고,
  payload가 없는 variant는 빈 struct입니다.
- `Variant() (ValueVariant, error)`와 `MustVariant()`

```go
switch active := value.MustVariant().(type) {
case ValueInteger:
    fmt.Println(active.Value)
case ValueChild:
    // borrowed *ChildRef. receiver가 열려 있는 동안만 유효합니다.
    use(active.Value)
case ValueNone:
    fmt.Println("none")
}
```

읽기 전용 표현이며 variant type으로 union을 만들거나 설정할 수는 없습니다. payload
사본과 수명 규칙은 `As*`와 같습니다. 숫자 slice는 호출마다 복사되고, handle payload는
receiver에 수명이 묶인 borrowed `*TRef`입니다. native 호출 횟수는 tag 한 번과 활성
variant의 projection 한 번이며, variant 수만큼 probe하지 않습니다.

variant type 이름이 이미 생성된 다른 이름과 겹치면 `Variant` 접미사, 그다음 숫자
접미사로 결정적으로 회피합니다.

## Tagged union snapshot

작고 모양이 고정된 scalar union을 자주 읽는다면 snapshot을 추가할 수 있습니다.

```zig
.types = .{
    .{ .type = mylib.Signal, .repr = .tagged_union, .access = .snapshot },
},
```

`Snapshot() (SignalSnapshot, error)`와 `MustSnapshot()`이 tag와 payload를 native 호출 한 번으로
가져옵니다. 기존 projection API도 그대로 남습니다.

```go
snapshot := signal.MustSnapshot()
if ticks, ok := snapshot.Ticks(); ok {
    fmt.Println(snapshot.Tag(), ticks)
}
```

snapshot을 쓰는 union은 `Variant()`도 이 한 번의 호출로 만들어집니다. tag를 따로
읽지 않습니다.

모든 payload가 `void`, bool, 정수/부동소수 scalar 또는 등록 enum이어야 합니다. 중첩
aggregate, slice, handle, optional, error union, callback은 `ZIGO011`로 거부됩니다. `tag`라는
variant 이름도 snapshot의 discriminant field와 충돌하므로 사용할 수 없습니다.

snapshot은 zigo 소유 `extern struct`의 전체 크기를 ABI로 고정합니다. variant 추가도 breaking
change입니다. variant가 늘 수 있으면 projection을, 모양이 고정되고 FFI 왕복을 줄여야 하면
snapshot을 선택하세요.

## 생성된 Go error 판별

분류에는 내보낸 sentinel과 `errors.Is`를 사용하고, 세부 정보가 필요할 때만 `errors.As`를
사용합니다. 모든 생성 error type은 정확히 하나의 sentinel로 unwrap됩니다.

| `errors.Is` 대상 | 뜻 | 세부 타입 |
|---|---|---|
| `ErrInvalidHandle` | nil·closed·부모가 닫힌 handle | `*HandleError` |
| `ErrNativePanic` | Zig panic | `*NativePanicError` |
| `ErrNativeStatus` | 알려지지 않은 native status | `*StatusError` |
| `ErrLibraryLoad` | purego library·symbol load 실패 | `*LibraryError` |
| `ErrCallbackPanic` | Go 콜백 안에서 발생한 panic (반환이 아니라 **rethrow**) | `*CallbackPanicError` |
| `ErrCallbackFailed` | `.go_error` 콜백이 돌려준 error | `*CallbackError` |
| `Err<ZigError>` | Zig error set 값. 반환된 값의 `Operation`이 어느 호출에서 났는지 말한다 | `*Error` |

```go
switch {
case errors.Is(err, ErrInvalidHandle):
case errors.Is(err, ErrNativePanic):
case errors.Is(err, ErrOutOfMemory):
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
frame을 풀 수 없기 때문입니다. native 쪽은 부호 있는 32비트 결과에서 `-3`을 받아 스스로
정리하고 반환할 수 있고, 그 호출이 돌아온 직후 생성된 함수가 **같은 goroutine에서 panic을
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
적용됩니다. native 코드가 `-3`을 자기 error로 바꿔 반환하더라도 Go 호출자는 그 error가
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

## Doc 주석

Zig 쪽 doc은 그대로 생성된 Go doc이 됩니다. 본문을 다시 쓰지는 않고 형식만 맞춥니다.

수집 순서는 다음과 같습니다.

1. 선언 바로 앞의 `///` 블록.
2. `///`가 없으면, 선언 바로 위에 빈 줄 없이 붙은 평범한 `//` 줄들. `///`, `////`, `//!`로
   시작하는 줄은 여기에 포함되지 않습니다.
3. 자기 doc이 없고 앞 선언과 빈 줄 없이 이어지는 선언은 그 묶음이 시작할 때의 doc을
   물려받습니다. 빈 줄 하나가 묶음을 끊습니다.

```zig
// The selection flag bits shared by the setters below.
pub fn select(self: *Flags) void { ... }
pub fn selectSilent(self: *Flags) void { ... }  // 위 doc을 공유합니다

pub fn detached(self: *Flags) void { ... }      // 빈 줄이 묶음을 끊습니다
```

출력은 Go 관례대로 항상 식별자로 시작합니다. 본문이 선언 이름으로 시작하거나 소문자
동사로 시작할 때만 한 줄로 이어 붙이고, 그 밖의 대문자로 시작하는 문장은 자기 줄을
가집니다.

```go
// Len reports how many events are queued.

// SelectionSilent
// The selection flag bits shared by the setters below.
```

doc이 없는 함수는 `// Name calls the Zig function Owner.name.` 한 문장을 받습니다.

패키지 doc은 공개 패키지마다 정확히 한 파일에 생성됩니다. 본문은 `go_package_doc` 빌드
옵션, `bindings.zig` 최상위의 `//!` 블록, 라이브러리 루트 모듈(`source_root`, 기본값은
`bindings.zig` 옆의 `root.zig`) 최상위의 `//!` 블록, 그리고 기본 문장
`// Package {name} provides Go bindings generated by zigo.` 순으로 결정됩니다. 본문이
`Package {name}`으로 시작하면 그대로 쓰고, 소문자 동사로 시작하면 `// Package {name}` 뒤에
이어 붙입니다. 그 밖의 본문(대문자로 시작하는 문장 등)은 기본 문장 뒤에 빈 `//` 줄을 두고
별도 문단으로 이어집니다. godoc은 연속된 주석 줄을 한 문단으로 합치므로, 이름만 적은 줄 뒤에
본문을 붙이면 `Package scalar Scalar arithmetic…`처럼 읽히기 때문입니다. raw 패키지는
지원 API가 아니라는 사실을 밝히는 자체 doc을 받습니다.

`bindings.zig`가 루트 모듈보다 먼저인 이유는, 남이 쓴 라이브러리를 바인딩할 때 루트 모듈의
`//!`가 Zig 사용자를 향해 쓰인 글이기 때문입니다. `bindings.zig`는 바인딩 작성자가 소유한
유일한 파일이므로, 그 머리 주석을 Go 독자가 읽을 문장으로 쓰는 것이 작성자의 몫입니다.
예제 `03-opaque`가 이 자리를 보여 주고, `01-scalar`는 루트 모듈 `//!`가 쓰이는 경우를,
`07-event-queue`는 `go_package_doc` 옵션을 보여 줍니다.
