# enumkit

생성된 Go enum에 값 목록과 알려진 tag 판별을 추가합니다.

```zig
const enumkit = @import("zigo_enumkit");

api.enumType("Mode", .{}).use(enumkit.plugin, .{}),
```

```go
for _, mode := range ModeValues() {
    fmt.Println(mode)
}
known := Mode(255).IsKnown()
```

- `values` (기본 `true`): `ModeValues() []Mode`를 생성합니다. 공개된 tag의 선언 순서를 유지하며 매번 새 slice를 반환합니다.
- `is_known` (기본 `true`): `IsKnown() bool`을 생성합니다. 열린 enum에서도 알려지지 않은 숫자는 `false`입니다. native 호출 가능 여부를 검사하는 메서드는 아닙니다.
- 두 옵션은 독립적으로 끌 수 있습니다. 별도 attachment가 없는 타입에는 생성하지 않습니다.
- Go adapter가 지정된 enum은 지원하지 않으며 `ENUMKIT002` 진단을 냅니다.
- `features.text` 및 JSON 플러그인과 함께 사용할 수 있습니다. 생성될 `<Type>Values`와 `IsKnown` 이름은 사용자 선언에서 비워 두세요.

빌드에는 다른 플러그인처럼 등록합니다.

```zig
const enumkit: zigo.PluginModule = .{
    .name = "zigo_enumkit",
    .root_source_file = b.dependency("zigo_enumkit", .{}).path("src/plugin.zig"),
};
// addGoBindings 옵션: .plugins = &.{enumkit}
```

`build.zig.zon`에 이 패키지를 `zigo_enumkit` 의존성으로 추가하세요.
[실제 연결 예제](../../examples/10-tagged-union/build.zig) ·
[플러그인 사용](../../docs/plugins/README.md) ·
[플러그인 API](../../docs/plugins/api-reference.md)

Go 코드만 추가하므로 C ABI는 변경되지 않고 cgo·purego에서 동일하게 동작합니다.
