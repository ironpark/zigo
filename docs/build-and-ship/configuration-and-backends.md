# 설정과 백엔드

이 가이드는 `zigo.addGoBindings`를 프로젝트에 맞게 구성하고 네이티브 라이브러리 연결 방식을
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

기본값은 cgo 정적 링크와 `internal/raw` 패키지입니다. 공개 패키지는 이름을 snake_case로
변환한 `go_package`를 사용하며, 기본 import 경로는 `<go_module>/<go_package>`입니다.

## 백엔드 선택

| `link` | Go 빌드 | 네이티브 산출물 | 선택할 때 |
|---|---|---|---|
| `.cgo_static` | `CGO_ENABLED=1` | 정적 아카이브 | 기본값, 실행 파일에 네이티브 코드를 링크 |
| `.cgo_dynamic` | `CGO_ENABLED=1` | 공유 라이브러리 | 네이티브 라이브러리를 별도 배포·교체 |
| `.purego` | `CGO_ENABLED=0` 가능 | 공유 라이브러리 | Go 빌드에서 C 컴파일러 제거 |

백엔드는 공개 Go API를 가능한 한 바꾸지 않습니다. 라이브러리를 빌드 시 링크하는지 실행 시
로드하는지와 배포 파일이 달라집니다.

## Go 패키지 배치

```zig
.go_package = "client",
.go_package_path = "client/v2",
.raw_package = "internal/native",
.go_package_doc = "Package client exposes the native library.",
```

- `go_package`는 Go 소스의 패키지 이름입니다.
- `go_package_path`는 `go_dir` 안의 디렉터리이자 import 경로 접미사입니다.
- `.`을 사용하면 공개 패키지를 Go 모듈 root에 둡니다.
- `raw_package`는 기본값 `internal/raw`로 분리하는 것을 권장합니다.

한 Go 모듈에 여러 바인딩 set을 생성하면 `go_dir`, 공개 경로, raw 경로와 C `prefix`가
서로 충돌하지 않아야 합니다. 표준 단계에도 접두사를 붙입니다.

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

디렉터리는 Zig install 접두사 기준입니다. `library_name`에는 `lib` 접두사와 확장자를 넣지
않습니다. 실제 결과 경로가 필요한 사용자 지정 빌드 단계는 `bindings.library_path`와
`bindings.library_filename`을 사용하세요.

## 여러 대상을 한 Go tree에 넣기

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

`target`과 추가 대상의 라이브러리는 `<library_dir>/<goos>_<goarch>/`에 설치됩니다. cgo는
플랫폼별 `#cgo` 줄을 만들고 purego loader는 실행 중인 플랫폼 디렉터리를 선택합니다.

모듈 의존 관계에 미리 빌드한 archive가 있으면 zigo가 다른 대상용으로 다시 만들 수 없습니다.
그 경우 대상마다 `addGoBindings`를 따로 구성하거나 소스에서 빌드되는 라이브러리로 바꾸세요.

## C와 네이티브 링크 옵션

zigo는 모듈의 시스템 라이브러리, 프레임워크와 링크된 산출물을 추적합니다. 직접 보강해야 할
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

비어 있지 않은 `cflags`와 `ldflags`는 계산된 기본값을 교체하고 `extra_ldflags`는 뒤에 추가합니다. 전체
교체는 헤더와 바인딩 라이브러리 경로까지 직접 책임져야 하므로 일반적으로
`extra_ldflags`와 `target_ldflags`를 사용하세요.

`.cgo_dynamic`은 배포 환경의 rpath를 자동으로 정하지 않습니다. macOS의
`DYLD_LIBRARY_PATH`, Linux의 `LD_LIBRARY_PATH` 또는 애플리케이션에 맞는
`@loader_path`·`$ORIGIN` rpath를 구성해야 합니다.

## purego 설정

[시작 가이드](../getting-started.md)의 단일 바인딩을 purego로 바꾸려면
`addGoBindings` 옵션에 다음 한 줄을 추가합니다. `go_dir`와 표준 단계 이름은 유지합니다.

```zig
.link = .purego,
```

시작 가이드를 완료하여 `go/go.mod`가 이미 있다면, 생성 전에 purego 의존성을 추가합니다.
zigo는 기존 `go.mod`의 의존성을 자동 수정하지 않습니다.

```bash
(cd go && go get github.com/ebitengine/purego@v0.10.2)
zig build go
(cd go && go mod tidy)
```

cgo와 purego를 함께 제공하려면 별도 `addGoBindings`를 구성하고 Go 디렉터리·모듈과
표준 단계 이름을 구분합니다. 아래는 추가 바인딩의 전체 빌드 설정이며 기존 `mylib`,
`target`, `optimize`를 사용합니다.

```zig
const purego_bindings = zigo.addGoBindings(b, .{
    .name = "mylib",
    .module = mylib,
    .bindings = b.path("src/bindings.zig"),
    .source_root = b.path("src/root.zig"),
    .go_dir = b.path("go-purego"),
    .go_module = "example.com/mylib/go-purego",
    .target = target,
    .optimize = optimize,
    .link = .purego,
});
_ = purego_bindings.addStandardSteps(b, .{ .name_prefix = "purego" });
```

이 추가 바인딩은 `zig build purego-go`로 생성합니다. `go-purego/go.mod`가 없으면 zigo가
purego 의존성을 포함해 만들고, 이미 있다면 생성 전에 해당 디렉터리에서 위 `go get`을
실행합니다. 생성 후 `go mod tidy`로 체크섬을 준비합니다.

기본 정책은 사용자가 공개 `LoadLibrary`를 호출하는 명시적 로딩입니다.

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
| `.automatic` | 첫 바인딩 호출에 검색하며 공개 loader API도 유지 |
| `.automatic_internal` | 첫 호출에 검색하고 loader API는 숨김 |

`env_vars = null`은 패키지별 기본 변수와 `ZIGO_LIBRARY_PATH`를 사용하고 `&.{}`은 환경
변수 검색을 끕니다. 라이브러리 loading은 네이티브 코드 실행이므로 사용자가 통제할 수 없는 경로를
그대로 신뢰하지 마세요.

모든 필드와 기본값은 [빌드 옵션 참조](../reference/build-options.md), 배포 배치는
[패키징과 배포](packaging-and-distribution.md)를 참고하세요.
