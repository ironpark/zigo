# 생성기 플러그인

플러그인은 core 바인딩 계약을 검증·변형하거나 생성 공개 Go 패키지에 코드와 파일을
추가합니다. 일반 바인딩 작성과 분리된 확장 지점이며, 현재 계약 version은 3.0입니다.

## 언제 플러그인을 사용하나요?

다음 요구가 여러 바인딩에서 반복될 때 플러그인이 적합합니다.

- 열거형이나 value 타입에 공통 Go 메서드 추가
- project naming 또는 Go 타입 어댑터 정책 적용
- 바인딩 선언에 project-specific 검증 추가
- 패키지별 Go file 또는 문서·schema 산출물 생성
- semantic model을 lowering 전에 일관되게 변형

한 패키지에서만 필요한 작은 도우미는 생성 패키지의 사용자 `.go` 파일에 직접 작성하는 편이
단순합니다. C shim이나 raw ABI를 임의로 바꾸는 플러그인 hook은 제공하지 않습니다.

## 사용하는 쪽의 연결

`build.zig`에서 플러그인 소스를 generator에 등록합니다.

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

`name`은 `bindings.zig`에서 플러그인 패키지를 import할 이름입니다.

```zig
const enumkit = @import("zigo_enumkit");

api.enumType("Mode", .{})
    .use(enumkit.plugin, .{})
```

`.use`는 함수 또는 타입 entry에 typed 옵션을 붙입니다. 같은 플러그인을 한 entry에 두 번
붙이면 컴파일 error입니다. 의도적인 교체에는 `.replacePlugin`을 사용합니다.

## bundled enumkit

저장소의 `plugins/enumkit`은 독립 플러그인의 기준 예제입니다.

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

전체 연결은 [10-tagged-union](../../examples/10-tagged-union/README.md), 플러그인 패키지 사용법은
[enumkit README](../../plugins/enumkit/README.md)를 참고하세요.

## 문서 구성

- [Plugin 작성](authoring.md) — 최소 플러그인부터 빌드와 테스트까지
- [Plugin API 참조](api-reference.md) — hook, context, 출력과 실행 순서

플러그인은 generator와 함께 컴파일되므로 계약 major가 맞지 않으면 빌드 그래프 생성 중
거부됩니다. minor version은 기능 추가이며 플러그인의 `min_contract`보다 현재 generator가
낮아도 거부됩니다.
