# satisfies

생성된 Go 타입이 지정한 interface를 만족한다는 컴파일 시점 assertion을 타입 옆에 씁니다.
Go에는 "이 타입은 이 interface를 구현한다"를 선언하는 문법이 없으므로,
`var _ io.ReadWriteCloser = (*Document)(nil)` 한 줄이 그 역할을 합니다. 메서드 모양이 바뀌는
날 소비자의 빌드가 아니라 이 패키지의 빌드가 먼저 실패합니다.

claim은 assertion을 쓰기 전에 검사합니다. 표준 interface는 플러그인이 아는 이름이어야 하고,
claim한 method set은 handle의 생성 메서드가 모두 채워야 합니다. `go build`까지 내려가는 것은
generator가 판단할 수 없는 것뿐입니다.

```zig
const satisfies = @import("zigo_satisfies");

// 표준 interface는 이름으로, 바인딩이 선언한 interface는 참조로 적습니다.
const Counter = zigo.interface(.{
    .name = "Counter",
    .methods = &.{"count"},
    .types = &.{ document.typeRef(), Sink.typeRef() },
});
const Document = document.use(satisfies.plugin, .{
    .interfaces = &.{"io.ReadWriteCloser"},
    .generated = &.{.{ .entry = Counter }},
}).context();
```

```go
// 생성 파일에 함께 실리는 assertion
var _ io.ReadWriteCloser = (*Document)(nil)
var _ Counter = (*Document)(nil)
```

## 옵션

| 옵션 | 기본값 | 의미 |
|---|---|---|
| `interfaces` | `&.{}` | Go 표준 라이브러리 interface 이름. 플러그인이 아는 이름만 받습니다 |
| `generated` | `&.{}` | 바인딩이 `zigo.interface(...)`로 선언한 interface 참조. `.{ .entry = Counter }` 또는 `.{ .name = "Counter" }` |
| `form` | `.pointer` | assertion이 검사할 method set. `.pointer`는 `(*T)(nil)`, `.value`는 `*new(T)` |

두 목록을 하나의 union 목록으로 합치지 않은 이유는 authoring 매핑입니다. 참조 field의
`.{ .entry = ... }` 표기는 union field 안에서는 쓸 수 없고, 문자열 하나로 실리는
`interfaces`의 wire 형태는 기존 문서와 그대로 같습니다.

wire 형태는 다음과 같습니다.

```json
{ "SATIS": { "interfaces": ["io.ReadWriteCloser"], "generated": ["Counter"] } }
```

## 아는 표준 interface

`error`, `fmt.Stringer`, `fmt.GoStringer`,
`io.Reader`, `io.Writer`, `io.Closer`, `io.ReadWriter`, `io.ReadCloser`, `io.WriteCloser`,
`io.ReadWriteCloser`, `io.ReaderFrom`, `io.WriterTo`, `io.StringWriter`, `io.ByteReader`,
`io.ByteWriter`, `io.RuneReader`, `io.Seeker`,
`encoding.TextMarshaler`, `encoding.TextUnmarshaler`, `encoding.BinaryMarshaler`,
`encoding.BinaryUnmarshaler`, `json.Marshaler`, `json.Unmarshaler`, `sort.Interface`.

목록에 없는 이름은 `SATIS003`입니다. 바인딩이 선언한 interface라면 `generated`에 참조로
적고, 그 밖의 표준 interface가 필요하면 `src/plugin.zig`의 `standard_interfaces` 표에
method set과 함께 추가하세요.

## 진단

| 코드 | 언제 |
|---|---|
| `SATIS002` | `generated` 참조가 가리키는 interface 선언이 없음 (core 검증) |
| `SATIS003` | 플러그인이 모르는 표준 interface 이름 |
| `SATIS004` | claim한 interface의 method를 handle이 같은 이름·시그니처로 갖고 있지 않음 |

method set 검사는 handle(opaque) 타입에만 적용합니다. enum이나 value 타입은 공개 패키지에서
메서드를 직접 써서 interface를 만족시킬 수 있어서(`fmt.Stringer`가 보통 그렇습니다) 생성
메서드가 없다는 사실이 아무것도 증명하지 못합니다. 그런 claim은 assertion이 그대로 검사합니다.

빌드에는 다른 플러그인처럼 등록합니다.

```zig
const satisfies: zigo.PluginModule = .{
    .name = "zigo_satisfies",
    .root_source_file = b.dependency("zigo_satisfies", .{}).path("src/plugin.zig"),
};
// addGoBindings 옵션: .plugins = &.{satisfies}
```

`build.zig.zon`에 이 패키지를 `zigo_satisfies` 의존성으로 추가하세요.
[연결 예제](../../examples/11-io-streams/build.zig) ·
[플러그인 사용](../../docs/plugins/README.md) ·
[플러그인 API](../../docs/plugins/api-reference.md)

생성 Go 코드만 추가하므로 C ABI는 변경되지 않고 cgo와 purego에서 동일하게 동작합니다.
