# Plugin 작성

이 가이드는 enum에 Go helper를 추가하는 최소 plugin을 만듭니다. plugin은 별도 Zig package로
두고 root source가 `pub const plugin`을 export하게 합니다.

## 최소 plugin

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
    .targets = &.{.enumeration},
    .type_hook = typeHook,
};

fn typeHook(
    context: api.Context,
    writer: *std.Io.Writer,
    declaration: semantic.TypeDecl,
) !void {
    const options = try context.typeOptions(plugin, declaration) orelse return;
    if (!options.enabled) return;

    try writer.print(
        "func (value {0s}) HasName() bool {{ return value.String() != \"\" }}\n",
        .{declaration.name},
    );
}
```

실제 구현에서는 Go string을 조합해 비교하기보다 semantic field를 순회해 정확한 switch를
생성하는 편이 좋습니다. [enumkit](../../plugins/enumkit/src/plugin.zig)이 그 예입니다.

## 이름과 target

plugin `name`은 다음 세 곳에서 같은 identity로 사용됩니다.

- declaration extension key
- diagnostic prefix
- plugin output owner와 file suffix

대문자 ASCII 이름을 사용하세요. `targets`는 option을 붙일 수 있는 declaration kind를
제한하며 function, handle, value, enumeration, tagged_union, callback, materialized,
error_set을 선택할 수 있습니다.

## option

```zig
pub const FunctionOptions = struct {
    trace: bool = true,
};

pub const TypeOptions = struct {
    helper_name: []const u8 = "Values",
};
```

`FunctionOptions`와 `TypeOptions`는 JSON으로 직렬화 가능한 type이어야 합니다. 사용자가
`.use(plugin, value)`를 쓰는 위치에서 Zig type checking이 먼저 적용되고 generator에서 다시
decode됩니다.

build 전체에 적용할 configuration은 `Config`로 분리합니다.

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

hook에서는 `try context.config(plugin)`으로 읽습니다. declaration option과 build config는 서로
다른 범위입니다.

## validation

core validation 뒤에 project rule을 추가할 수 있습니다.

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
                .site = .{ .path = "semantic.json", .declaration = declaration.name },
                .hint = "attach KNOWN to an enumeration",
            });
        }
    }
}
```

`NAME001`은 option decode failure에 사용되므로 plugin의 자체 rule은 일반적으로 `002`부터
시작합니다. core 진단을 숨기지 않도록 core validation이 먼저 실행됩니다.

## 별도 Go file

기존 type 바로 뒤에 코드를 붙일 필요가 없다면 `go_files`를 사용합니다.

```zig
pub const plugin: api.Plugin = .{
    .name = "KNOWN",
    .go_files = &.{.{
        .pathAlloc = path,
        .render = render,
    }},
};

fn path(context: api.Context) ![]u8 {
    return context.publicFilePathAlloc("known_gen.go");
}
```

Go file은 package clause, build constraint와 import framing을 generator가 맡고 body만 plugin이
씁니다. Go가 아닌 정확한 byte artifact는 `artifacts`를 사용합니다.

## deterministic output

- source order가 필요한 경우 semantic/ABI 배열 순서를 유지합니다.
- map iteration 결과는 정렬합니다.
- timestamp, absolute build path와 random value를 출력하지 않습니다.
- hook 호출 중 shared mutable state를 사용하지 않습니다.
- path는 context helper로 만들고 output root 밖으로 나가지 않습니다.
- 생성된 Go는 `gofmt`와 `go test`를 통과해야 합니다.

## test

plugin package에서는 최소한 다음을 검사하세요.

- option별 render 결과 golden
- 잘못된 declaration의 diagnostic code와 hint
- empty declaration과 disabled option
- 여러 public package에서 path와 import
- 반복 실행의 byte-identical output
- cgo와 purego에서 public Go code compile

zigo 저장소의 [plugin API test](../../tests/plugin_api.zig),
[plugin output test](../../tests/plugin_outputs.zig)와 bundled
[enumkit](../../plugins/enumkit/src/plugin.zig)을 참고할 수 있습니다.
