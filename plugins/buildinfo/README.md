# buildinfo

네이티브 library가 **어떻게 빌드되었는지**를 알려 주는 문자열 하나를 생성 API에 더합니다.
`go`와 `rust` 렌더링 slot을 모두 채우고, 그 둘이 감싸는 심볼은 플러그인이 직접 실어 보낸
Zig 소스에서 나옵니다.

다른 동봉 플러그인과 달리 읽을 선언이 없습니다. 공개하는 것이 문서의 사실이 아니라 네이티브
library의 사실이므로 attachment(`use(...)`)가 없고, `build.zig`의 `.plugins`에 넣는 것만으로
동작합니다. 그래서 이 패키지는 플러그인 계약의 네이티브 절반에 대한 기준 예제이기도 합니다:
소스 하나, 심볼 하나, target마다 wrapper 하나.

```zig
const buildinfo: zigo.PluginModule = .{
    .name = "zigo_buildinfo",
    .root_source_file = b.dependency("zigo_buildinfo", .{}).path("src/plugin.zig"),
    // `native.sources`가 선언한 목록을 한 번 더 적습니다. 경로를 module로 바꿀 수 있는
    // 것은 `build.zig`뿐이고, 빌드 그래프는 configure 시점에 그 경로를 알아야 합니다.
    .native_sources = &.{.{ .module = "buildinfo_native", .path = "native.zig" }},
};
// addGoBindings 또는 addRustBindings 옵션: .plugins = &.{buildinfo}
```

`build.zig.zon`에 이 패키지를 `zigo_buildinfo` 의존성으로 추가하세요.

## 생성되는 것

```go
// BuildInfo reports how the native library behind this binding was built:
// the Zig version, the optimize mode and the target triple.
func BuildInfo() string
```

```rust
pub fn build_info() -> &'static str
```

```text
zig 0.16.0; Debug; aarch64-macos-none
```

문자열은 `src/native.zig`가 `@import("builtin")`에서 comptime에 조립합니다. 세 조각은 Zig
version, optimize mode, target triple이며 `; `로 구분됩니다. 생성 코드는 이 값을 알 수
없습니다. 네이티브 library를 실제로 컴파일한 빌드만 답할 수 있고, 그것이 이 플러그인이
렌더링이 아니라 네이티브 기여인 이유입니다.

## 옵션

선언 옵션은 없습니다. 빌드 설정만 하나 있습니다.

```zig
.config = zigo.configJson(b, .{ .enabled = false }),
```

- `enabled` (기본 `true`): 끄면 심볼도 wrapper도 만들지 않습니다. C 헤더, 두 Go raw backend,
  Rust raw 모듈, `abi-diff`의 기록 모두 플러그인을 넣기 전과 같아집니다.

## 어떻게 동작하나요

1. `src/native.zig`는 평범한 Zig 파일입니다. `std` 말고는 아무것도 import하지 않고 아무것도
   `export`하지 않습니다. 생성된 shim이 이 파일을 `buildinfo_native`로 import합니다.
2. `native.symbols`가 `build_info`를 선언합니다. 반환은 `api.c_string`, 곧 NUL로 끝나는
   문자열입니다. shim이 `zg_buildinfo_build_info`를 `export`하고 구현을 호출합니다.
3. 심볼은 바인딩 함수와 같은 경로로 실립니다. C 헤더는
   `ZIGO_EXPORT const char * zg_buildinfo_build_info(void);`, Go raw 패키지는
   `BuildinfoBuildInfo() string`, Rust raw 모듈은 `buildinfo_build_info() -> &'static str`을
   가집니다.
4. 공개 쪽에는 아무것도 자동으로 쓰이지 않습니다. 두 slot이 자기 심볼을 읽어 `rawCall`로
   감쌉니다. 이름을 직접 쓰지 않으므로 layout이나 backend가 달라도 호출이 어긋나지 않습니다.

포인터는 어느 공개 쪽에도 나타나지 않습니다. Go raw 패키지가 바이트를 `string`으로
복사하고(cgo는 `C.GoString`, purego는 자체 NUL scan), Rust raw 모듈은 `&'static str`로
빌려 옵니다. 그 `'static`이 계약입니다. 반환 포인터는 프로세스가 사는 동안 유효해야 하고,
comptime에 만든 문자열이 그 조건을 만족합니다.

심볼 이름은 `<prefix>_<플러그인 소문자>_<name>`이므로 바인딩 함수와 절대 부딪히지 않습니다.
심볼이 하나 늘어난다는 것은 ABI가 바뀐다는 뜻이므로, 처음 켤 때 `go-abi-check`나
`rust-abi-check`는 `ADDED: plugin.BUILDINFO.build_info`를 보고합니다.

[Go 연결 예제](../../examples/00-quick-start/build.zig) ·
[Rust 연결 예제](../../examples/13-rust-quick-start/build.zig) ·
[플러그인 사용](../../docs/plugins/README.md) ·
[네이티브 기여 안내](../../docs/plugins/authoring.md) ·
[플러그인 API](../../docs/plugins/api-reference.md)
