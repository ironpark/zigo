# 생성기 플러그인

플러그인은 core 바인딩 계약을 검증·변형하거나 생성 공개 패키지에 코드와 파일을
추가합니다. 일반 바인딩 작성과 분리된 확장 지점이며, 현재 계약 version은 6.0입니다.
출력 언어는 플러그인이 채운 렌더링 slot(`go`, `rust`)이 정합니다.

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

api.enumeration("Mode", .{})
    .use(enumkit.plugin, .{})
```

`.use`는 함수 또는 타입 entry에 typed 옵션을 붙입니다. 첫 인자는 `zigo.Plugin` 값이어야
하며(플러그인 패키지가 export하는 `plugin`, 또는 `zigo.features.*`), 다른 타입을 넘기면 컴파일
error입니다. 같은 플러그인을 한 entry에 두 번 붙이면 컴파일 error이고, 의도적인 교체에는
`.replacePlugin`을 사용합니다.

플러그인 패키지 자체는 `cd plugins/<name> && zig build test`로 단위 테스트를 실행합니다.
`zigo` 의존성이 `plugin`, `semantic`, `abi`, `diagnostic` 모듈을 이름으로 공개하므로 플러그인의
`build.zig`는 generator가 쓰는 것과 같은 계약 모듈에 대해 컴파일됩니다.

## 동봉 플러그인

| 플러그인 | 렌더링 slot | 하는 일 |
|---|---|---|
| `plugins/enumkit` | `go`, `rust` | enum 값 목록과 알려진 tag 판별 |
| `plugins/json` | `go` | value 타입의 `MarshalJSON`/`UnmarshalJSON` |
| `plugins/satisfies` | `go` | 생성 타입이 지정한 interface를 만족하는지 컴파일 타임 단언 |

## bundled enumkit

저장소의 `plugins/enumkit`은 독립 플러그인의 기준 예제이자, 한 플러그인이 두 출력 언어를
렌더링하는 기준 예제입니다.

```zig
api.enumeration("Mode", .{})
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

같은 attachment가 Rust target에서는 crate의 enum 옆 `impl` block으로 나옵니다.

```rust
impl crate::Mode {
    pub fn values() -> &'static [Self] { /* 선언 순서 */ }
    pub fn is_known(self) -> bool { /* 닫힌 enum은 언제나 true */ }
}
```

전체 연결은 Go 쪽 [10-tagged-union](../../examples/10-tagged-union/README.md)과 Rust 쪽
[13-rust-quick-start](../../examples/13-rust-quick-start/README.md), 플러그인 패키지 사용법은
[enumkit README](../../plugins/enumkit/README.md)를 참고하세요.

## 내장 플러그인도 같은 계약을 씁니다

`MUST`, `ITERATOR`, `IMPLEMENTS`, `INTERFACES`, `SESSION`은 generator 안에 있을 뿐, 외부
플러그인이 쓸 수 없는 통로는 하나도 쓰지 않습니다. 옵션은 선언의 `ext`에 실려 오고
(`use(zigo.features.iterator, ...)`), hook은 `GoContext`가 주는 것만 읽으며, 출력은 builder로
씁니다. core 규칙이 내장 플러그인의 옵션을 볼 때도 계약의 reader
(`plugin.builtins.iterator.read`, `plugin.builtins.implements.read`)를 그대로 씁니다.

그래서 `src/gen/plugins/`의 소스가 곧 참조 구현입니다.

| 파일 | 보여 주는 것 |
|---|---|
| `src/gen/plugins/iterator.zig` | function node 방문, 옵션 검증, builder로 메서드 추가 |
| `src/gen/plugins/implements.zig` | 한 플러그인이 function·type·file 경계를 모두 쓰는 법, `claims`로 공개 메서드 대체 |
| `src/gen/plugins/must.zig` | `analyze`에서 `Facts`를 만들고 렌더링에서 읽는 법 |
| `src/gen/plugins/session.zig` | 여러 선언을 묶어 새 Go 타입을 만드는 법 |

## 문서 구성

- [Plugin 작성](authoring.md) — 최소 플러그인부터 빌드와 테스트까지
- [Plugin API 참조](api-reference.md) — `visit` node, context, 출력과 실행 순서

플러그인은 generator와 함께 컴파일되므로 계약 major가 맞지 않으면 빌드 그래프 생성 중
거부됩니다. minor version은 기능 추가이며 플러그인의 `min_contract`보다 현재 generator가
낮아도 거부됩니다.
