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
    .type_hook = typeHook,
};

fn typeHook(
    context: api.Context,
    writer: *std.Io.Writer,
    declaration: semantic.TypeDecl,
) !void {
    const options = try context.optionsOf(plugin, .type, declaration.ext) orelse return;
    if (!options.enabled) return;

    const b = context.builder();
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
    try b.render(writer, &.{try b.func(.{
        .doc = .{ .text = "HasName reports whether value is a registered tag." },
        .receiver = .{ .name = "value", .type = declaration.name },
        .name = "HasName",
        .signature = .{ .explicit = .{ .results = &.{b.ident("bool")} } },
        .body = body.items,
    })}, .{ .blank_after = true });
}
```

선언에 붙은 옵션은 모든 context에서 같은 한 가지 방법, `optionsOf(plugin, .function | .type, ext)`로
읽습니다. Go 출력은 `context.builder()`가 돌려주는 [builder](api-reference.md#go-builder)로
조립합니다. 플러그인은 Go 문법을 문자열로 쓰지 않습니다. Zig 이름에서 파생하는 Go 식별자는
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

대문자 ASCII 이름을 사용하세요. `subjects`는 옵션을 붙일 수 있는 선언 kind를
제한하며 `.function`, `.handle`, `.value`, `.enumeration`, `.tagged_union`, `.callback`,
`.materialized`, `.error_set`을 선택할 수 있습니다.

## 옵션

```zig
pub const FunctionOptions = struct {
    trace: bool = true,
};

pub const TypeOptions = struct {
    helper_name: []const u8 = "Values",
};
```

`FunctionOptions`와 `TypeOptions`는 JSON으로 직렬화 가능한 타입이어야 합니다. 사용자가
`.use(plugin, value)`를 쓰는 위치에서 Zig 타입 checking이 먼저 적용되고 generator에서 다시
decode됩니다.

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

hook에서는 `try context.config(plugin)`으로 읽습니다. 선언 옵션과 빌드 config는 서로
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

기존 타입 바로 뒤에 코드를 붙일 필요가 없다면 `source_files`를 사용합니다.

```zig
pub const plugin: api.Plugin = .{
    .name = "KNOWN",
    .source_files = &.{.{
        .pathAlloc = path,
        .render = render,
    }},
};

fn path(context: api.Context) ![]u8 {
    return context.publicFilePathAlloc("known_gen.go");
}
```

Go file은 패키지 clause, 빌드 constraint와 import framing을 generator가 맡고 body만 플러그인이
씁니다. Go가 아닌 정확한 바이트 산출물은 `artifacts`를 사용합니다.

## 결정적인 출력

- 소스 순서가 필요한 경우 semantic/ABI 배열 순서를 유지합니다.
- map iteration 결과는 정렬합니다.
- timestamp, absolute 빌드 경로와 random value를 출력하지 않습니다.
- hook 호출 중 공유 가변 상태를 사용하지 않습니다.
- 경로는 context 도우미로 만들고 출력 root 밖으로 나가지 않습니다.
- 생성된 Go는 `gofmt`와 `go test`를 통과해야 합니다.

## 테스트

플러그인 패키지에서는 최소한 다음을 검사하세요.

- 옵션별 렌더링 결과 golden. `api.testing.context(allocator, program)`가 header·식별자·리터럴
  도우미는 동작하고 generator가 답해야 하는 writer는 `error.Unsupported`를 내는 context를 줍니다
- 잘못된 선언의 진단 code와 hint
- empty 선언과 disabled 옵션
- 여러 공개 패키지에서 경로와 import
- 반복 실행의 byte-identical 출력
- cgo와 purego에서 공개 Go code 컴파일

zigo 저장소의 [플러그인 계약 테스트](../../tests/plugin_contract.zig),
[플러그인 출력 테스트](../../tests/plugin_outputs.zig)와 bundled
[enumkit](../../plugins/enumkit/src/plugin.zig)을 참고할 수 있습니다.
