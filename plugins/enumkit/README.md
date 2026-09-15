# enumkit

생성된 enum에 값 목록과 알려진 tag 판별을 추가합니다. `go`와 `rust` 렌더링 slot을 모두
채우므로 attachment 하나가 두 출력 언어에 각각의 표기로 나옵니다.

```zig
const enumkit = @import("zigo_enumkit");

api.enumeration("Mode", .{}).use(enumkit.plugin, .{}),
```

```go
for _, mode := range ModeValues() {
    fmt.Println(mode)
}
known := Mode(255).IsKnown()
```

```rust
for mode in Mode::values() {
    println!("{mode:?}");
}
let known = Mode::try_from(255).map(|mode| mode.is_known());
```

- `values` (기본 `true`): `ModeValues() []Mode`를 생성합니다. 공개된 tag의 선언 순서를 유지하며 매번 새 slice를 반환합니다.
- `is_known` (기본 `true`): `IsKnown() bool`을 생성합니다. 열린 enum에서도 알려지지 않은 숫자는 `false`입니다. native 호출 가능 여부를 검사하는 메서드는 아닙니다.
- 두 옵션은 독립적으로 끌 수 있습니다. 별도 attachment가 없는 타입에는 생성하지 않습니다.
- Go adapter가 지정된 enum은 지원하지 않으며 `ENUMKIT002` 진단을 냅니다.
- `.text = true` 및 JSON 플러그인과 함께 사용할 수 있습니다. 생성될 `<Type>Values`와 `IsKnown` 이름은 사용자 선언에서 비워 두세요.

## 다른 플러그인에 알리는 것

이 플러그인은 붙은 enum마다 capability `plugin.capabilities.enum_known`으로 fact 하나를
남깁니다. 실리는 것은 `is_known`과 `values`, 즉 두 도우미가 실제로 쓰였는지 뿐이고, 이름은
capability의 규약(`<Type>Values()`와 `<Type>.IsKnown()`)이므로 읽는 쪽이 그대로 씁니다.

[json 플러그인](../json/README.md)이 그 소비자입니다. 한 enum에 두 플러그인을 모두 붙이면
json의 `UnmarshalJSON`이 자기 tag 목록 대신 이 플러그인이 쓴 두 도우미로 tag 이름을
해석하므로, "알려진 tag"를 정하는 코드는 `IsKnown()` 하나만 남습니다. 옵션으로 `values`나
`is_known`을 끄면 json은 예전의 `switch`로 되돌아갑니다.

## Rust 출력

같은 옵션이 crate의 enum 옆 `impl` block 하나로 나옵니다. 두 옵션을 모두 끄면 block 자체를
쓰지 않습니다.

```rust
impl crate::Mode {
    /// The known values, in declaration order.
    pub fn values() -> &'static [Self] {
        &[Self::Fast, Self::Slow]
    }

    pub fn is_known(self) -> bool {
        true
    }
}
```

- `values`: 선언 순서의 `&'static [Self]`입니다. 값이 불변이므로 Go처럼 매번 복사하지 않습니다.
- `is_known`: 닫힌 enum은 알 수 없는 값을 표현할 수 없으므로 상수 `true`입니다. 열린 enum은
  `#[repr(transparent)]` newtype이라 tag를 검사합니다. 값이 연속이면 `(min..=max).contains(&self.0)`,
  구멍이 있으면 `matches!(self.0, ..)`입니다.
- `Display`와 `FromStr`은 쓰지 않습니다. `.text = true`인 enum에는 Rust emitter가 이미 둘 다
  쓰고 있으며, 이는 Go 쪽 `String`/`Parse<Enum>`과 같은 조건입니다.

빌드에는 다른 플러그인처럼 등록합니다.

```zig
const enumkit: zigo.PluginModule = .{
    .name = "zigo_enumkit",
    .root_source_file = b.dependency("zigo_enumkit", .{}).path("src/plugin.zig"),
};
// addGoBindings 또는 addRustBindings 옵션: .plugins = &.{enumkit}
```

`build.zig.zon`에 이 패키지를 `zigo_enumkit` 의존성으로 추가하세요.
[Go 연결 예제](../../examples/10-tagged-union/build.zig) ·
[Rust 연결 예제](../../examples/13-rust-quick-start/build.zig) ·
[플러그인 사용](../../docs/plugins/README.md) ·
[플러그인 API](../../docs/plugins/api-reference.md)

생성 언어의 코드만 추가하므로 C ABI는 변경되지 않고 cgo·purego·Rust에서 동일하게 동작합니다.
