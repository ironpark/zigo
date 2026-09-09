# Generator plugin

plugin은 core binding contract를 검증·변형하거나 생성 public Go package에 코드와 파일을
추가합니다. 일반 바인딩 작성과 분리된 확장 지점이며, 현재 contract version은 2.0입니다.

## 언제 plugin을 사용하나요?

다음 요구가 여러 binding에서 반복될 때 plugin이 적합합니다.

- enum이나 value type에 공통 Go method 추가
- project naming 또는 Go type adapter 정책 적용
- binding declaration에 project-specific validation 추가
- package별 Go file 또는 문서·schema artifact 생성
- semantic model을 lowering 전에 일관되게 변형

한 package에서만 필요한 작은 helper는 생성 package의 사용자 `.go` 파일에 직접 작성하는 편이
단순합니다. C shim이나 raw ABI를 임의로 바꾸는 plugin hook은 제공하지 않습니다.

## 사용하는 쪽의 연결

`build.zig`에서 plugin source를 generator에 등록합니다.

```zig
const enumkit: zigo.PluginModule = .{
    .name = "zigo_enumkit",
    .root_source_file = b.dependency("zigo_enumkit", .{}).path("src/plugin.zig"),
};

const bindings = zigo.addGoBindings(b, .{
    // ...
    .plugins = &.{enumkit},
});
```

`name`은 `bindings.zig`에서 plugin package를 import할 이름입니다.

```zig
const enumkit = @import("zigo_enumkit");

api.enumType("Mode", .{})
    .use(enumkit.plugin, .{})
```

`.use`는 function 또는 type entry에 typed option을 붙입니다. 같은 plugin을 한 entry에 두 번
붙이면 compile error입니다. 의도적인 교체에는 `.replacePlugin`을 사용합니다.

## bundled enumkit

저장소의 `plugins/enumkit`은 독립 plugin의 기준 예제입니다.

```zig
api.enumType("Mode", .{})
    .use(enumkit.plugin, .{
        .values = true,
        .is_known = true,
    })
```

생성 Go API:

```text
func ModeValues() []Mode
func (value Mode) IsKnown() bool
```

전체 연결은 [10-tagged-union](../../examples/10-tagged-union/README.md), plugin package 사용법은
[enumkit README](../../plugins/enumkit/README.md)를 참고하세요.

## 문서 구성

- [Plugin 작성](authoring.md) — 최소 plugin부터 build와 test까지
- [Plugin API 참조](api-reference.md) — hook, context, output과 실행 순서

plugin은 generator와 함께 compile되므로 contract major가 맞지 않으면 build graph 생성 중
거부됩니다. minor version은 capability 추가이며 plugin의 `min_contract`보다 현재 generator가
낮아도 거부됩니다.
