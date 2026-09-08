# 생성기 플러그인

플러그인은 공개 Go 패키지에 메서드·타입·파일을 추가하는 Zig 모듈입니다. 내장 Must,
Iterator, Implements, Interfaces도 공개 계약만 사용하는 별도 모듈로 컴파일됩니다.
현재 hook은 shim·C 헤더·raw 패키지를 수정하지 않습니다.

## 계약과 실행 순서

루트 소스에서 `pub const plugin: @import("plugin").Plugin`을 선언합니다.
공개 모듈은 `plugin`, `abi`, `semantic`, `diagnostic`, `naming`이며 계약의 정본은
[`src/plugin.zig`](../src/plugin.zig)입니다. 이 모듈들이 노출하는 타입도 계약에 포함됩니다.

`plugin.contract_version`은 `{ major, minor }`입니다. `Plugin.min_contract`의 major는
동일해야 하고 minor는 생성기가 지원하는 값 이하여야 합니다. 현재 계약은 **1.0**입니다.
이전의 `validateAll`, 구형 `validate`, optional writer 슬롯과 `go_must_variants`는 제거됐습니다.

```zig
const api = @import("plugin");
pub const plugin: api.Plugin = .{
    .name = "EXAMPLE",
    .min_contract = .{ .major = 1, .minor = 0 },
    .Config = struct { enabled: bool = true },
    .FunctionOptions = struct {},
    .TypeOptions = struct {},
    .Facts = struct { eligible: bool },
    .after = &.{"MUST"},
    // .validate = validate,
    // .analyze = analyze,
    // .method_hook = methodHook,
};
```

실행 순서는 core 검증 → 플러그인 검증 → lowering → 플러그인 분석 → 공개 패키지 렌더링입니다.
`after`는 등록된 플러그인 사이의 순서를 정하고, 없는 이름은 무시합니다. `requires`는
등록과 활성화가 모두 필요한 의존성이며 실행 순서도 보장합니다. 나머지 순서는 등록 순서를
유지합니다. 이름 중복·계약 불일치·의존성 누락·순환은 컴파일 오류입니다.

## 빌드 설정과 선언 옵션

`Config`는 빌드 전체 설정이고, `FunctionOptions`·`TypeOptions`는 선언에 붙는 설정입니다.
세 타입은 JSON으로 표현 가능한 struct입니다. 빌드와 생성기는 별도 프로그램이므로 설정은
JSON으로 전달하고 생성기에서 등록된 플러그인의 `Config` 타입으로 검사합니다.

```zig
const plugins = [_]zigo.PluginModule{.{
    .name = "example", // bindings.zig에서 import하는 이름
    .root_source_file = b.path("plugins/example.zig"),
    .config = zigo.configJson(b, .{ .enabled = true }),
}};
_ = zigo.addGoBindings(b, .{
    // ...
    .plugins = &plugins,
    .plugin_config = zigo.configJson(b, .{ .MUST = .{ .enabled = true } }),
});
```

`plugin_config`는 등록 이름(`Plugin.name`)을 키로 하는 객체이며 각 항목의 `.config`를
덮어씁니다. 지정되지 않은 필드는 `Config`의 기본값을 사용합니다. CLI에서는
`--plugin-config '{"MUST":{"enabled":true}}'`로 같은 설정을 전달합니다.
알 수 없는 설정 필드·잘못된 값은 `<NAME>001` 진단입니다.

선언에는 `.use(plugin, options)`로 붙입니다. 선언 종류는 `targets`와 대조하고 옵션은
comptime에 타입 검사합니다. 같은 플러그인을 두 번 붙일 수 없으며
`.replacePlugin(plugin, options)`로 교체할 수 있습니다.

```zig
api.enumeration("Mode", .{}).use(satisfies.plugin, .{
    .interfaces = &.{"fmt.Stringer"},
    .form = .value,
})
```

reflection은 `semantic.json`의 `ext`에 등록 이름과 옵션을 기록합니다. callback과
materialized 선언도 옵션을 전달합니다. 렌더 hook은 `context.functionOptions(plugin, fn)`
또는 `context.typeOptions(plugin, declaration)`으로 읽습니다. 반환값 null은 해당 선언에
옵션이 붙지 않았다는 뜻입니다. 빌드 설정은 `try context.config(plugin)`으로 읽습니다.

## 검증과 분석 결과

검증 함수의 시그니처는 `fn(api.ValidateContext) !void`입니다. 컨텍스트에는 `allocator`,
`document`, `configurations`, `facts`, `diagnostics`가 있습니다.

```zig
fn validate(context: api.ValidateContext) !void {
    for (context.document.functions) |function| {
        // 옵션 타입을 알고 있는 다른 플러그인의 옵션도 읽을 수 있습니다.
        const options = try context.optionsOf(plugin, .function, function.ext) orelse continue;
        _ = options;
        try context.diagnose(.{
            .severity = .@"error",
            .code = "EXAMPLE002",
            .message = "설명",
            .site = api.site.functionSite(function),
            .hint = "수정 방법",
        });
    }
}
```

`diagnose`를 여러 번 호출해 독립적인 진단을 모읍니다. `api.site.functionSiteFor`와
`functionDeclarationAlloc`은 소스 위치와 receiver를 포함한 선언 경로를 만들고,
`api.interfaces`는 인터페이스 선언 규칙과 메서드 조회를 제공합니다.

`analyze: fn(api.AnalyzeContext) !void`는 lowering 뒤, 패키지 분할과 helper 탐색 전에
생성 실행당 한 번 호출됩니다. `context.render`에는 읽기 전용 프로그램과 공개 writer가
있고, `context.facts`에는 검증 단계와 같은 저장소가 있습니다.

```zig
try context.facts.put(context.render.allocator, plugin,
    api.DeclarationId.function(function.origin.*), .{ .eligible = true });
// 렌더링 단계:
const fact = try context.options.facts.get(plugin,
    api.DeclarationId.function(function.origin.*));
```

`Plugin.Facts`로 타입을 지정합니다. 키는 플러그인 이름과 선언 ID입니다. 함수 ID는 이름,
receiver, namespace, package로 구성되어 lowering이 함수를 복사해도 유지됩니다. 원본
`symbol`은 재계산되는 입력일 수 있어 ID로 쓰지 않습니다. 문서 전체 사실은
`.{ .kind = .document, .name = "" }`, 타입 사실은 `DeclarationId.declaration(type)`을
사용합니다. 동일 키에 두 번 쓰면 오류입니다. 분석이 새로 만드는 사실은 별도 선언 ID를
사용하거나 검증에서 저장한 사실을 그대로 읽습니다.

키·값·내부 할당은 생성 실행의 arena 수명을 따릅니다. 포인터를 다음 생성 실행까지
보관하면 안 됩니다. 렌더 컨텍스트의 저장소는 `*const Facts`이므로 렌더링은 사실을 읽기만
합니다. Must는 이 저장소에 생성 여부를 기록하고 Interfaces가 같은 결과를 읽습니다.

## 공개 writer

writer 슬롯은 모두 필수이며 생성기가 제공하는 테이블을 사용합니다.

```zig
try context.writeTypeName(writer, "Document");
try context.writeGoType(writer, node);
try context.writeSignature(writer, function);
try context.writeSignatureWith(writer, function, .{ .parameter_names = false });
try context.writeParameters(writer, function);
const count = try context.writeResultType(writer, function, .{ .omit_error = true });
try context.writeCallArguments(writer, function);
try context.writeValueType(writer, function); // optional의 bool/error를 제외한 값 타입
```

메서드 hook 밖에서도 이름을 계산하므로 파일·분석 컨텍스트에서도 쓸 수 있습니다.
`writeResultType`은 앞 공백과 tuple 괄호를 포함하고 결과 개수를 반환합니다. 생성자,
borrowed 결과, optional의 bool, adapter, 분할 패키지 한정자를 생성기와 동일하게 처리합니다.
`functionInfo`는 공개 이름·공개 노출 여부·error 반환 여부를 조회합니다. 반환한 `go_name`은
컨텍스트 allocator에 할당되며 호출자가 소유합니다. `writeDoc`은 생성기의 GoDoc 규칙을 씁니다.

## 렌더 hook

모든 렌더 hook은 결정적이어야 합니다. helper 탐색이 같은 패키지를 반복 렌더링하므로,
외부 작업을 수행하거나 호출 횟수에 따라 출력·분석 상태를 바꾸면 안 됩니다.

| hook | 호출 위치 |
|---|---|
| `method_hook(Context, writer, AbiFn)` | 각 공개 함수·메서드 뒤 |
| `type_hook(Context, writer, TypeDecl)` | 생성된 handle·value·enum·tagged union·callback·materialized 타입 뒤 |
| `file_hook(Context, writer, FileInfo, FilePhase)` | 공개 파일 본문 시작과 끝 (`begin`, `end`) |
| `package_hook(Context, writer)` | 패키지별 `zigo_plugins_gen.go` 본문에 한 번씩, 각 렌더 pass마다 |

error-set 선언의 type hook은 해당 패키지의 오류 파일에서 실행합니다. 오류 집합은 공통
`Error` 표현을 사용하므로 선언 이름과 같은 Go 타입이 존재한다고 가정하면 안 됩니다.
이름 없이 파생된 callback도 합성 `TypeDecl`을 받으며 그 선언에는 `ext`가 없습니다.
사용되지 않아 생성되지 않는 callback·materialized 타입에는 type hook을 호출하지 않습니다.

`FileInfo`에는 출력 루트 기준 `path`, `owner`, `kind`가 있습니다. kind는 `api`, `enums`,
`structs`, `handles`, `runtime`, `errors`, `tagged_union`, `plugin`, `package`입니다.
파일 hook은 package/import 바깥이 아닌 **본문**에 씁니다. `var`, `init()` 등을 추가할 수
있으며 hook이 쓴 한정자도 import 분석에 포함됩니다. raw·shim·헤더·내부 lifecycle 파일에는
호출되지 않습니다. `active_package`는 분할 패키지 선택값이고 null은 단일 패키지,
빈 문자열은 분할된 기본 패키지입니다.

## 추가 파일과 import

```zig
pub const plugin: api.Plugin = .{
    .name = "HELPERS",
    .files = &.{.{ .pathAlloc = path, .render = render }},
};
fn path(context: api.Context) ![]u8 {
    return context.publicFilePathAlloc("zigo_helpers_gen.go");
}
fn render(_: api.Context, writer: *std.Io.Writer) !void {
    try writer.writeAll("const HelperVersion = 1\\n");
}
```

`File`은 본문만 작성합니다. 생성 표식·package·import는 생성기가 관리하고 비어 있는 파일은
제거합니다. 모든 경로는 쓰기 전에 정규화·충돌 검사하며 잘못된 경로나 중복은 `ZIGO059`입니다.
경로는 생성 출력 루트 기준이며 `publicFilePathAlloc`을 쓰면 활성 공개 패키지 아래로 갑니다.

추가 import는 `.imports = &.{.{ .qualifier = "json", .path = "encoding/json" }}`처럼
선언합니다. 본문에서 실제로 사용하는 한정자만 import에 들어갑니다.

## 테스트와 이전

이전 플러그인은 validator를 `ValidateContext`와 `diagnose`로 바꾸고, 파일 콜백을
`Context` 기반으로 바꿔야 합니다. Must 설정은 `plugin_config.MUST.enabled`로 옮깁니다.
구형 writer 테이블을 직접 만든 코드는 모든 슬롯을 구현해야 합니다.

[`tests/plugin_contract.zig`](../tests/plugin_contract.zig)는 별도 외부 모듈로 설정 전달,
검증→분석 사실 전달, 반복 렌더링, 타입·파일·패키지 hook과 cgo/purego의 ABI 불변을 검사합니다.
내장 모듈은 생성기 내부를 import할 수 없는 모듈 루트에서 컴파일합니다. golden case는
추가 hook을 켜지 않은 생성 결과를 비교합니다.

예제: [satisfies](../plugins/satisfies), [JSON](../plugins/json), [enumkit](../plugins/enumkit),
[wrapper writer](../tests/plugins/wrappers.zig).
