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
    .source_root = b.path("src/root.zig"), // 이름·주석 보강 (선택, import과 의존 module까지 스캔)
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

const api = zigo.scope(mylib);

pub const bindings = zigo.define(.{
    .root = mylib,
    .declarations = &.{api.function("add", .{})},
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
| `plugins` | `&.{}` | Go 표면을 더하는 생성기 플러그인 모듈 ([플러그인](plugins.md)) |
| `library_loading` | 명시적 로드 | purego 검색 경로·환경 변수·`.explicit`/`.automatic` |
| `install` | `.lib` / `.header` | `.library_dir`, `.header_dir`, `.library_name`(`<name>_zigo`), `.header_name`(`zigo_<name>.h`) |
| `coverage_json` | `null` | 커버리지 보고서 경로 |

## `zigo.define` 최상위 키

| 키 | 용도 |
|---|---|
| `root` | `scope`와 같은 Zig 루트 모듈 |
| `declarations` | 함수·타입·package·interface를 담는 `[]const zigo.Entry` |
| `discovery` | `.explicit` 기본값, `.{ .public = .{} }`, `.{ .recursive = .{} }` |
| `defaults` | `strings = .infer_utf8`, `codepoints = .infer_u21` 등 추론 정책 |
| `allocator` | `.c_allocator`, `.page_allocator`, `.smp_allocator`, `.{ .path = "gpa" }` |
| `io` | `std.Io`를 주입할 `.{ .path = "io" }` |
| `string_release` | owned 문자열의 기본 `FunctionRef` |

```zig
const api = zigo.scope(mylib);
const shared = zigo.package(.{
    .path = "types",
    .declarations = &.{api.value("Point", .{})},
});
const batch = zigo.interface(.{
    .name = "Batch",
    .methods = &.{"len"},
    .types = &.{ api.typeRef("IntBatch"), api.typeRef("FloatBatch") },
});
```

`shared`, `batch`를 `declarations`에 넣고 참조한 handle·메서드도 등록합니다.
[함수와 패키지](bindings-functions.md), [인터페이스](bindings-handles.md#인터페이스)를 참고하세요.

## 타입 선언

| Helper | 용도·옵션 |
|---|---|
| `api.handle("T", options)` | 객체 수명, `fields` 접근자 |
| `api.value("T", options)` | 적격한 extern/packed struct, `fields`, `go` adapter |
| `api.enumeration("T", options)` | enum, `exhaustive`, `go`, `covers` 참조 |
| `api.taggedUnion("T", options)` | tagged union, `access`, `omit` |
| `api.materialized("T", options)` | 복사할 결과 트리, `fields` |
| `api.callback("T", options)` | 콜백 alias, `params`, `returns`, `userdata`, 수명·실패 기본값 |

공통 설정은 `.named()`, `.documented()`, `.members(entries)`입니다.
아래 예제의 `api`는 대상 모듈의 scope입니다.

```zig
const mode = api.enumeration("Mode", .{ .exhaustive = false })
    .use(zigo.features.text, .{});
const terminal = api.handle("Terminal", .{
    .fields = &.{.{ .path = "cols", .set = true }},
}).members(api.in("Terminal").functions(.{ .names = &.{ "create", "deinit" } }));
```

값과 결과 트리의 자세한 지원 모양은 [타입 문서](bindings-types.md)에 있습니다.

## 함수와 파라미터

| 옵션 | 용도 |
|---|---|
| `name`, `doc` | 이름·GoDoc override |
| `role` | `.auto`, `.free`, `.{ .method = TypeRef }`, constructor, destructor |
| `params` | 필요한 원본 Zig 인덱스만 적는 sparse 목록 |
| `returns` | `lifetime`, `semantic`, `go` |
| `covers` | 대신 노출한 함수의 `FunctionRef` 목록 |

| Param 필드 | 용도 |
|---|---|
| `index` | 0부터 시작. receiver·주입 인자·userdata 포함 |
| `go_name` | 파라미터 이름 override |
| `semantic` | `.utf8_string`, `.c_string`, `.opaque_bytes`, `.codepoint`, `.integer` |
| `go` | scalar Go 타입 adapter |
| `contract` | 아래의 배타적인 계약 중 하나 |

| contract | payload |
|---|---|
| `.value` | 기본값 |
| `.buffer` | `.input`, `.{ .output = .{ .written = .result } }`, `.{ .inout = .{} }` |
| `.stream` | `.{ .buffer = 4096 }` |
| `.callback` | `retention`, `thread`, `reentrancy`, `go_error`, `on_failure`, `userdata` 원본 인덱스 |
| `.cancel` | `.{ .canceled = "Canceled" }` |
| `.flatten` | 펼칠 struct 필드 이름 목록 |

```zig
// fn load(self: *Document, reader: *std.Io.Reader) !usize
const load = api.in("Document").function("load", .{
    .params = &.{.{ .index = 1, .contract = .{ .stream = .{ .buffer = 4096 } } }},
});
const take = api.function("takeCodepoints", .{
    .returns = .{
        .semantic = .codepoint,
        .lifetime = .{ .owned = .{ .release = api.ref("freeCodepoints") } },
    },
});
const next = api.in("Context").function("next", .{}).use(zigo.features.iterator, .{});
```

`with()`는 적은 필드만 교체하며 null은 기존 값을 지웁니다. 중첩 계약은 전체 교체입니다.
선언의 `.use()`는 중복 플러그인을 거절하고 `.replacePlugin()`은 명시적으로 교체합니다.
[작성 API 마이그레이션](migration-authoring.md)에 이전 표기와의 대응표가 있습니다.

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
| 등록 enum | `type E uint8` + 상수 + `String()` | `features.text`를 쓰면 `ParseE`, `MarshalText`/`UnmarshalText` |
| `extern struct` | mirror struct 또는 `.go` 어댑터 타입 | |
| `*const fn(..., userdata: usize) callconv(.c)` | `func(...)` | 마지막 `usize`가 userdata; 다른 자리면 `.userdata`로 지정. `bool` 인자·결과 가능 |
| `*std.Io.Writer` / `*std.Io.Reader` | `io.Writer` / `io.Reader` | |
| `*const std.atomic.Value(u32)` + `.cancel` | `context.Context` | |

전체 제약은 [지원 범위와 제한사항](limitations.md).

## 생성된 Go API 패턴

```go
h, err := NewTerminal(80, 24)         // 생성자 → *Terminal, error
defer h.Close()                        // 두 번 호출해도 안전
n, err := h.Write(data)                // 메서드: 닫힌 handle이면 ErrInvalidHandle
for v, err := range h.All() { ... }    // features.iterator → All(); .name = "Checked" → Checked()
fmt.Fprintf(doc, "%d", n)              // features.implements의 .writer → Write
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
차례로 시도합니다. 콜백 결과는 `void`·`bool`·`i32`만 가능합니다(`ZIGO014`). 자세한 내용은
[공유 라이브러리와 purego](purego.md).

## 자주 만나는 진단

| 코드 | 원인 | 조치 |
|---|---|---|
| ZIGO002 / ZIGO029 | 열린 enum 미표시 / 닫힌 enum에 `.exhaustive = false` | 등록 항목의 `exhaustive` 조정 |
| ZIGO018 / ZIGO019 | 지원하지 않는 폭·타입·위치 | 표준 폭으로 바꾸거나 opaque·materialized로 |
| ZIGO024 / ZIGO036 | Go 이름 / C 심볼 충돌 | `.name`, `prefix` 조정 |
| 작성 컴파일 오류 | 인덱스·참조·중복·대상 contract 오류 | 원본 Zig 인덱스와 선언 확인 |
| ZIGO028 / ZIGO035 | 생성자·소멸자 짝 / 소유권 미지정 | `.role`, `.returns.lifetime` |
| ZIGO045 | narrow slice용 allocator 없음 | `.allocator = .c_allocator` |
| ZIGO050 / ZIGO051 / ZIGO052 / ZIGO053 | `iterator` / `text` / `go` / `codepoint` 오용 | 해당 표의 적용 대상 확인 |
| ZIGO048 | materialized 트리가 지원하지 않는 필드 모양 | 위 materialized 필드 표 확인 |
| ZIGO054 | 명시 선언과 discovery 제외 충돌 | 경로 한 번만 |
| ZIGO056 | 값 receiver(등록 enum)에 handle 전용 메타데이터 | 소유권·`iterator`·스트림은 opaque 타입에만 |
| ZIGO055 | 콜백 userdata 규약 위반(`usize` 자리 없음·자리 불일치) | callback 등록의 `.userdata`, `Param.contract.callback.userdata` 확인 |
| ZIGO057 | 콜백 시그니처에 `[]T` slice·extern struct·optional 등 | 콜백 값은 scalar·enum·packed·handle 포인터·`[*:0]const u8`·`[*]const u8`+`usize` |
| ZIGO058 | `features.implements` 메서드의 모양이 인터페이스와 다름 | receiver 있는 handle 메서드, 파라미터 하나, 결과 `void`·정수 |

전체 목록은 [진단 코드](diagnostics.md).

## 릴리스 전 로컬 검사

```bash
zig fmt --check build.zig src tests examples
zig build test --summary all
(cd examples/<name> && zig build go-check abi-check --summary all)   # purego면 purego-go-check도
staticcheck -checks U1000 ./...                                       # 각 Go 모듈에서
```

절차 전체는 [프로젝트 개발](development.md#릴리즈-절차).


작은 계약 helper: `zigo.param.output(index, .result)`, `stream(index, buffer)`,
`callback(index, options)`, `cancel(index, canceled)`, `flatten(index, fields)`.
반환은 `zigo.result.owned()`, `releasedBy(api.ref("release"))`, `borrowed()`로 만듭니다.
함수와 콜백 타입 모두 원본 Zig 인덱스를 사용합니다. 콜백 타입 실패 설정은 `on_failure`입니다.
