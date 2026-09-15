# json

생성된 value 타입과 enum에 `MarshalJSON`/`UnmarshalJSON`을 추가합니다. `go` 렌더링 slot만
채웁니다.

```zig
const json = @import("zigo_json");

api.value("RGB", .{}).use(json.plugin, .{ .field_names = .zig }),
api.enumeration("Mode", .{}).use(json.plugin, .{}),
```

```go
encoded, _ := json.Marshal(RGB{R: 1, G: 2, B: 3}) // {"r":1,"g":2,"b":3}
encoded, _ = json.Marshal(ModePaused)              // "paused"
```

- `field_names` (기본 `.zig`): struct key의 표기입니다. `.zig`는 Zig field 이름을, `.go`는 공개
  Go field 이름을 씁니다. 공개 struct는 그대로 두고 wire struct에만 tag가 실리므로 다른 생성
  변환이 읽는 모습은 달라지지 않습니다.
- enum은 이 옵션을 무시합니다. enum은 Zig tag 이름 하나로만 오갑니다.
- value struct와 enum이 아닌 선언에 붙이면 `JSON002` 진단을 냅니다.

## 알려지지 않은 tag 판별은 한 곳에서

`UnmarshalJSON`은 이름이 tag가 아니면 `Mode: unknown value "retired"` 형태의 error를 냅니다.
그 "알려진 tag"를 누가 정하느냐가 이 플러그인이 [enumkit](../enumkit/README.md)과 주고받는
유일한 지점입니다.

- enumkit이 없거나 같은 enum에 붙어 있지 않으면 tag 이름을 나열한 `switch`를 씁니다.
- enumkit이 그 enum에 `ModeValues()`와 `IsKnown()`을 모두 썼다면 -- capability
  `plugin.capabilities.enum_known`이 그렇다고 답하면 -- `switch` 대신 그 둘을 돌립니다.

```go
for _, candidate := range ModeValues() {
	if candidate.IsKnown() && candidate.String() == text {
		*value = candidate
		return nil
	}
}
return fmt.Errorf("Mode: unknown value %q", text)
```

여기서 "단일 정본"은 **판별 로직이 `IsKnown()`에만 있다**는 뜻입니다. 이 플러그인은 tag
집합을 다시 적지 않고, 후보 목록과 판정을 모두 enumkit에서 받아옵니다. enumkit의 옵션으로
`values`나 `is_known` 중 하나라도 꺼지면 돌릴 것이 없으므로 `switch`로 되돌아갑니다. 두
플러그인을 같은 enum에 붙이지 않은 바인딩의 출력은 한 바이트도 달라지지 않습니다.

capability의 양쪽을 어떻게 쓰는지는
[Plugin 작성](../../docs/plugins/authoring.md#다른-플러그인의-capability-사용하기)에 있습니다.

빌드에는 다른 플러그인처럼 등록합니다.

```zig
const json: zigo.PluginModule = .{
    .name = "zigo_json",
    .root_source_file = b.dependency("zigo_json", .{}).path("src/plugin.zig"),
};
// addGoBindings 옵션: .plugins = &.{json}
```

`build.zig.zon`에 이 패키지를 `zigo_json` 의존성으로 추가하세요.
[연결 예제](../../examples/10-tagged-union/build.zig) ·
[플러그인 사용](../../docs/plugins/README.md) ·
[플러그인 API](../../docs/plugins/api-reference.md)

생성 Go 코드만 추가하므로 C ABI는 변경되지 않고 cgo·purego에서 동일하게 동작합니다.
