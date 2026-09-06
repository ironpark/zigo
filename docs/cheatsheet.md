# zigo 치트시트

한 장에 모은 참조표입니다. 처음이라면 [시작 가이드](getting-started.md)를 먼저 읽고, 각 항목의
자세한 규칙은 표 옆의 링크에서 확인하세요. 코드 조각은 기존 `zigo.define`이나 `build.zig`에
넣는 부분 선언입니다.

## 최소 구성

```zig
// build.zig
const bindings = zigo.addGoBindings(b, .{
    .name = "mylib",
    .module = mylib,                       // *std.Build.Module
    .bindings = b.path("src/bindings.zig"),
    .source_root = b.path("src/root.zig"), // 이름·주석 보강 (선택)
    .go_dir = b.path("go"),
    .go_module = "example.com/mylib/go",
    .target = target,
    .optimize = optimize,
});
_ = bindings.addStandardSteps(b, .{});
```

```zig
// src/bindings.zig
const zigo = @import("zigo");
const mylib = @import("mylib");

pub const bindings = zigo.define(.{
    .root = mylib,
    .functions = .{
        .{ .path = "root.add" },
    },
});
```

```bash
zig build go          # 생성 + 네이티브 라이브러리 설치
cd go && go test ./...
```

## 빌드 스텝

| 스텝 | 역할 |
|---|---|
| `go` | Go 생성물 갱신, 라이브러리·헤더 설치 |
| `go-check` | 커밋된 생성물이 최신인지 검사 |
| `go-lib` | 라이브러리·헤더만 설치 |
| `go-verify` | `go-check` + `go-lib` + `go-doctor` |
| `go-doctor` | 툴체인·링크 환경 진단 |
| `go-report` | 바인딩 결정(이름·소유권·로더 정책) 설명 |
| `go-coverage` | 공개 API 중 바인딩된 비율 |
| `abi-check` | `abi_base` ref의 `semantic.json`과 호환성 비교 |

`addStandardSteps(b, .{ .name_prefix = "purego", .install_library_by_default = false })`처럼
두 번째 바인딩에 접두사를 주면 `purego-go`, `purego-go-report`가 되고, 기본 `zig build`의
라이브러리 설치를 끌 수 있습니다. 전체 옵션은 [빌드 설정](configuration.md).

## `addGoBindings` 옵션 요약

| 옵션 | 기본값 | 용도 |
|---|---|---|
| `link` | `.cgo_static` | `.cgo_static` / `.cgo_dynamic` / `.purego` |
| `prefix` | `"zg"` | C 심볼 접두사. 바인딩이 여럿이면 다르게 |
| `go_package`, `go_package_path` | `name` 기반 | 공개 패키지 이름·경로 |
| `raw_package` | `"internal/raw"` | raw 계층 경로 |
| `go_package_doc` | 모듈 `//!` 주석 | 공개 패키지 GoDoc |
| `go_must_variants` | `false` | `Must*` 동반 API 생성 |
| `gofmt` | `PATH`의 `gofmt` | 생성물 포맷 도구 경로 |
| `targets` | `&.{}` | 추가 타깃용 네이티브 라이브러리 (`library_dir/<goos>_<goarch>/`) |
| `cgo_flags` | 모듈에서 계산 | `.cflags`, `.ldflags`(교체), `.extra_ldflags`(보강), `.target_ldflags`(GOOS별) |
| `abi_base` | `null` | `abi-check` 기준 Git ref (예: `"HEAD"`) |
| `library_loading` | 명시적 로드 | purego 검색 경로·환경 변수·`.explicit`/`.automatic` |
| `install` | `.lib` / `.header` | `.library_dir`, `.header_dir`, `.library_name`(`<name>_zigo`), `.header_name`(`zigo_<name>.h`) |
| `coverage_json` | `null` | 커버리지 보고서 경로 |

## `zigo.define` 최상위 키

| 키 | 용도 |
|---|---|
| `root` | 경로의 기준 module. 필수 |
| `types` | opaque·value·enum·tagged union·materialized·callback 등록 |
| `functions` | 노출 함수와 메타데이터 (`discover`와 함께 쓰면 메타데이터만 붙임) |
| `discover` | `.public` / `.recursive` 자동 발견 |
| `exclude` | 자동 발견에서 뺄 경로 |
| `packages` | 공개 Go 하위 패키지 분할 ([함수와 패키지](bindings-functions.md#공개-go-하위-패키지)) |
| `interfaces` | 여러 opaque 타입을 묶는 Go 인터페이스 ([객체 수명](bindings-handles.md#인터페이스)) |
| `allocator` | `.c_allocator` / `.page_allocator` / `.smp_allocator` / `"gpa"` 선언 경로. `std.mem.Allocator` 주입·narrow slice·materialized에 필요 |
| `io` | `std.Io`를 주입할 선언 경로 |
| `codepoints` | `.infer_u21`이면 모든 `u21`이 `rune` ([코드포인트](bindings-types.md#코드포인트)) |

```zig
.interfaces = .{
    .{ .name = "Batch", .methods = .{"len"}, .types = .{ mylib.IntBatch, mylib.FloatBatch },
       .closer = true, .doc = "Batch is any staged batch." },
},
.packages = .{
    .{ .path = "types", .name = "types", .doc = "Package types ...",
       .types = .{ "Ticker", "Key*" }, .namespaces = .{"text.*"}, .functions = .{"root.liveTickers"},
       .closure = true },   // 도달 가능한 등록 타입을 같은 패키지로
},
```

## `types` 항목

공통 필드: `type`(필수), `repr`(필수), `name`(Go 이름 override; callback·comptime enum은 필수), `doc`.

| `repr` | Zig 타입 | 추가 필드 | 문서 |
|---|---|---|---|
| `.@"opaque"` | 상태를 가진 struct | `fields`(getter/setter 접근자) | [객체 수명](bindings-handles.md) |
| `.value` | `extern struct`, 정수 backing `packed struct` | `go`(어댑터), `field_meta` | [값 타입](bindings-types.md#extern-struct-값) |
| `.enumeration` | enum | `exhaustive = false`(열린 enum), `text = true`, `go`, `covers`(Go enum이 대신하는 Zig 메서드 경로) | [값 타입](bindings-types.md#enum-이름-지정) |
| `.tagged_union` | `union(enum)` | `access = .snapshot`, `omit_variants` | [Tagged union](bindings-unions.md) |
| `.materialized` | pointer·string·slice 결과 트리 | `field_meta`(`[]const u8` 필드를 `[]byte`로) | [값 타입](bindings-types.md#materialized-결과-트리) |
| `.callback` | `*const fn (...) callconv(.c)` | `on_callback_failure`, `param_semantics`, `semantic` | [콜백](bindings-callbacks.md) |

```zig
.types = .{
    .{ .type = mylib.Terminal, .repr = .@"opaque", .fields = .{
        .{ .path = "cols" },                                            // getter
        .{ .path = "screen.cursor.style", .name = "cursorStyle", .set = true },
    } },
    .{ .type = mylib.Point, .repr = .value, .go = .{ .type = "image.Point", .import = "image", .to_raw = "pointToRaw", .from_raw = "pointFromRaw" } },
    .{ .type = mylib.Glyph, .repr = .value, .field_meta = .{ .cp = .{ .semantic = .codepoint } } },
    .{ .type = mylib.Mode, .repr = .enumeration, .exhaustive = false, .text = true },
    .{ .type = mylib.Signal, .repr = .tagged_union, .access = .snapshot },
    .{ .name = "Observer", .type = mylib.Observer, .repr = .callback, .on_callback_failure = .{ .result = 0 } },
    .{ .name = "Visitor", .type = mylib.Visitor, .repr = .callback, .param_semantics = .{ .codepoint, .integer }, .semantic = .codepoint },
},
```

## `functions` 항목

| 필드 | 값 | 용도 |
|---|---|---|
| `path` | `"root.name"` / `"Type.name"` | 선언 경로 |
| `name` | 문자열 | 공개 Go 이름 override |
| `params` | 이름 목록 | Go가 넘기는 파라미터 이름 (receiver·주입 인자 제외) |
| `param_meta` | 파라미터별 계약 | 아래 표 |
| `receiver` | 등록 opaque 타입 이름 | 자유 함수를 메서드로 |
| `functions` + `receiver` + `strip_prefix` | 그룹 | 여러 함수에 같은 receiver·접두사 제거 |
| `constructs` / `destroys` | opaque 타입 이름 | 이름 규칙(`init`/`create`/`new`/`open`, `deinit`)이 맞지 않는 생성자·소멸자 |
| `child_of_receiver` | `true` | 생성된 handle이 receiver보다 먼저 닫혀야 함 |
| `returns` | `.caller` / `.borrowed` | 반환 pointer·slice의 소유권 |
| `release` | 함수 경로 | caller-owned 반환 버퍼의 해제 함수 |
| `semantic` | `.utf8_string` / `.c_string` / `.codepoint` / `.integer` | 반환값 의미 |
| `go` | `.{ .type, .import, .to_raw, .from_raw }` | scalar 반환값 어댑터 |
| `iterator` | `.{}` / `.{ .name = "Checked" }` | `?T`·`!?T` 메서드를 `iter.Seq`로 |
| `cancel` | `.{ .param = "cancel", .canceled = "Cancelled" }` | `context.Context` 취소 |
| `covers` | 경로 목록 | `go-coverage`에서 대신 노출한 것으로 계산 |
| `doc` | 문자열 | Go doc override |

### `param_meta`

| 키 | 값 | 적용 대상 |
|---|---|---|
| `semantic` | `.utf8_string` / `.c_string` / `.opaque_bytes` / `.codepoint` / `.integer` | `[]const u8`, `[]const []const u8`, `u21`/`u32`와 그 slice |
| `direction` | `.in` / `.out` | slice 버퍼 |
| `written` | `.all` / `.@"return"` | `.out` slice가 얼마나 채워졌는지 |
| `flatten` | 필드 이름 목록 | 설정 struct의 일부 필드만 Go 인자로 |
| `retention` | `.borrowed` / `.retained` | 콜백·atomic 포인터를 호출 뒤에도 보관하는지 |
| `go_error` | `true` | 콜백이 Go `error`를 돌려줄 수 있음 (Zig 반환 `i32`) |
| `on_callback_failure` | `.{ .result = n }` | 콜백 panic·error 시 native에 돌려줄 값 |
| `reentrancy`, `thread` | `.allowed`/`.forbidden`, `.caller`/`.any` | 콜백 계약 (doc에만 반영) |
| `buffer` | 바이트 수 | `std.Io` 스트림 staging 버퍼 |
| `go` | 어댑터 | scalar 파라미터 하나 |

```zig
.{ .path = "Document.load", .params = .{"r"}, .param_meta = .{ .r = .{ .buffer = 4096 } } },
.{ .path = "root.render", .params = .{ "text", "dst" }, .param_meta = .{
    .text = .{ .semantic = .utf8_string },
    .dst = .{ .direction = .out, .written = .@"return" },
} },
.{ .path = "Terminal.init", .params = .{"options"}, .param_meta = .{ .options = .{ .flatten = .{ "cols", "rows" } } } },
.{ .path = "root.takeCodepoints", .returns = .caller, .release = "root.freeCodepoints", .semantic = .codepoint },
.{ .path = "Context.next", .iterator = .{} },
.{ .path = "root.run", .params = .{ "limit", "callback", "userdata", "cancel" },
   .param_meta = .{ .callback = .{ .retention = .retained, .go_error = true } },
   .cancel = .{ .param = "cancel" } },
```

## Zig 타입 → Go 타입

| Zig | Go | 비고 |
|---|---|---|
| `bool`, `iN`/`uN`(8·16·32·64), `f32`/`f64` | 같은 폭 | `usize`/`isize`는 `uint`/`int` |
| `u21`, `i24` 같은 비정규 폭 | 다음 표준 폭 | 입력 범위 검사로 `error` 추가; `.codepoint`면 `rune` |
| `[]const u8` + `.utf8_string` | `string` | 복사 한 번 |
| `[:0]const u8`, `[*:0]const u8` | `string` | C 문자열 |
| `[]const u8`(힌트 없음) | `[]byte` | |
| `[]const T` (scalar·enum·extern struct) | `[]T` | 반환은 Go로 복사; castable struct는 재해석 |
| `[]const []const u8` | `[]string` | sentinel 원소 또는 `.utf8_string` |
| `?T` 파라미터 / 반환 | `*T` / `(T, bool)` | struct 필드·콜백에는 불가 |
| `E!T` | `(T, error)` | `anyerror` 불가 |
| `*Opaque` | `*Opaque` handle | `Close()`, `ErrInvalidHandle` |
| 등록 enum | `type E uint8` + 상수 + `String()` | `.text`면 `ParseE`, `MarshalText`/`UnmarshalText` |
| `extern struct` | mirror struct 또는 `.go` 어댑터 타입 | |
| `*const fn(..., userdata: usize) callconv(.c)` | `func(...)` | 마지막 `usize`가 userdata |
| `*std.Io.Writer` / `*std.Io.Reader` | `io.Writer` / `io.Reader` | |
| `*const std.atomic.Value(u32)` + `.cancel` | `context.Context` | |

전체 제약은 [지원 범위와 제한사항](limitations.md).

## 생성된 Go API 패턴

```go
h, err := NewTerminal(80, 24)         // 생성자 → *Terminal, error
defer h.Close()                        // 두 번 호출해도 안전
n, err := h.Write(data)                // 메서드: 닫힌 handle이면 ErrInvalidHandle
for v, err := range h.All() { ... }    // .iterator = .{} → All(); .name = "Checked" → Checked()
v := MustParse(s)                      // go_must_variants = true일 때
```

| `errors.Is` 대상 | 뜻 | `errors.As` 타입 |
|---|---|---|
| `ErrInvalidHandle` | nil·closed·부모가 닫힌 handle | `*HandleError` |
| `ErrOutOfRange` | 비정규 폭 정수·코드포인트 범위 밖 | `*RangeError` |
| `ErrNativePanic` | Zig panic (`Message`) | `*NativePanicError` |
| `ErrNativeStatus` | 알 수 없는 status 코드 | `*StatusError` |
| `ErrLibraryLoad` | purego 로드 실패 | `*LibraryError` |
| `ErrCallbackFailed` | `.go_error` 콜백이 돌려준 error | `*CallbackError` |
| `ErrCallbackPanic` | Go 콜백 panic — 다시 panic됨 | `*CallbackPanicError` |
| `Err<ZigError>` | Zig error set 값 | `*Error` |
| `ErrHandleInUse` | `Close` 시점에 진행 중 호출이나 열린 자식이 있음 | `*HandleInUseError` |
| `ErrNilStream`, 사용자 `io` 오류, `io.ErrShortWrite` 등 | `io.Writer`/`io.Reader` 파라미터의 실패 | `*StreamError` (`Unwrap`으로 원인) |

raw 패키지(공유 시 `support/ffi`)의 `LastErrorMessage()`는 마지막 native 오류 메시지를,
`PanicMessage(code)`는 붙잡힌 panic 메시지를 돌려주지만, 보통은 `errors.As`로 얻는
`*NativePanicError.Message`면 충분합니다. 생성 패키지의 비공개 식별자는 모두 `zigo` 접두사이므로 같은 패키지에
파일을 추가할 때 그 접두사만 피하면 됩니다([생성 패키지 확장하기](generated-code.md#생성-패키지-확장하기)).

## purego

```zig
const purego = zigo.addGoBindings(b, .{ ..., .link = .purego, .go_dir = b.path("go-purego"),
    .library_loading = .{ .search_paths = &.{"${EXECUTABLE_DIR}"}, .loader = .automatic } });
_ = purego.addStandardSteps(b, .{ .name_prefix = "purego" });
```

```bash
zig build purego-go purego-go-verify
CGO_ENABLED=0 go test ./...
ZIGO_LIBRARY_PATH=/path/libmylib_zigo.so go run .   # 또는 ZIGO_<PACKAGE>_LIBRARY_PATH
```

`.explicit` 로더는 `LoadLibrary(path)`를 공개하고, `.automatic`은 첫 호출에 후보 경로를
차례로 시도합니다. 콜백 결과는 `void`·`i32`만 가능합니다. 자세한 내용은
[공유 라이브러리와 purego](purego.md).

## 자주 만나는 진단

| 코드 | 원인 | 조치 |
|---|---|---|
| ZIGO002 / ZIGO029 | 열린 enum 미표시 / 닫힌 enum에 `.exhaustive = false` | 등록 항목의 `exhaustive` 조정 |
| ZIGO018 / ZIGO019 | 지원하지 않는 폭·타입·위치 | 표준 폭으로 바꾸거나 opaque·materialized로 |
| ZIGO024 / ZIGO036 | Go 이름 / C 심볼 충돌 | `.name`, `prefix` 조정 |
| ZIGO027 | `.params` 개수 불일치 | receiver·주입 인자 제외하고 나열 |
| ZIGO028 / ZIGO035 | 생성자·소멸자 짝 / 소유권 미지정 | `.constructs`/`.destroys`, `.returns` |
| ZIGO045 | narrow slice용 allocator 없음 | `.allocator = .c_allocator` |
| ZIGO050 / ZIGO051 / ZIGO052 / ZIGO053 | `iterator` / `text` / `go` / `codepoint` 오용 | 해당 표의 적용 대상 확인 |
| ZIGO054 | 경로 중복 또는 `functions`·`exclude` 충돌 | 경로 한 번만 |

전체 목록은 [진단 코드](diagnostics.md).

## 릴리스 전 로컬 검사

```bash
zig fmt --check build.zig src tests examples
zig build test --summary all
(cd examples/<name> && zig build go-check abi-check --summary all)   # purego면 purego-go-check도
staticcheck -checks U1000 ./...                                       # 각 Go 모듈에서
```

절차 전체는 [프로젝트 개발](development.md#릴리즈-절차).
