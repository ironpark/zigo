# 설정과 백엔드

이 가이드는 `zigo.addGoBindings`를 프로젝트에 맞게 구성하고 native library 연결 방식을
선택하는 방법을 설명합니다.

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

기본값은 cgo 정적 링크, `internal/raw` raw package와 `<go_module>/<name>` public package입니다.

## 백엔드 선택

| `link` | Go build | native artifact | 선택할 때 |
|---|---|---|---|
| `.cgo_static` | `CGO_ENABLED=1` | static archive | 기본값, 실행 파일에 native 코드를 링크 |
| `.cgo_dynamic` | `CGO_ENABLED=1` | shared library | native library를 별도 배포·교체 |
| `.purego` | `CGO_ENABLED=0` 가능 | shared library | Go build에서 C compiler 제거 |

백엔드는 public Go API를 가능한 한 바꾸지 않습니다. library를 빌드 시 링크하는지 실행 시
로드하는지와 배포 파일이 달라집니다.

## Go package 배치

```zig
.go_package = "client",
.go_package_path = "client/v2",
.raw_package = "internal/native",
.go_package_doc = "Package client exposes the native library.",
```

- `go_package`는 Go source의 package name입니다.
- `go_package_path`는 `go_dir` 안의 directory이자 import path suffix입니다.
- `.`을 사용하면 public package를 Go module root에 둡니다.
- `raw_package`는 기본값 `internal/raw`로 분리하는 것을 권장합니다.

한 Go module에 여러 binding set을 생성하면 `go_dir`, public path, raw path와 C `prefix`가
서로 충돌하지 않아야 합니다. 표준 step에도 prefix를 붙입니다.

```zig
_ = admin_bindings.addStandardSteps(b, .{ .name_prefix = "admin" });
```

이 경우 `admin-go`, `admin-go-check`, `admin-go-verify`가 등록됩니다.

## 설치 위치와 이름

```zig
.install = .{
    .library_dir = .{ .custom = "dist/lib" },
    .header_dir = .{ .custom = "dist/include" },
    .library_name = "mylib_native",
    .header_name = "mylib_native.h",
},
```

디렉터리는 Zig install prefix 기준입니다. `library_name`에는 `lib` prefix와 확장자를 넣지
않습니다. 실제 결과 경로가 필요한 custom build step은 `bindings.library_path`와
`bindings.library_filename`을 사용하세요.

## 여러 target을 한 Go tree에 넣기

```zig
.targets = &.{
    b.resolveTargetQuery(.{
        .cpu_arch = .x86_64,
        .os_tag = .linux,
        .abi = .gnu,
    }),
    b.resolveTargetQuery(.{
        .cpu_arch = .x86_64,
        .os_tag = .windows,
        .abi = .gnu,
    }),
},
```

`target`과 추가 target의 library는 `<library_dir>/<goos>_<goarch>/`에 설치됩니다. cgo는
platform별 `#cgo` line을 만들고 purego loader는 실행 중인 platform directory를 선택합니다.

module graph에 미리 빌드한 archive가 있으면 zigo가 다른 target용으로 다시 만들 수 없습니다.
그 경우 target마다 `addGoBindings`를 따로 구성하거나 source에서 빌드되는 library로 바꾸세요.

## C와 native link option

zigo는 module의 system library, framework와 linked artifact를 추적합니다. 직접 보강해야 할
때만 `cgo_flags`를 사용합니다.

```zig
.cgo_flags = .{
    .cflags = &.{"-DMYLIB_FEATURE=1"},
    .extra_ldflags = &.{"-lm"},
    .target_ldflags = &.{
        .{ .goos = "linux", .ldflags = &.{"-Wl,--as-needed"} },
    },
},
```

`cflags`와 `ldflags`는 계산된 기본값을 교체하고 `extra_ldflags`는 뒤에 추가합니다. 전체
교체는 header와 binding library 경로까지 직접 책임져야 하므로 일반적으로
`extra_ldflags`와 `target_ldflags`를 사용하세요.

`.cgo_dynamic`은 배포 환경의 rpath를 자동으로 정하지 않습니다. macOS의
`DYLD_LIBRARY_PATH`, Linux의 `LD_LIBRARY_PATH` 또는 애플리케이션에 맞는
`@loader_path`·`$ORIGIN` rpath를 구성해야 합니다.

## purego 설정

```zig
const purego_bindings = zigo.addGoBindings(b, .{
    // 공통 option ...
    .go_dir = b.path("go-purego"),
    .go_module = "example.com/mylib/go-purego",
    .link = .purego,
});
_ = purego_bindings.addStandardSteps(b, .{ .name_prefix = "purego" });
```

기본 policy는 사용자가 public `LoadLibrary`를 호출하는 명시적 로딩입니다.

```go
if err := mylib.LoadLibrary("/opt/myapp/lib/" + mylib.DefaultLibraryName); err != nil {
    return err
}
```

자동 로딩이 필요하면 검색 위치와 함께 명시합니다.

```zig
.library_loading = .{
    .search_paths = &.{ "${EXECUTABLE_DIR}", "${EXECUTABLE_DIR}/../lib" },
    .env_vars = &.{"MYLIB_LIBRARY_PATH"},
    .loader = .automatic,
},
```

| loader | 동작 |
|---|---|
| `.explicit` | `LoadLibrary`를 호출해야 함 |
| `.automatic` | 첫 binding 호출에 검색하며 public loader API도 유지 |
| `.automatic_internal` | 첫 호출에 검색하고 loader API는 숨김 |

`env_vars = null`은 package별 기본 변수와 `ZIGO_LIBRARY_PATH`를 사용하고 `&.{}`은 환경
변수 검색을 끕니다. library loading은 native code 실행이므로 사용자가 통제할 수 없는 경로를
그대로 신뢰하지 마세요.

모든 field와 기본값은 [build option 참조](../reference/build-options.md), 배포 layout은
[패키징과 배포](packaging-and-distribution.md)를 참고하세요.
