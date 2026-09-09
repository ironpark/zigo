# Build option 참조

이 문서는 `zigo.addGoBindings`와 `addStandardSteps`의 public build API를 나열합니다. 선택 기준과
예시는 [설정과 백엔드](../build-and-ship/configuration-and-backends.md)를 사용하세요.

## `addGoBindings`

필수 option:

| 필드 | 타입 역할 |
|---|---|
| `name` | library, header와 기본 package의 기준 이름 |
| `module` | reflection하고 link할 `*std.Build.Module` |
| `bindings` | `zigo.define`을 내보내는 source path |
| `go_dir` | 생성 Go module directory |
| `go_module` | Go module import path |
| `target` | primary native target |
| `optimize` | native optimization mode |

선택 option:

| 필드 | 기본값 | 의미 |
|---|---|---|
| `source_root` | `null` | parameter name과 doc을 읽을 Zig source root |
| `prefix` | `"zg"` | C symbol prefix |
| `link` | `.cgo_static` | `.cgo_static`, `.cgo_dynamic`, `.purego` |
| `targets` | `&.{}` | 같은 Go tree에 추가할 resolved target |
| `plugins` | `&.{}` | 순서대로 실행할 plugin module |
| `cgo_flags` | `null` | C와 linker flag 설정 |
| `abi_base` | `null` | ABI 비교 Git ref |
| `raw_package` | `"internal/raw"` | Go module 안의 raw package path |
| `gofmt` | `null` | 기본 `PATH` 대신 사용할 formatter path |
| `go_package` | normalized `name` | public Go package name |
| `go_package_path` | `go_package` | public package relative path; `.`은 module root |
| `go_package_doc` | binding/module doc | package GoDoc body |
| `plugin_config` | `"{}"` | plugin별 JSON configuration |
| `coverage_json` | `null` | coverage JSON output source path |
| `library_loading` | 명시적 | purego loader policy |
| `install` | `.lib`, `.header` | native artifact 위치와 이름 |

## `Link`

```zig
pub const Link = enum {
    cgo_static,
    cgo_dynamic,
    purego,
};
```

purego는 항상 shared library를 사용합니다. cgo static과 dynamic은 Go build에 C compiler가
필요합니다.

## `CgoFlags`

```zig
.cgo_flags = .{
    .cflags = &.{},
    .ldflags = &.{},
    .extra_ldflags = &.{},
    .target_ldflags = &.{
        .{ .goos = "linux", .goarch = "amd64", .ldflags = &.{"-lm"} },
    },
}
```

- `cflags`: 계산된 CFLAGS를 교체합니다.
- `ldflags`: 계산된 LDFLAGS를 교체합니다.
- `extra_ldflags`: 계산된 LDFLAGS 뒤에 모든 platform용 값을 추가합니다.
- `target_ldflags`: `goos`와 optional `goarch`별 별도 `#cgo` line을 추가합니다.

## `Install`

| 필드 | 기본값 |
|---|---|
| `library_dir` | `.lib` |
| `header_dir` | `.header` |
| `library_name` | `<name>_zigo` |
| `header_name` | cgo `zigo_<name>.h`, purego `zigo_<name>_purego.h` |

이름에는 directory separator를 넣을 수 없습니다. `library_name`에는 OS prefix와 확장자를
넣지 않습니다.

## `LibraryLoading`

purego 전용입니다.

| 필드 | 기본값 | 의미 |
|---|---|---|
| `search_paths` | `&.{}` | 환경 변수 다음에 확인할 파일 또는 directory |
| `env_vars` | `null` | `null`은 package별 변수와 `ZIGO_LIBRARY_PATH` |
| `loader` | `.explicit` | explicit, automatic, automatic_internal |

`${EXECUTABLE_DIR}`는 실행 파일 directory로 확장됩니다. search path에는 control character,
quote, backslash와 `:`를 넣을 수 없습니다. Windows drive path는 `LoadLibrary` 인자나 환경
변수로 전달하세요.

## plugin 등록

```zig
const enumkit: zigo.PluginModule = .{
    .name = "zigo_enumkit",
    .root_source_file = b.dependency("zigo_enumkit", .{}).path("src/plugin.zig"),
};

// addGoBindings options
.plugins = &.{enumkit},
```

`name`은 `bindings.zig`에서 import하는 이름과 같아야 합니다. `root_source_file`은
`pub const plugin`을 제공합니다. plugin이 build-time `Config`를 선언했다면
`.config = zigo.configJson(b, value)`로 JSON을 전달합니다.

## `addStandardSteps`

```zig
_ = bindings.addStandardSteps(b, .{
    .name_prefix = null,
    .install_library_by_default = true,
});
```

`name_prefix = "admin"`은 모든 기본 step을 `admin-go`, `admin-go-check`처럼 등록합니다.
`install_library_by_default = false`는 plain `zig build`의 install dependency만 끄며 명시적
`go-lib`는 유지합니다.

반환된 `StandardSteps`에는 `update`, `check`, optional `abi_check`, `report`, `doctor`,
`coverage`, `library`, `verify` step pointer가 있습니다.

## `GoBindings`에서 제공하는 경로

- `lib`: primary target의 compile step
- `install_library`: primary install step
- `library_filename`: target별 실제 basename
- `library_path`: primary library의 전체 install path
- `native_libraries`: target과 추가 target별 compile/install/path
- `semantic_json`: 생성 semantic document path
- `resolved_pkg_config`: build-time에 해석한 pkg-config 입력

custom step은 이름을 다시 조합하지 말고 이 값을 사용하세요.
