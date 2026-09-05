# 빌드 설정

이 문서는 `build.zig`의 `zigo.addGoBindings` 옵션을 설명합니다. 처음 설정하는 중이라면
[시작 가이드](getting-started.md)를 먼저 완료하세요. 함수와 타입을 노출하는 방법은
[`bindings.zig` 선언](bindings.md), 생성 파일과 CI 스텝은
[생성물과 CI 관리](generated-code.md)에
각각 정리되어 있습니다.

## 기본 구성

```zig
const bindings = zigo.addGoBindings(b, .{
    .name = "mylib",
    .module = mylib,
    .bindings = b.path("src/bindings.zig"),
    .source_root = b.path("src/root.zig"),
    .go_dir = b.path("go"),
    .go_module = "example.com/mylib/go",
    .target = target,
    .optimize = optimize,
});
_ = bindings.addStandardSteps(b, .{});
```

필수 옵션만 사용하면 cgo가 정적 아카이브를 링크하고, 공개 Go 패키지는 `name`에서,
raw 패키지는 `internal/raw`에서 생성됩니다. `addStandardSteps`는 기본 `install` 스텝에도
네이티브 바인딩 라이브러리를 연결하므로 plain `zig build`만 실행해도 `zig-out/lib`에
라이브러리가 설치됩니다.

## 전체 옵션

처음에는 필수 입력만 설정하세요. 패키지 배치, 링크와 검증 옵션은 필요할 때 추가합니다.

### 필수 입력

| 옵션 | 필수 | 기본값 | 설명 |
|---|---:|---|---|
| `name` | 예 | — | 라이브러리, 헤더와 기본 Go 패키지의 기준 이름 |
| `module` | 예 | — | reflection하고 링크할 `*std.Build.Module` |
| `bindings` | 예 | — | `zigo.define` 선언 파일 |
| `go_dir` | 예 | — | 생성된 Go 모듈을 둘 소스 경로 |
| `go_module` | 예 | — | 생성할 `go.mod`와 import에 사용할 모듈 경로 |
| `target` | 예 | — | 네이티브 라이브러리 타깃 |
| `optimize` | 예 | — | 네이티브 라이브러리 최적화 모드 |

### 공개 API와 패키지

| 옵션 | 필수 | 기본값 | 설명 |
|---|---:|---|---|
| `source_root` | 아니요 | 자동 탐색 | AST 파라미터 이름·GoDoc 보강에 사용할 실제 Zig root |
| `prefix` | 아니요 | `"zg"` | 생성 C 심볼 접두사. 바인딩 함수뿐 아니라 zigo 런타임 심볼(`<prefix>_panic_bridge`, `<prefix>_last_error_message`)에도 붙으므로, 한 실행 파일에 링크되는 바인딩마다 다른 값을 준다 |
| `go_package` | 아니요 | `name`의 snake_case | 공개 Go 패키지 이름 |
| `go_package_path` | 아니요 | `go_package` | `go_dir` 기준 공개 Go 패키지 경로. `"."`은 모듈 루트 |
| `go_package_doc` | 아니요 | `bindings.zig`의 `//!`, 없으면 루트 모듈(`source_root`)의 `//!` | 생성된 공개 패키지의 `// Package …` doc 본문 |
| `go_must_variants` | 아니요 | `false` | 오류를 반환하는 공개 함수·메서드에 panic 기반 `Must*` 동반 API 생성 |
| `raw_package` | 아니요 | `"internal/raw"` | `go_dir` 기준 raw Go 패키지 경로 |

### 링크·설치·검증

| 옵션 | 필수 | 기본값 | 설명 |
|---|---:|---|---|
| `link` | 아니요 | `.cgo_static` | `.cgo_static`, `.cgo_dynamic`, `.purego` 중 하나 |
| `coverage_json` | 아니요 | `null` | `go-coverage`의 JSON 보고서를 기록할 소스 경로 |
| `cgo_flags` | 아니요 | 모듈에서 계산 | 생성할 CFLAGS/LDFLAGS 덮어쓰기와 추가 LDFLAGS |
| `gofmt` | 아니요 | `PATH`의 `gofmt` | 생성 코드 포맷에 사용할 실행 파일 |
| `abi_base` | 아니요 | `null` | ABI 비교 기준 Git ref. 없으면 검사 비활성화 |
| `library_loading` | 아니요 | 명시적 로드 | purego 전용 런타임 로딩 정책 |
| `install` | 아니요 | `.lib` / `.header`, 기본 파일명 | 네이티브 라이브러리와 C 헤더의 설치 위치·이름 |

## 설치 위치

`install`은 Zig 설치 prefix 아래에서 라이브러리와 헤더가 놓일 디렉터리와 파일명을
한곳에서 정합니다. 디렉터리는 `std.Build.InstallDir`이므로 `.lib`, `.bin`, `.header`,
`.prefix`, `.{ .custom = "..." }`을 쓸 수 있고, `zig build -p <prefix>`로 전체 배치를
그대로 옮길 수 있습니다.

```zig
.install = .{
    .library_dir = .{ .custom = "dist/native/lib" },
    .header_dir = .{ .custom = "dist/native/include" },
    .library_name = "mylib_native", // lib 접두사와 확장자를 제외한 stem
    .header_name = "mylib_native.h",
},
```

| 필드 | 기본값 | 설명 |
|---|---|---|
| `library_dir` | `.lib` | 바인딩 라이브러리와 cgo 정적 링크 입력 archive의 설치 디렉터리 |
| `header_dir` | `.header` | 생성 C 헤더의 설치 디렉터리 |
| `library_name` | `<name>_zigo` | `lib` 접두사와 플랫폼 확장자를 제외한 라이브러리 stem |
| `header_name` | `zigo_<name>.h` | 설치되는 헤더 파일명 |

cgo의 `#cgo CFLAGS -I`와 `LDFLAGS -L`, 정적 archive 경로는 이 설정에서 함께
계산되며 계속 `${SRCDIR}` 기준 forward-slash 경로입니다. 모듈에 연결된 정적 라이브러리도
바인딩 archive와 같은 `library_dir`에 설치됩니다. `GoBindings.library_filename`과
`GoBindings.library_path`는 이름 변경과 디렉터리 변경이 반영된 실제 결과를 제공합니다.
`go-lib`, `go-check`, `go-coverage`, `abi-check`, 기본 `install` 스텝도 같은 배치를
사용합니다.

purego는 `header_name`을 생략하면 같은 prefix의 cgo 헤더를 덮지 않도록
`zigo_<name>_purego.h`를 사용합니다. 두 백엔드에 같은 명시적 `header_name`과
`header_dir`을 주면 빌드 그래프 생성 중 충돌을 명확히 진단합니다. custom
`library_dir`을 선택하고 `library_loading.search_paths`를 비워 두면 설치 디렉터리의
Go 패키지 기준 상대 경로가 기본 검색 경로가 됩니다. 명시적 `search_paths`가 있으면
그 목록을 그대로 사용합니다.

## 링크 방식 선택

`link`는 Go가 네이티브 라이브러리에 도달하는 방식을 하나의 값으로 고릅니다.

| 값 | Go 빌드 | 네이티브 아티팩트 | 적합한 경우 |
|---|---|---|---|
| `.cgo_static` | cgo 필요 | 정적 archive | 기본 선택, 단일 Go 실행 파일 배포 |
| `.cgo_dynamic` | cgo 필요 | 공유 라이브러리 | 네이티브 라이브러리를 별도 교체·공유 |
| `.purego` | `CGO_ENABLED=0` 가능 | 공유 라이브러리 | Go 빌드 환경에서 C 컴파일러 제거 |

purego는 정적 링크와 조합되지 않습니다. 지원 플랫폼, 로딩 정책과 배포 방법은
[공유 라이브러리와 purego](purego.md)를 참고하세요.

## 공개 Go 패키지 이름과 경로

기본 패키지 이름은 `name`의 snake_case입니다. `event_queue`처럼 밑줄이 생겨 Go 관례와
맞지 않는다면 명시적으로 바꿉니다.

```zig
.name = "event_queue",
.go_package = "eventqueue",
```

`go_package`는 소스의 `package` 절 이름과 기본 생성 경로를 정합니다. C 헤더
`zigo_event_queue.h`와 네이티브 라이브러리 `libevent_queue_zigo.a`는 계속 `name`을 사용합니다.
유효한 Go 식별자가 아니면 빌드 그래프 생성 시점에 실패합니다.

`go_package_path`는 `go_dir` 안의 생성 위치를 별도로 정합니다. 기본값은 `go_package`라서
기존 구성의 생성 경로와 바이트는 바뀌지 않습니다. 중첩 경로도 사용할 수 있습니다.

```zig
.go_package = "eventqueue",
.go_package_path = "api/events", // go/api/events/eventqueue_gen.go
```

모듈 루트에 공개 패키지를 생성하려면 `"."`을 지정합니다. 패키지 이름은 그대로
`go_package`입니다. `04-callback`의 cgo·purego 구성이 이 형태를 검증합니다.

```zig
.go_dir = b.path("go"),
.go_module = "example.com/mylib",
.go_package = "mylib",
.go_package_path = ".", // go/mylib_gen.go
```

공개 import path는 `go_package_path == "."`이면 `<go_module>`, 그 밖에는
`<go_module>/<go_package_path>`입니다. 경로는 `raw_package`와 같은 portable
slash-separated 상대 경로 규칙을 따르며 `"."`만 루트 표기로 따로 허용합니다.

`bindings.zig`의 [`.packages`](bindings-functions.md#공개-go-하위-패키지)가 있으면 각 `path`는 이
기본 경로 아래에 생성됩니다. 예를 들어 `go_package_path = "api"`와 `.path = "types"`는
`<go_module>/api/types`입니다. `go_package_doc`은 기본 패키지에만 적용되고, 하위 패키지는
각 항목의 `.doc`을 사용하며 없으면 기본 package 문장을 생성합니다.

## raw Go 패키지 위치

raw 패키지는 C ABI 또는 purego 함수 포인터를 담는 내부 계층입니다. 기본 위치는
`go/internal/raw/raw_gen.go`이며 일반 애플리케이션은 직접 import하지 않습니다.

```zig
.raw_package = "internal/raw",
```

다른 상대 경로로 옮길 수 있습니다.

```zig
// go/support/ffi/ffi_gen.go
.raw_package = "support/ffi",
```

`go_package_path`와 같은 경로를 지정하면 한 패키지에 함께 생성합니다.

```zig
// go/api/mylib_cgo_gen.go
.go_package = "mylib",
.go_package_path = "api",
.raw_package = "api",
```

루트에서도 colocate하려면 두 옵션을 모두 `"."`으로 둡니다. `raw_package = "."`만 단독으로
지정하면 raw 계층을 루트에 노출하는 모호한 구성이므로 빌드 그래프 생성 시점에 실패합니다.

그 밖의 경로는 `go_dir` 기준의 slash-separated 상대 경로여야 합니다. 절대 경로, 빈 요소,
`.` 또는 `..` 요소, 역슬래시는 허용하지 않습니다. 경로를 바꾼 뒤 `zig build go`를 실행하면
marker가 있는 이전 zigo 생성 파일만 정리합니다. `go.mod`와 marker가 없는 사용자 Go 파일은
유지됩니다.

하위 공개 패키지도 별도 예외 없이 `go_dir` 전체 marker walk에 포함됩니다. `.packages`에서
경로를 없애거나 옮긴 뒤 `zig build go`를 실행하면 옛 하위 디렉터리의 생성 파일은 제거되고,
그 디렉터리의 사용자 파일은 보존됩니다.

## 소스 이름과 문서 보강

Zig reflection에는 함수 파라미터 이름이 없습니다. zigo는 다음 순서로 이름을 결정합니다.

1. `bindings.zig`의 명시적인 `params`
2. `source_root`에서 시작한 Zig AST 탐색
3. `p0`, `p1` 형식의 fallback

```zig
.source_root = b.path("src/root.zig"),
```

`source_root`를 생략하면 `bindings.zig` 옆의 `root.zig`를 찾습니다. 실제 module root가 다른
위치라면 명시하세요. AST는 이름과 문서만 보강하며 타입 판단에는 사용되지 않습니다.

## cgo 플래그 덮어쓰기

기본적으로 대상 module과 그 module이 import하는 전체 module 그래프의 system library,
library path, framework 링크 정보를 생성된 `#cgo LDFLAGS`로 전달합니다. 배포 환경에서
별도 경로가 필요할 때만 전체 값을 덮어씁니다.

```zig
.cgo_flags = .{
    .cflags = &.{"-I/opt/mylib/include"},
    .ldflags = &.{ "-L/opt/mylib/lib", "-lmylib" },
    .extra_ldflags = &.{"-Wl,--as-needed"},
},
```

`cflags`와 `ldflags`는 zigo가 계산한 include 경로와 라이브러리 경로를 대체합니다.
`extra_ldflags`는 대체하지 않고 기본값 또는 `ldflags` 뒤에 덧붙습니다. module에 붙은
system library, framework, pkg-config 정보도 그대로 함께 나갑니다. 그것까지 빼려면
module에서 해당 링크를 하지 마세요. 정적 backend의 순서는 바인딩 archive, module 그래프의 정적
입력, `extra_ldflags`, system library입니다. `ldflags`를 지정하면 앞의 두 항목을 함께
대체하고 뒤의 두 항목은 유지합니다.

## 링크 정보가 전달되는 방식

`.cgo_static`과 `.cgo_dynamic`에서 대상 module과 모든 imported module의 링크 정보는
다음과 같이 생성된 raw 파일의 cgo 블록으로 옮겨집니다. 의존 module부터 안정적인 순서로
수집하고, 같은 library path, system library, pkg-config package, framework는 한 번만 적습니다.

| module에 한 일 | 생성된 줄 |
|---|---|
| `linkLibrary(static_lib)` / `addObjectFile(static_archive)` | `#cgo LDFLAGS: ... /absolute/path/libname.a` (`.cgo_static`만) |
| `linkSystemLibrary("z", .{})` | `#cgo LDFLAGS: ... -lz` |
| `linkSystemLibrary("libcurl", .{ .use_pkg_config = .force })` | `#cgo pkg-config: libcurl` |
| `addLibraryPath(...)` | `#cgo LDFLAGS: ... -L<경로>` |
| `linkFramework("CoreFoundation", .{})` | `#cgo darwin LDFLAGS: -framework CoreFoundation` |
| `linkFramework("Metal", .{ .weak = true })` | `#cgo darwin LDFLAGS: -weak_framework Metal` |

`use_pkg_config = .force`인 system library만 `-l` 대신 `#cgo pkg-config:` 줄로 나갑니다.
cgo가 pkg-config에게 컴파일·링크 플래그를 직접 묻게 하기 위해서입니다. 기본값 `.yes`는
"pkg-config를 시도하고 안 되면 `-lname`"이라는 뜻인데 cgo에는 그 fallback이 없으므로
`-lname`으로 내보냅니다. `.force`는 build 시 `pkg-config --exists <name>`과
`pkg-config --exists lib<name>`을 차례로 실행하고 성공한 spelling을 내보냅니다. 둘 다 실패하면
library와 선언 module을 적은 진단으로 `go` step이 실패합니다. `pkg-config` 실행 파일 자체가
없으면 원래 이름을 유지하고 warning을 출력합니다. `.force` 대상이 하나도 없으면 그 줄은 생성되지 않습니다. `rpath`와 추가 include 경로는 전달하지 않으므로 필요하면
`cgo_flags`로 직접 지정하세요.

`.purego`는 링크 지시자를 전혀 생성하지 않습니다. 시스템 라이브러리는 native 공유
라이브러리가 이미 링크하고 있어야 합니다. 반대로 `.cgo_static`은 archive를 Go 링크 시점에
푸는 방식이라, native가 쓰는 시스템 라이브러리가 이 블록에 빠짐없이 있어야 합니다. Zig는
정적 archive 안에 다른 archive를 합치지 않으므로 zigo는 module과 module이 import하는 모든
module의 `.other_step` 정적 라이브러리와 `.static_path` 입력을 의존 먼저 순서로 다시 적고,
binding install이 그 artifact에 의존하게 합니다. 같은 라이브러리에 여러 import를 거쳐 닿아도
한 번만 적습니다. fat archive를 만들지는 않습니다.

각 정적 입력은 binding archive와 같은 `zig-out/lib`에 `lib<name>.a`로 설치되고(`.other_step`은
라이브러리 이름, `.static_path`는 파일 이름에서 `lib` 접두사와 확장자를 뺀 것), cgo 줄에는
`${SRCDIR}` 기준 상대 경로로 적힙니다. Windows에서도 `.lib` 대신 `.a`로 설치하므로 cgo의
플래그 검사를 통과합니다. 이 줄은 raw package의 `zigo_link_inputs_gen.go`에 build-time으로
기록됩니다. 이 파일은 `.gitignore`에 추가해 커밋에서 제외하세요. `go-check`의 비교 대상도
아니며, `zig build`, `go-lib`, `go-check`,
`go`가 artifact와 함께 갱신합니다. 나머지 생성 파일은 다른 OS에서 byte-for-byte 비교할 수
있습니다. reflector는 호스트용으로 module을 복제해 실행하므로, 대상 전용 정적 입력이 있어도
`-Dtarget`으로 크로스 컴파일할 수 있습니다. `linkLibrary`로 붙인 정적 라이브러리는
`root_module`과 설치 헤더를 호스트용 정적 라이브러리로 한 번 더 복제해 연결합니다. 따라서
호출자 module의 C/C++ 소스가 그 라이브러리의 헤더, `link_libc` 또는 `link_libcpp` 설정에
의존해도 reflection 컴파일에서 유지됩니다. 동적 라이브러리와 `addObjectFile`로 붙인 미리
빌드된 archive는 호스트 실행 파일에 연결하지 않습니다.

## `gofmt` 선택

모든 생성 Go 파일은 기록 전에 `gofmt`를 거칩니다. 기본값은 `PATH`에서 찾은 실행 파일이며,
고정 경로가 필요하면 지정합니다.

```zig
.gofmt = "/opt/go/bin/gofmt",
```

`gofmt`를 찾지 못하면 생성과 `go-doctor`가 실패합니다. 사용자 소유 Go 파일은 포맷하지
않습니다.

## 자동 cleanup

생성된 caller-owned handle은 옵션 없이 항상 `runtime.AddCleanup` 안전망을 등록합니다.
그래서 생성 코드의 Go 하한은 1.24입니다. zigo가 새 `go.mod`를 만들면 `go 1.24`를
기록하고, 기존 `go.mod`는 수정하지 않으므로 직접 버전을 올려야 합니다.

안전망은 누수 대비일 뿐 명시적 `Close`를 대체하지 않습니다. 실행 시점이나 프로그램 종료
전 실행은 보장되지 않으며 임의 goroutine에서 호출될 수 있습니다. retained callback의 참조
순환이나 특정 OS thread에서만 가능한 해제에도 기대지 마세요. 수명주기 전체는
[객체 수명](bindings-handles.md#opaque-handle)에 정리되어 있습니다.

## ABI 기준 설정

독립 배포 버전과 호환성을 유지할 때만 Git ref를 지정합니다.

```zig
.abi_base = "HEAD",
```

기준 ref의 `zigo/semantic.json`과 현재 계약을 비교하는 `abi-check`가 추가됩니다. 옵션을
생략하면 zigo는 Git을 호출하지 않고 `GoBindings.abi_check`도 `null`입니다. CI 구성은
[생성물과 CI 관리](generated-code.md#ci-권장-구성)를 참고하세요.

## 공개 API 커버리지

`addStandardSteps`가 등록하는 `go-coverage`는 root 모듈과 등록 타입에서 도달할 수 있는 모든
`pub fn`을 재귀적으로 훑습니다. 바인딩에 들어간 함수는 `bound`, `.exclude`에 든 함수는
`excluded`, 나머지는 `unbound`로 분류합니다. 함수 메타데이터의 `.covers`가 가리키는 unbound
선언은 `wrapped`로 따로 표시하고 bound 비율에 포함합니다. `.covers`는 경로 하나 또는 목록을
받으며 생성 결과나 ABI 비교에는 영향을 주지 않습니다. `.fields`가 만든 getter와 setter도 bound 함수로
셉니다. 비율은 `bound / (bound + unbound)`이며 excluded 함수는 목록에는 나오지만 분모에는
들어가지 않습니다. 함수 signature에서 참조하지만 `.types`에 등록하지 않은 공개 struct, enum,
union도 `unregistered types`에 따로 표시합니다. 이 목록은 root가 선언한 경로(`Terminal.Options`)로 적으므로
같은 이름의 타입을 구분할 수 있고, `.types` 항목에 그대로 쓸 수 있습니다.

```bash
zig build go-coverage
```

unbound 이유는 기존 ZIGO signature 제약을 기준으로 가능한 만큼 설명합니다. 문제가 여러 개면
모든 parameter와 return을 소스 이름으로 나열하고, plain struct는 첫 번째 문제 field까지
표시합니다. metadata를 붙이면 바인딩할 수 있는 함수는 `not listed`, 판별할 수 없는 경우는
`unsupported signature`입니다.
CI artifact처럼 기계가 읽을 보고서도 필요하면 build option을 한 번 선언해 `coverage_json`에
전달합니다. 경로는 build root 기준입니다.

```zig
const coverage_json = b.option(
    []const u8,
    "coverage-json",
    "Write the go-coverage report as JSON at this path",
);

const bindings = zigo.addGoBindings(b, .{
    // ...
    .coverage_json = coverage_json,
});
```

```bash
zig build go-coverage -Dcoverage-json=zigo/coverage.json
```

## 여러 바인딩 세트

한 빌드에 cgo와 purego 또는 서로 다른 라이브러리를 함께 등록한다면 `go_dir`, `go_module`을
분리하고 표준 스텝에 접두사를 붙입니다.

```zig
_ = admin_bindings.addStandardSteps(b, .{ .name_prefix = "admin" });
// admin-go, admin-go-check, admin-go-report, admin-go-doctor, admin-go-coverage,
// admin-go-lib, admin-go-verify, admin-abi-check
```

상위 빌드가 라이브러리 설치를 별도로 관리한다면 기본 install 연결만 끌 수 있습니다.
`admin-go-lib` 스텝은 이 설정과 무관하게 계속 라이브러리를 설치합니다.

```zig
_ = admin_bindings.addStandardSteps(b, .{
    .name_prefix = "admin",
    .install_library_by_default = false,
});
```

전체 스텝의 역할은 [생성물과 CI 관리](generated-code.md#표준-빌드-스텝)에서 확인할 수 있습니다.
