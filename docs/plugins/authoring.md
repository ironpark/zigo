# 플러그인 작성

이 가이드는 열거형에 Go 도우미를 추가하는 최소 플러그인을 만듭니다. 플러그인은 별도 Zig 패키지로
두고 root 소스가 `pub const plugin`을 export하게 합니다.

## 최소 플러그인

`src/plugin.zig`:

```zig
const std = @import("std");
const api = @import("plugin");
const semantic = @import("semantic");

pub const Options = struct {
    enabled: bool = true,
};

pub const plugin: api.Plugin = .{
    .name = "KNOWN",
    .TypeOptions = Options,
    .subjects = &.{.enumeration},
    .go = .{ .visit = visit },
};

fn visit(context: api.GoContext, node: api.Node, b: *api.Builder) !void {
    if (node != .type) return;
    const declaration = node.type;
    const options = try context.optionsOf(plugin, .type, node) orelse return;
    if (!options.enabled) return;

    var body: std.ArrayList(api.gobuild.Stmt) = .empty;
    defer body.deinit(context.allocator);
    for (context.program.liveFields(declaration.name)) |field| {
        const value = field.value orelse return error.MissingEnumValue;
        try body.append(context.allocator, try b.ifStmt(.{
            .cond = try b.bin("==", b.ident("value"), b.int(value)),
            .body = try b.dupStmts(&.{try b.ret(&.{b.boolean(true)})}),
        }));
    }
    try body.append(context.allocator, try b.ret(&.{b.boolean(false)}));
    try b.emit(&.{try b.func(.{
        .doc = .{ .text = "HasName reports whether value is a registered tag." },
        .receiver = .{ .name = "value", .type = declaration.name },
        .name = "HasName",
        .signature = .{ .explicit = .{ .results = &.{b.ident("bool")} } },
        .body = body.items,
    })}, .{ .blank_after = true });
}
```

`visit`은 [렌더링 slot](api-reference.md#렌더링-slot-go와-rust) 안에 있습니다. 어떤 출력 언어를
쓸지는 slot을 채우는 것으로 정합니다: Go를 쓰면 `.go`, Rust를 쓰면 `.rust`, 둘 다 쓰면 둘 다.
채우지 않은 target에는 transform도 진단도 출력 file도 기여하지 않으므로, Go writer로 쓴 hook이
Rust 실행에 끌려 나올 일이 없습니다. slot을 하나도 채우지 않은 플러그인은 IR에만 기여하는
플러그인이고 모든 target에서 실행됩니다.

렌더링 hook은 slot마다 `visit` 하나입니다. generator가 프로그램의 모든 [`Node`](api-reference.md#렌더링-hook-visit)를
document 순서로 넘기고, 플러그인은 관심 있는 node만 처리합니다. 선언과 그 안쪽 node에 붙은
옵션은 모든 context에서 같은 한 가지 방법, `optionsOf(plugin, attachment, ext)`로 읽습니다
(`ext` 자리에 `Node`를 그대로 넘겨도 됩니다). Go 출력은 `visit`이 받은
[builder](api-reference.md#go-builder)로 조립합니다. 플러그인은 Go 문법을 문자열로 쓰지 않습니다. Zig 이름에서 파생하는 Go 식별자는
`identifierAlloc(allocator, name, .pascal | .camel)`로 얻어야 generator가 core 타입에 쓰는 것과
같은 표기(initialism 규칙)를 플러그인도 얻습니다. builder node는 context allocator(run arena)에
복사되므로 loop 안에서 만든 node도 렌더링까지 살아 있습니다.

등록된 태그의 실제 정수 값으로 비교하므로 알려지지 않은 값은 `false`가 됩니다.
`String()`은 알려지지 않은 값에도 설명 문자열을 반환할 수 있어 빈 문자열 여부로 판별하면
안 됩니다. 이 예제는 Go 어댑터가 없는 열거형에 사용합니다. 범용 플러그인은 어댑터와
메서드 이름 충돌도 검증해야 합니다. [enumkit](../../plugins/enumkit/src/plugin.zig)의 검증을
참고하세요.

## 프로젝트에 연결하고 실행하기

[시작 가이드](../getting-started.md)의 프로젝트에 위 파일을 추가한 경우, `addGoBindings`에
다음 옵션을 넣습니다.

```zig
.plugins = &.{.{
    .name = "known",
    .root_source_file = b.path("src/plugin.zig"),
}},
```

`src/root.zig`에 `pub const Mode = enum(u8) { idle, active };`를 추가합니다.
`src/bindings.zig` 상단에 `const known = @import("known");`을 추가하고 `.declarations`에
`api.enumeration("Mode", .{}).use(known.plugin, .{})`를 넣습니다.

`go/mylib/plugin_test.go`에 다음 테스트를 작성합니다.

```go
package mylib_test

import (
    "testing"
    "example.com/mylib/go/mylib"
)

func TestHasName(t *testing.T) {
    if !mylib.ModeIdle.HasName() || mylib.Mode(99).HasName() {
        t.Fatal("HasName must recognize only declared tags")
    }
}
```

프로젝트 루트에서 생성한 뒤 테스트합니다.

```bash
zig build go
(cd go && go test ./...)
```

테스트가 통과하면 플러그인 등록, 옵션 전달과 생성 메서드 호출이 연결된 것입니다.

## 이름과 대상

플러그인 `name`은 다음 세 곳에서 같은 식별 정보로 사용됩니다.

- 선언 extension key
- 진단 접두사
- 플러그인 출력 owner와 file 접미사

대문자 ASCII 이름을 사용하세요. `subjects`는 옵션을 붙일 수 있는 node kind를
제한하며 선언 kind인 `.function`, `.handle`, `.value`, `.enumeration`, `.tagged_union`,
`.callback`, `.materialized`, `.error_set`과 선언 안쪽 node인 `.param`, `.result`,
`.field`, `.enum_tag`를 선택할 수 있습니다.

## 옵션

```zig
pub const FunctionOptions = struct {
    trace: bool = true,
};

pub const TypeOptions = struct {
    helper_name: []const u8 = "Values",
};
```

선언 안쪽 node도 각자의 옵션 타입을 가집니다.

```zig
pub const ParamOptions = struct {
    trusted: bool = false,
};

pub const FieldOptions = struct {
    column: []const u8,
};
```

여섯 옵션 타입은 모두 JSON으로 직렬화 가능한 타입이어야 합니다. 사용자가
`.use(plugin, value)`를 쓰는 위치에서 Zig 타입 checking이 먼저 적용되고 generator에서 다시
decode됩니다.

binding은 매개변수와 field에 같은 방식으로 붙입니다.

```zig
api.func("insert", .{
    .params = &.{zigo.param.input(1).use(known.plugin, .{ .trusted = true })},
}),
api.value("Row", .{
    .fields = &.{(zigo.ValueField{ .name = "id" }).use(known.plugin, .{ .column = "row_id" })},
}),
```

generator는 그 node를 `visit`에 따로 넘기고, hook은 node의 `ext`를 해당 attachment로 읽습니다.

```zig
switch (node) {
    .param => {
        const options = try context.optionsOf(plugin, .param, node) orelse return;
        if (options.trusted) ...;
    },
    .field => {
        const options = try context.optionsOf(plugin, .field, node) orelse return;
        ...;
    },
    else => {},
}
```

`subjects`에 `.param`이나 `.field`를 넣지 않은 플러그인에 그 node로 `use`하면 선언
위치에서 컴파일 error입니다.

빌드 전체 설정은 `Config`로 분리하고 `plugin` 선언에도 `.Config = Config`를 지정합니다.

```zig
pub const Config = struct {
    package_prefix: []const u8 = "",
};
```

```zig
const entry: zigo.PluginModule = .{
    .name = "known",
    .root_source_file = dependency.path("src/plugin.zig"),
    .config = zigo.configJson(b, .{ .package_prefix = "api" }),
};
```

`visit`에서는 `try context.config(plugin)`으로 읽습니다. 선언 옵션과 빌드 config는 서로
다른 범위입니다.

## 검증

core 검증 뒤에 project rule을 추가할 수 있습니다.

```zig
fn validate(context: api.ValidateContext) !void {
    for (context.document.types) |declaration| {
        const options = try context.optionsOf(
            plugin,
            .type,
            declaration.ext,
        ) orelse continue;
        _ = options;

        if (declaration.kind != .@"enum") {
            try context.diagnose(.{
                .severity = .@"error",
                .code = "KNOWN002",
                .message = "KNOWN requires an enum",
                .site = api.site.typeSite(declaration),
                .hint = "attach KNOWN to an enumeration",
            });
        }
    }
}
```

위 함수를 실행하려면 `plugin` 선언에 `.validate = validate`도 추가합니다.

진단의 `site`는 `api.site`의 도우미로 만듭니다. `typeSite(declaration)`과 `functionSite(function)`은
reflection이 기록한 Zig 소스 위치(파일, 줄, 열)를 가리키고, 위치가 없는 선언은 `semantic.json`의
해당 항목으로 떨어집니다. 경로를 직접 쓰지 마세요.

`NAME001`은 옵션 decode failure에 사용되므로 플러그인의 자체 rule은 일반적으로 `002`부터
시작합니다. core 진단을 숨기지 않도록 core 검증이 먼저 실행됩니다.

## 별도 Go file

기존 타입 바로 뒤에 코드를 붙일 필요가 없다면 slot의 `source_files`를 사용합니다.

```zig
pub const plugin: api.Plugin = .{
    .name = "KNOWN",
    .go = .{ .source_files = &.{.{ .pathAlloc = path, .render = render }} },
    .rust = .{ .source_files = &.{.{ .module = "known", .render = renderRust }} },
};

fn path(context: api.GoContext) ![]u8 {
    return context.publicFilePathAlloc("known_gen.go");
}
```

Go file은 패키지 clause, 빌드 constraint와 import framing을 generator가 맡고 body만 플러그인이
씁니다. Rust module은 `src/<module>.rs`에 쓰이고 `lib.rs`가 `mod`와 재export를 써 주므로
플러그인은 경로도 `mod` 줄도 고르지 않습니다. Go도 Rust도 아닌 정확한 바이트 산출물은
언어 중립인 `artifacts`를 사용합니다.

## 한 플러그인에서 두 target 렌더링하기

`go`와 `rust` slot을 모두 채우면 한 플러그인이 두 출력 언어를 렌더링합니다. 바인딩 쪽 표기는
그대로입니다. `use(enumkit.plugin, .{ .values = true, .is_known = true })` 하나가 Go 바인딩
세트에서는 Go를, Rust 바인딩 세트에서는 crate를 만듭니다. 동봉 플러그인
[enumkit](../../plugins/enumkit/src/plugin.zig)이 그 기준 예제입니다.

```zig
pub const plugin: api.Plugin = .{
    .name = "ENUMKIT",
    .TypeOptions = Options,
    .subjects = &.{.enumeration},
    .go = .{ .visit = visitGo },
    .rust = .{ .visit = visitRust },
    .validate = validateDocument,
};
```

옵션, `subjects`, `validate`, `analyze`, `transform`, `artifacts`는 언어 중립이므로 slot 밖에
한 번만 씁니다. 공유할 것은 여기까지입니다. **어느 선언에 무엇이 붙었는지**는 두 slot이
같이 보고, **그것을 어떻게 쓰는지**는 각 slot이 따로 씁니다.

```zig
/// 두 slot이 공유하는 전부: 이 node가 무엇이고 어떤 옵션이 붙었는가.
/// `GoContext`와 `RustContext`는 서로 다른 타입이지만 `optionsOf`와 `program`을
/// 같은 모양으로 답하므로 context는 `anytype`으로 받습니다.
fn attachment(context: anytype, node: api.Node) !?Attachment {
    if (node != .type) return null;
    const declaration = node.type;
    const options = try context.optionsOf(plugin, .type, node) orelse return null;
    return .{ .declaration = declaration, .fields = context.program.liveFields(declaration.name), .options = options };
}
```

렌더링 본문을 하나로 합치려 하지 마세요. 두 언어가 다른 것은 이름 규칙이 아닙니다.

- Go의 enum은 정수 newtype이라 `IsKnown()`이 언제나 값을 검사해야 합니다. Rust의 닫힌
  enum은 알 수 없는 값을 표현할 수 없으므로 `is_known(self)`는 상수 `true`입니다.
- Go는 매번 새 slice를 반환하는 `<Type>Values()`를, Rust는 빌려 주는
  `values() -> &'static [Self]`를 씁니다. Rust 쪽은 불변이라 복사할 이유가 없습니다.
- 생성기가 이미 쓰는 것을 다시 쓰지 않습니다. Rust emitter는 `.text = true`인 enum에
  `Display`와 `FromStr`을 이미 쓰므로 플러그인이 또 쓰면 trait 중복 구현입니다. 이것은
  Go 쪽 `String`/`Parse<Enum>`과 같은 조건입니다.
- 생성된 code가 lint를 통과해야 합니다. Rust 예제와 golden crate는 `-D warnings`로
  컴파일되므로, `match`로 bool을 만들면 `clippy::match_like_matches_macro`에,
  `x >= a && x <= b`는 `clippy::manual_range_contains`에 걸립니다.

타입 이름처럼 생성기만 아는 것은 `RustWriters`가 답합니다. `b.typeName(declaration.name)`이
crate가 쓰는 철자(`crate::Mode`)를 주므로 플러그인은 PascalCase 규칙을 따로 갖지 않습니다.

```zig
try b.emit(&.{try b.implBlock(.{ .type = b.typeName(declaration.name), .items = items.items })}, .{ .blank_before = true });
```

slot을 채운 것 자체가 "이 언어를 렌더링한다"는 선언입니다. `go` slot만 채운 플러그인을 Rust
바인딩 세트의 `.plugins`에 나열해도 error가 아니라 아무것도 쓰지 않습니다.

## 결정적인 출력

- 소스 순서가 필요한 경우 semantic/ABI 배열 순서를 유지합니다.
- map iteration 결과는 정렬합니다.
- timestamp, absolute 빌드 경로와 random value를 출력하지 않습니다.
- `visit` 호출 중 공유 가변 상태를 사용하지 않습니다.
- 경로는 context 도우미로 만들고 출력 root 밖으로 나가지 않습니다.
- 생성된 Go는 `gofmt`와 `go test`를 통과해야 합니다.

## 테스트

플러그인 패키지에서는 최소한 다음을 검사하세요.

- 옵션별 렌더링 결과 golden. `api.testing.goContext(allocator, program)`와
  `api.testing.rustContext(allocator, program)`가 header·식별자·리터럴 도우미는 동작하고
  generator가 답해야 하는 writer는 `error.Unsupported`를 내는 context를 줍니다. Rust
  쪽에서는 `writeTypeName`만 실제로 답하므로 `impl` block을 쓰는 slot도 generator 없이
  테스트할 수 있습니다
- 잘못된 선언의 진단 code와 hint
- empty 선언과 disabled 옵션
- 여러 공개 패키지에서 경로와 import
- 반복 실행의 byte-identical 출력
- cgo와 purego에서 공개 Go code 컴파일

zigo 저장소의 [플러그인 계약 테스트](../../tests/plugin_contract.zig),
[플러그인 출력 테스트](../../tests/plugin_outputs.zig)와 bundled
[enumkit](../../plugins/enumkit/src/plugin.zig)을 참고할 수 있습니다.
