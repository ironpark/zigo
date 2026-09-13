# 빌드 옵션 참조

이 문서는 `zigo.addGoBindings`, `zigo.addRustBindings`와 각 `addStandardSteps`의 공개 빌드 API를
나열합니다. 선택 기준과 예시는 [설정과 백엔드](../build-and-ship/configuration-and-backends.md)를
사용하세요.

## `addGoBindings`

필수 옵션:

| 필드 | 타입 역할 |
|---|---|
| `name` | 라이브러리, 헤더와 기본 패키지의 기준 이름 |
| `module` | reflection하고 링크할 `*std.Build.Module` |
| `layout` | Go 모듈 경로와 패키지 배치. [`Layout`](#layout) 참고 |
| `target` | primary 네이티브 대상 |
| `optimize` | 네이티브 optimization mode |

선택 옵션:

| 필드 | 기본값 | 의미 |
|---|---|---|
| `bindings` | `module.root_source_file` 옆의 `bindings.zig` | `zigo.define`을 내보내는 소스 경로 |
| `source_root` | `null` | 매개변수 이름과 doc을 읽을 Zig 소스 root |
| `go_dir` | `b.path("go")` | 생성 Go 모듈 디렉터리 |
| `prefix` | `"zg"` | C 심볼 접두사 |
| `link` | `.cgo_static` | `.cgo_static`, `.cgo_dynamic`, `.{ .purego = LibraryLoading }` |
| `targets` | `&.{}` | 같은 Go tree에 추가할 resolved 대상 |
| `plugins` | `&.{}` | 순서대로 실행할 플러그인 모듈과 설정 |
| `cgo_flags` | `null` | C와 linker flag 설정 |
| `abi_base` | `"HEAD"` | ABI 비교 Git ref. `null`이면 ABI 검사를 등록하지 않음 |
| `gofmt` | `null` | 기본 `PATH` 대신 사용할 포매터 경로 |
| `go_package_doc` | `null` | 바인딩 파일의 `//!` 주석, 없으면 기본 설명으로 대체 |
| `install` | `.lib`, `.header` | 네이티브 산출물 위치와 이름 |
| `standard_steps` | `.{}` | `addStandardSteps` 옵션. `null`이면 표준 단계를 등록하지 않음 |

`module.root_source_file`이 없는 모듈(C 소스만 있는 모듈)은 `bindings`를 직접 지정해야 합니다.

## `Layout`

```zig
.layout = .{
    .go_module = "example.com/mylib/go",
    .go_package = null,
    .go_package_path = null,
    .raw_package = "internal/raw",
    .raw_colocated = false,
},
```

| 필드 | 기본값 | 의미 |
|---|---|---|
| `go_module` | 필수 | Go 모듈 import 경로 |
| `go_package` | normalized `name` | 공개 Go 패키지 이름 |
| `go_package_path` | `go_package` | 공개 패키지 relative 경로; `.`은 모듈 root |
| `raw_package` | `"internal/raw"` | raw 패키지 경로. `raw_colocated`가 참이면 무시 |
| `raw_colocated` | `false` | raw 바인딩을 공개 패키지 안에 함께 생성 |

colocation은 `raw_colocated`로만 선택합니다. `raw_package`가 공개 패키지 경로와 같으면 build가
실패하며, `raw_colocated = true`일 때 `raw_package`는 기본값이어야 합니다.

## `Link`

```zig
pub const Link = union(enum) {
    cgo_static,
    cgo_dynamic,
    purego: LibraryLoading,
};
```

purego는 항상 공유 라이브러리를 사용하고 run-time loading 정책을 payload로 가집니다. 기본
정책은 `.{ .purego = .{} }`입니다. cgo static과 dynamic은 Go 빌드에 C 컴파일러가 필요하며
loading 정책이 없으므로 cgo에 loader 옵션을 쓰는 것은 컴파일 오류입니다.

## `CgoFlags`

```zig
.cgo_flags = .{
    .cflags = &.{},
    .extra_ldflags = &.{},
    .target_ldflags = &.{
        .{ .goos = "linux", .goarch = "amd64", .ldflags = &.{"-lm"} },
    },
}
```

- `cflags`: 비어 있지 않으면 계산된 CFLAGS를 교체합니다. 빈 목록은 기본값을 유지합니다.
- `extra_ldflags`: zigo가 만든 라이브러리 LDFLAGS 뒤에 모든 플랫폼용 값을 추가합니다.
- `target_ldflags`: `goos`와 optional `goarch`별 별도 `#cgo` 줄을 추가합니다.

LDFLAGS 전체를 교체하는 옵션은 없습니다. 헤더와 바인딩 라이브러리 경로는 zigo가 소유합니다.

## `Install`

| 필드 | 기본값 |
|---|---|
| `library_dir` | `.lib` |
| `header_dir` | `.header` |
| `library_name` | `<name>_zigo` |
| `header_name` | cgo `zigo_<name>.h`, purego `zigo_<name>_purego.h` |

이름에는 디렉터리 separator를 넣을 수 없습니다. `library_name`에는 OS 접두사와 확장자를
넣지 않습니다.

## `LibraryLoading`

`Link.purego`의 payload입니다.

| 필드 | 기본값 | 의미 |
|---|---|---|
| `search_paths` | `&.{}` | 환경 변수 다음에 확인할 파일 또는 디렉터리 |
| `env_vars` | `null` | `null`은 패키지별 변수와 `ZIGO_LIBRARY_PATH` |
| `loader` | `.explicit` | explicit, automatic, automatic_internal |

`${EXECUTABLE_DIR}`는 실행 파일 디렉터리로 확장됩니다. search 경로에는 control character,
quote, backslash와 `:`를 넣을 수 없습니다. Windows drive 경로는 `LoadLibrary` 인자나 환경
변수로 전달하세요.

## 플러그인 등록

```zig
const enumkit: zigo.PluginModule = .{
    .name = "zigo_enumkit",
    .root_source_file = b.dependency("zigo_enumkit", .{}).path("src/plugin.zig"),
};

// addGoBindings options
.plugins = &.{enumkit},
```

`name`은 `bindings.zig`에서 import하는 이름과 같아야 합니다. `root_source_file`은
`pub const plugin`을 제공합니다. 플러그인이 빌드 시점 `Config`를 선언했다면
`.config = zigo.configJson(b, value)`로 JSON을 전달합니다. 이것이 플러그인을 설정하는 유일한
경로입니다.

zigo에 내장된 플러그인은 `root_source_file` 없이 플러그인 이름으로 설정합니다.

```zig
.plugins = &.{.{ .name = "MUST", .config = zigo.configJson(b, .{ .enabled = true }) }},
```

## `addStandardSteps`

`addGoBindings`는 `standard_steps`가 `null`이 아니면 이 함수를 직접 호출하고 결과를
`GoBindings.standard_steps`에 둡니다. 직접 호출할 때는 `.standard_steps = null`로 두세요.

```zig
.standard_steps = .{
    .variant = null,
    .install_library_by_default = true,
},
```

`variant = "purego"`는 모든 기본 단계를 언어 토큰 뒤에 붙여 `go-purego`, `go-purego-check`,
`go-purego-verify`처럼 등록합니다. `install_library_by_default = false`는 plain `zig build`의
install 의존성만 끄며 명시적 `go-lib`는 유지합니다.

`addStandardSteps`는 `-D[<variant>-]coverage-json=<path>` 빌드 옵션도 선언합니다. 지정하면
`go-coverage`가 보고서의 JSON 형태를 그 소스 경로에 씁니다.

반환된 `StandardSteps`에는 `update`, `check`, optional `abi_check`, `report`, `doctor`,
`coverage`, `library`, `verify` 단계 포인터가 있습니다. 등록되는 단계 이름은
[생성물과 CI](../build-and-ship/generated-files-and-ci.md#표준-빌드-단계)를 참고하세요.

## `GoBindings`에서 제공하는 경로

- `lib`: primary 대상의 컴파일 단계
- `install_library`: primary install 단계
- `library_filename`: 대상별 실제 basename
- `library_path`: primary 라이브러리의 전체 install 경로
- `native_libraries`: 대상과 추가 대상별 compile/install/path
- `semantic_json`: 생성 semantic document 경로
- `coverage_json`: coverage 보고서의 JSON 형태
- `resolved_pkg_config`: 빌드 시점에 해석한 pkg-config 입력
- `standard_steps`: `standard_steps` 옵션이 등록한 단계, `null`로 두었으면 `null`

사용자 지정 단계는 이름을 다시 조합하지 말고 이 값을 사용하세요.

## `addRustBindings`

최소 Rust 바인딩 세트(스칼라, `[]const T` slice, error union)를 생성합니다. shim, panic 소스와 C
헤더는 `addGoBindings`가 같은 문서에서 만드는 산출물과 동일하며, 생성기의 `--output-target`과
crate 레이아웃만 다릅니다.

```zig
_ = zigo.addRustBindings(b, .{
    .name = "calculator",
    .module = library,
    .rust_dir = b.path("rust"),
    .target = target,
    .optimize = optimize,
});
```

### `RustOptions`

`Options`보다 의도적으로 작습니다. cgo 링크 줄, `go.mod` 관리, Go 플랫폼 단어, purego 로딩
정책은 Cargo crate가 자체 `build.rs`로 처리하므로 여기에는 없습니다.

필수 옵션:

| 필드 | 타입 역할 |
|---|---|
| `name` | 라이브러리, 헤더와 crate 이름의 기준 이름. 정규화한 값이 유효한 Rust crate 식별자여야 합니다 |
| `module` | reflection하고 링크할 `*std.Build.Module` |
| `rust_dir` | crate 디렉터리. `src/lib.rs`, `src/raw.rs`, `src/error.rs`를 그 안에 생성하며 `Cargo.toml`과 `build.rs`는 사용자가 관리합니다 |
| `target` | 네이티브 대상 |
| `optimize` | 네이티브 optimization mode |

선택 옵션:

| 필드 | 기본값 | 의미 |
|---|---|---|
| `bindings` | `module.root_source_file` 옆의 `bindings.zig` | `zigo.define`을 내보내는 소스 경로 |
| `source_root` | `null` | 매개변수 이름과 doc을 읽을 Zig 소스 root |
| `prefix` | `"zg"` | C 심볼 접두사 |
| `rustfmt` | `null` | 기본 `PATH` 대신 사용할 `rustfmt` 경로 |
| `abi_base` | `"HEAD"` | ABI 비교 Git ref. `null`이면 ABI 검사를 등록하지 않음 |
| `install` | `.lib`, `.header` | 네이티브 산출물 위치와 이름. [`Install`](#install)과 같습니다 |
| `standard_steps` | `.{}` | `addStandardSteps` 옵션. `null`이면 표준 단계를 등록하지 않음 |

### `RustBindings`에서 제공하는 경로

- `update`: crate 소스를 `rust_dir`에 생성하고 라이브러리를 install하는 단계
- `check`: 커밋된 crate가 stale이면 실패하는 단계
- `abi_check`: `abi_base`가 있을 때 breaking ABI 변경에 실패하는 단계, 없으면 `null`
- `coverage`: 공개 Zig API 바인딩 coverage 보고 단계. Zig 선언을 읽으므로 Go와 같은 실행입니다
- `lib`: crate가 링크하는 네이티브 라이브러리의 컴파일 단계
- `install_library`: install 단계
- `library_path`: 라이브러리의 전체 install 경로
- `semantic_json`: 생성 semantic document 경로
- `standard_steps`: `standard_steps` 옵션이 등록한 단계, `null`로 두었으면 `null`

Rust 바인딩 set의 sidecar는 `zigo/rust/semantic.json`과 `zigo/rust/errors.lock.json`입니다. Go는
`zigo/go/`를 쓰므로 한 프로젝트에서 `addGoBindings`와 `addRustBindings`를 함께 호출해도 파일과
단계 이름이 겹치지 않습니다.

### Rust `addStandardSteps`

```zig
.standard_steps = .{
    .variant = null,
    .install_library_by_default = true,
},
```

옵션의 의미는 Go와 같습니다(`variant = "admin"`은 `rust-admin`, `rust-admin-check`, ...).
등록되는 단계는 다음과 같습니다.

| 단계 | 역할 |
|---|---|
| `rust` | Rust 바인딩을 생성하고 빌드 |
| `rust-check` | 생성 Rust 바인딩이 stale이면 실패 |
| `rust-coverage` | 공개 Zig API 바인딩 coverage 보고 |
| `rust-lib` | 네이티브 Rust 바인딩 라이브러리 빌드와 install |
| `rust-abi-check` | `abi_base`가 설정된 경우에만 등록. breaking 바인딩 ABI 변경에 실패 |

`rust-test` 단계는 없습니다. `cargo`는 의존성을 해석하고 내려받으므로 `zig build`에서 실행하면
네트워크에 닿는 빌드 단계가 됩니다. 예제는 Go 예제가 `go test`를 직접 실행하듯 `cargo test`를
직접 실행합니다.

반환된 `StandardSteps`에는 `update`, `check`, optional `abi_check`, `coverage`, `library` 단계
포인터가 있습니다.
