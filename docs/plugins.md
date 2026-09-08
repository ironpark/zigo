# 생성기 플러그인

플러그인은 semantic IR을 변형하고 Go 타입·이름을 지정하며 공개 패키지에 코드를 추가하는 Zig 모듈입니다. 내장 Must,
Iterator, Implements, Interfaces도 공개 계약만 사용하는 별도 모듈로 컴파일됩니다.
렌더링 hook은 shim·C 헤더·raw 패키지를 수정하지 않습니다. IR 변형과 타입 이름 변경은
생성 ABI를 바꿀 수 있으며, 변형된 문서 전체를 검증한 뒤 lowering합니다.

## 계약과 실행 순서

루트 소스에서 `pub const plugin: @import("plugin").Plugin`을 선언합니다.
공개 모듈은 `plugin`, `abi`, `semantic`, `diagnostic`, `naming`이며 계약의 정본은
[`src/plugin.zig`](../src/plugin.zig)입니다. 이 모듈들이 노출하는 타입도 계약에 포함됩니다.

`plugin.contract_version`은 `{ major, minor }`입니다. `Plugin.min_contract`의 major는
동일해야 하고 minor는 생성기가 지원하는 값 이하여야 합니다. 현재 계약은 **2.0**입니다.
이전의 `validateAll`, 구형 `validate`, optional writer 슬롯과 `go_must_variants`는 제거됐습니다.

```zig
const api = @import("plugin");
pub const plugin: api.Plugin = .{
    .name = "EXAMPLE",
    .min_contract = .{ .major = 2, .minor = 0 },
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

실행 순서는 설정·의존성 검사 → 모든 `transform` → 모든 `name_type` → 각 플러그인의
`map_type`·`name_function` → core 검증 → 플러그인 검증 → stream 확장 → lowering →
플러그인 분석 → 공개 패키지 렌더링입니다. 각 단계 안에서는 아래 의존성 순서를 적용합니다.
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

## 문서 변형, 타입 매핑과 이름 정책

문서 변형에는 다음 네 콜백을 사용합니다. 모두 한 번 실행되고 결과는 run allocator로
할당하거나 정적 문자열을 사용합니다. 콜백이 받은 문서와 슬라이스는 입력 스냅샷입니다.
직접 `@constCast`해서 수정하지 말고 바뀔 배열·노드만 복사하여 반환하세요.

```zig
.transform: ?fn(api.TransformContext) anyerror!semantic.Semantic
.name_type: ?fn(api.TransformContext, semantic.TypeDecl) anyerror!?[]const u8
.map_type: ?fn(api.TransformContext, api.TypeUse) anyerror!?semantic.GoAdapter
.name_function: ?fn(api.TransformContext, semantic.SemanticFn) anyerror!?[]const u8
```

`TransformContext`에는 `allocator`, `document`, `config(P)`, `optionsOf(P, attachment, ext)`,
`diagnose(issue)`가 있습니다. `transform`은 함수 제거, 문서·이름 수정, 파생 선언 추가 등
문서 전체를 바꿀 수 있습니다. 후속 플러그인은 앞 플러그인이 반환한 문서를 받습니다.
모든 구조 변형이 끝난 뒤 정책을 적용하므로 파생 선언에도 모든 정책이 적용됩니다.
검증에서 저장하는 사실은 이 최종 문서를 기준으로 하며 변형 전 선언의 사실이 남지 않습니다.

함수를 복제하여 파생 wrapper를 만들 때는 `zig_path`를 원래 호출 경로로 지정하세요.
`semantic.zigCallPathAlloc(allocator, original)`로 얻을 수 있습니다. `name`, `symbol`,
`custom_symbol`은 새 선언의 정체성에 맞춰 지정합니다. 생성자가 참조하는 함수를 제거할
때는 `constructors` 등 관련 메타데이터도 갱신해야 합니다. 변형은 존재하지 않는 Zig 구현을
생성하지 않으므로 새 선언의 타입·호출 경로는 실제 native 함수와 맞아야 합니다.

파라미터 순서는 `try context.reorderParameters(function, &.{ 1, 0 })`으로 바꿉니다.
배열의 각 항목은 새 위치에 올 **기존 인덱스**입니다. Go·C 인자 순서는 바뀌지만
`native_index`를 보존하여 shim은 원래 Zig 순서로 호출합니다. 반복 재배치도 합성되며
주입된 allocator·io와 `receiver_at` 위치도 보존됩니다. 배열을 직접 재배치하면 작성자가
`native_index`의 완전한 순열을 유지해야 합니다. 잘못된 순열은 `ZIGO060`입니다.

`map_type`의 대상은 `TypeUse.declaration`, `.parameter { function, index }`, `.result`입니다.
기존 DSL의 `go_adapter`·`return_go_adapter`와 같은 변환 경로를 사용하므로 공개 서명,
입력의 `to_raw`, 출력의 `from_raw`, import가 함께 바뀝니다. 예를 들어 Unix 초 `u64`를
`time.Time`으로 내보내려면 다음 adapter를 반환합니다.

```zig
return .{
    .type = "time.Time", .import = "time",
    .to_raw = "unixTimeToRaw", .from_raw = "unixTimeFromRaw",
};
```

변환 함수는 공개 패키지의 사용자 Go 파일이나 플러그인 파일에서 구현합니다. 지원 범위는
현재 core adapter와 같습니다: 일반 scalar 입력·결과, extern struct value와 enum 선언입니다.
callback·handle·optional 등 지원하지 않는 위치에 adapter를 주면 `ZIGO052`로 거부합니다.
`null`은 기존 매핑 유지, 값은 기존 매핑 대체입니다. 같은 위치에 여러 플러그인이 값을
반환하면 의존성 순서에서 뒤의 값이 적용되므로 `after`·`requires`로 정책 우선순위를 정하세요.

`name_function`은 `HTTPGet`, `ParseURL`처럼 **변환하지 않을 정확한 Go 이름**을 반환합니다.
생성자에도 적용되며 공개 함수, 인터페이스, Must wrapper, 충돌 검사와 보고서가 같은 이름을
사용합니다. 이 정책은 Zig 경로·C 심볼·raw Go 이름을 바꾸지 않습니다. core가 생성하는
`Close`, stream의 `Write` 같은 프로토콜 메서드는 해당 프로토콜의 고정 이름을 유지합니다.

`name_type`은 등록 타입과 core IR의 참조를 한 번에 바꿉니다. 중첩 타입 노드, callback 참조,
함수의 receiver·owner, 생성자, 인터페이스의 구현 타입 목록도 갱신합니다. 원래 `zig_path`와
native root 이름을 보존하므로 shim은 기존 Zig 타입을 찾습니다. **생성 C 타입·심볼 이름은
바뀔 수 있습니다.** 플러그인 소유 `ext`, 문서 문자열, 임의의 Go adapter 코드 안의 이름은
불투명 데이터이므로 자동 변경하지 않습니다. 이런 참조는 해당 플러그인의 변형에서 관리하세요.
공개 `api.rename.types(allocator, document, changes)` 헬퍼도 같은 작업을 제공합니다.

`report --plugin-config <json-object>`는 생성과 같은 준비 단계를 실행합니다.
`generator.prepareDocument`가 반환한 최종 문서는 `Semantic.serialize`로 저장할 수 있습니다.
변형된 ABI를 비교하려면 이렇게 저장한 두 문서를 `abi-diff`에 넘기세요. `abi-diff`는 입력
스냅샷 자체를 비교하며 현재 설치된 플러그인 변형을 다시 적용하지 않습니다.

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
있으며 hook이 쓴 한정자도 import 분석에 포함됩니다. 테스트·문서 단위 Go 파일·raw·shim·헤더·내부 lifecycle 파일에는
호출되지 않습니다. `active_package`는 분할 패키지 선택값이고 null은 단일 패키지,
빈 문자열은 분할된 기본 패키지입니다.

## Go 파일과 범용 산출물

계약 2.0은 `Plugin.files`와 `File`을 제거하고 `go_files: []const GoFile`과
`artifacts: []const Artifact`로 분리합니다.

| 계약 | 생성기 처리 | 기본 실행 범위 |
|---|---|---|
| `GoFile` | build constraint·생성 표식·package·import를 붙이고 Go 본문 출력 | `.package` |
| `Artifact` | 작성한 바이트 그대로 출력 | `.document` |

`scope = .document`는 모든 패키지를 포함한 lowered program으로 한 번 실행됩니다.
`scope = .package`는 공개 패키지마다 실행되고 `program.functions`에는 해당 패키지의 함수만
있습니다. 타입을 포함한 공유 ABI 테이블은 전체 program을 유지합니다. 분할 패키지에서는
`options.active_package`가 기본 패키지는 빈 문자열, 하위 패키지는 그 이름입니다.
문서 단위 Go 파일의 `.package = .public`은 기본 공개 패키지에 출력합니다.

### Go 파일

```zig
pub const plugin: api.Plugin = .{
    .name = "HELPERS",
    .go_files = &.{.{ .pathAlloc = path, .render = render }},
};
fn path(context: api.Context) ![]u8 {
    return context.goFilePathAlloc("zigo_helpers_gen.go");
}
fn render(_: api.Context, writer: *std.Io.Writer) !void {
    try writer.writeAll("const HelperVersion = 1\n");
}
```

`GoFile.package`는 `.public`, `.external_test`, `.raw`입니다. `.external_test`는 현재
공개 패키지명에 `_test`를 붙입니다. `.raw`는 `raw_package_name`과 `raw_package_path`를
따르며 **`.scope = .document`가 필수**입니다. 다른 파일과의 패키지 일관성을 위해 경로는
선택한 패키지 디렉터리 안에 있어야 합니다. `context.goFilePathAlloc`이 이 경로를 만듭니다.

`kind = .test_file`이면 파일명은 `_test.go`로 끝나야 합니다. 기본값 `.source`는 일반 `.go`
파일이어야 합니다. 외부 테스트 패키지는 `.test_file`이 필수입니다. 동일 패키지의 `Test…`,
`Example…`도 `.public`과 `.test_file`로 생성합니다. 예제의 `// Output:` 주석은 본문에 씁니다.

`build_constraint = "linux && !integration"`은 package 앞의 `//go:build` 줄로 생성됩니다.
ASCII 태그·`!`·`&&`·`||`·괄호를 지원하며, 잘못된 식·개행·4096바이트 초과·과도한 중첩은
등록 시 컴파일 오류입니다. 빌드 태그만 있는 파일은 아래 `Artifact`로 만들 수 있습니다.

파일별 import는 `imports: ?fn(Context) ![]const Import` 콜백으로 제공합니다. 정적 배열을
반환하거나 현재 `go_module`·패키지 경로에 맞춰 run allocator로 배열을 만들면 됩니다.
외부 테스트·raw 파일에서는 공개 Go 타입의 import를 자동 추론하지 않으므로 필요한 패키지를
명시하세요. `Context`의 타입 writer는 공개 API 타입을 위한 것이며 raw 타입 변환기가 아닙니다.

```zig
fn testImports(_: api.Context) ![]const api.Import {
    return &.{.{ .qualifier = "testing", .path = "testing" }};
}
```

플러그인 공통 import는 기존처럼 `Plugin.imports` 배열에 선언할 수 있습니다. 일반 import는
본문에서 사용한 한정자만 출력하며 `_`·`.` import는 명시된 대로 포함됩니다. 파일별 `_ "embed"`
import와 `//go:embed`를 사용하면 함께 생성한 artifact를 Go 파일에 포함할 수 있습니다.
동일한 한정자에 서로 다른 경로를 지정하면 오류로 거부합니다.

공개 패키지 단위의 일반 Go 파일만 생산 코드의 `file_hook`과 helper 참조 분석에 참여합니다.
테스트·외부 테스트·raw·문서 단위 Go 파일은 별도로 렌더링하므로 생산 코드의 private helper에
의존하지 마세요. 일반 Go 파일은 helper 분석 때문에 여러 번 렌더링될 수 있어야 합니다.

### 바이트 산출물

```zig
pub const plugin: api.Plugin = .{
    .name = "SCHEMA",
    .artifacts = &.{.{ .pathAlloc = path, .render = render }},
};
fn path(context: api.ArtifactContext) ![]u8 {
    return context.allocator.dupe(u8, "api.proto");
}
fn render(_: api.ArtifactContext, writer: *std.Io.Writer) !void {
    try writer.writeAll("syntax = \"proto3\";");
}
```

`ArtifactContext`는 `allocator`, `program`, `options`, `config(P)`, `publicFilePathAlloc`을
제공합니다. Go writer나 파일 hook은 없습니다. `.md`, `.proto`, TypeScript, `go.mod` 조각,
바이너리, `.go` 모두 확장자와 무관하게 **빈 파일·NUL·CRLF·끝 개행까지 그대로 보존**합니다.
`go.mod` 조각을 생성하더라도 기존 `go.mod`에 자동 병합하지 않습니다.

두 파일 계약 모두 선택적인 `enabled` 콜백으로 설정에 따라 생략할 수 있습니다.
`GoFile.enabled`는 `Context`, `Artifact.enabled`는 `ArtifactContext`를 받고 `!bool`을
반환합니다. false이면 경로와 본문 콜백을 호출하지 않습니다. Artifact의 빈 본문은 생략이
아닌 0바이트 파일입니다. GoFile의 빈 본문은 파일을 생성하지 않거나 해당 경로의 기존 산출물을 제거합니다.

모든 출력 경로는 생성 루트 기준으로 정규화하고, core 파일과 다른 플러그인 산출물을 포함해
중복 검사합니다. 대소문자만 다른 ASCII 경로도 충돌로 취급합니다. 잘못된 경로·패키지 디렉터리·확장자·중복은 `ZIGO059`입니다. 렌더링이나
검증에 실패하면 기존 출력에 쓰지 않습니다. raw 추가 파일과 완성된 Go artifact는 사용자
코드를 실행할 수 있으므로 동작 불변을 보장하지 않지만, core가 생성하는 파일을 덮어쓸 수는 없습니다.

## 테스트와 이전

`files`를 `go_files`로, `File`을 `GoFile`로 옮기고 계약 major를 2로 바꾸세요.
Go 프레임이 필요 없는 파일은 `artifacts`와 `ArtifactContext`로 옮깁니다.
이전 플러그인은 validator를 `ValidateContext`와 `diagnose`로 바꾸고, 파일 콜백을
`Context` 기반으로 바꿔야 합니다. Must 설정은 `plugin_config.MUST.enabled`로 옮깁니다.
구형 writer 테이블을 직접 만든 코드는 모든 슬롯을 구현해야 합니다.

[`tests/plugin_contract.zig`](../tests/plugin_contract.zig)는 별도 외부 모듈로 설정 전달,
검증→분석 사실 전달, 반복 렌더링, 타입·파일·패키지 hook과 cgo/purego의 렌더링 ABI 불변을 검사합니다.
추가로 외부 플러그인의 문서 변형·의존성 순서·시간 타입 변환·명명 정책·native 인자 재배치와
잘못된 변형의 출력 전 거부를 검사합니다. 생성된 Go wrapper와 shim은 실제 Zig target에
연결해 두 backend에서 인자 의미와 변환 결과를 왕복 검사합니다.
[`tests/plugin_outputs.zig`](../tests/plugin_outputs.zig)는 산출물 바이트 보존·패키지 범위·경로
충돌을 검사하고, Go 테스트에서는 생성된 내부·외부 테스트, raw 추가 파일, build constraint와
artifact의 `go:embed`까지 컴파일하고 실행합니다.
내장 모듈은 생성기 내부를 import할 수 없는 모듈 루트에서 컴파일합니다. golden case는
추가 hook을 켜지 않은 생성 결과를 비교합니다.

예제: [satisfies](../plugins/satisfies), [JSON](../plugins/json), [enumkit](../plugins/enumkit),
[wrapper writer](../tests/plugins/wrappers.zig).

The CLI records output kinds in `.zigo-outputs.json`. Only `GoFile` outputs are
passed to gofmt; artifacts retain their exact bytes, including `.go` artifacts.
The build update step publishes Go files and artifacts, and removes obsolete
artifacts listed in the previous manifest. Untracked consumer files remain
unowned. Source synchronization checks include these artifacts as well.
Direct generator callers can request this metadata with `write_manifest = true`.
The manifest path is reserved when metadata is enabled.
