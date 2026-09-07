# 작성 API 마이그레이션

이 문서는 0.17.x의 flat binding/DSL을 새 declaration tree API로 옮기는 방법입니다.
새 API는 **소스 호환성을 유지하지 않습니다**. 생성기의 semantic IR과 기존 수명 구현을
유지하면서, 작성 단계의 참조·선택·계약 검증을 바꿨습니다.

## 최소 변경

이전 선언:

```zig
pub const bindings = zigo.define(.{
    .root = library,
    .functions = &.{.{ .path = "root.add" }},
});
```

새 선언:

```zig
const api = zigo.scope(library);
pub const bindings = zigo.define(.{
    .root = library,
    .declarations = &.{api.function("add", .{})},
});
```

함수·타입을 함께 `declarations`에 넣습니다. package에는 경로 목록 대신 실제 선언을 넣고,
타입에는 `.members(entries)`로 메서드를 묶습니다. 중첩 namespace는
`api.in("namespace").in("child")`로 선택합니다.

| 이전 작성 방식 | 새 작성 방식 |
|---|---|
| `zigo.dsl.func("root.add")` | `api.function("add", .{})` |
| `zigo.dsl.func("Store.read")` | `api.in("Store").function("read", .{})` |
| `.types = &.{.{ .handle = .{ .type = library.Store } }}` | `.declarations = &.{api.handle("Store", .{})}` |
| `funcs(..., .{ .names = ... })` | `api.functions(.{ .names = ... })` |
| `funcs(..., .{ .prefix = ..., .exclude = ... })` | `api.functions(.{ .public = .{ .prefix = ..., .exclude = ... } })` |
| `collect(...)` | `++`로 `[]const zigo.Entry` 또는 배열 결합 |
| `pathsOf(...)`, package selector·closure | `zigo.package(.{ .path = ..., .declarations = ... })` |
| `.receiver = library.Store` | `.role = .{ .method = api.typeRef("Store") }` |
| `.constructs = library.Store` | `.role = .{ .constructor = .{ .type = api.typeRef("Store") } }` |
| `.destroys = library.Store` | `.role = .{ .destructor = api.typeRef("Store") }` |
| `.child_of_receiver = true` | constructor의 `.parent = .receiver`와 `.receiver = .{ .type = api.typeRef("Parent") }` (멤버 안에서는 `.member`) |
| `.returns.ownership = .caller` | `.returns.lifetime = .{ .owned = .{} }` |
| `.returns.release = "root.free"` | `.returns.lifetime.owned.release = api.ref("free")` |
| `.returns.ownership = .borrowed` | `.returns.lifetime = .{ .borrowed = .receiver }` |
| `.returns.ownership = .library` | `.returns.lifetime = .library` |
| `.strings`, `.codepoints` | `.defaults.strings`, `.defaults.codepoints` |
| `.discover = .public`, 별도 `.exclude` | `.discovery = .{ .public = .{ .exclude = &.{api.ref("debug")} } }` |
| `.iterator = options` | `.use(zigo.features.iterator, options)` |
| `.implements = .writer` | `.use(zigo.features.implements, .{ .kind = .writer })` |
| enum `.text = true` | `.use(zigo.features.text, .{})` |
| `.interfaces = &.{...}` | `declarations` 안의 `zigo.interface(...)` |
| `.extend(plugin, options)` | `.use(plugin, options)` |

`.methods`의 `strip_prefix`는 없어졌습니다. 공유 receiver는 타입의 `members`로 묶고
필요한 최종 이름을 `.named()`로 명시하세요. `.role = .auto`는 기존 receiver 추론을 유지하며,
`.role = .free`로 첫 handle 인자를 자유 함수의 인자로 남길 수도 있습니다.

## 파라미터 계약

이전 `params`는 receiver·주입 인자를 제거한 위치 목록이었습니다. 새 `params`는 필요한
인자만 고르는 sparse 목록이며, **원본 Zig 인덱스**를 적습니다.

```zig
// fn read(self: *Store, gpa: Allocator, offset: u32, dst: []u8) usize
api.in("Store").function("read", .{
    .params = &.{.{
        .index = 3,
        .go_name = "dst",
        .contract = .{ .buffer = .{ .output = .{ .written = .result } } },
    }},
})
```

| 이전 Param 필드 | 새 Param 필드 |
|---|---|
| `.name` | `.go_name` |
| `.semantic`, `.go` | 그대로 유지 |
| `.direction = .in` | `.contract = .{ .buffer = .input }` 또는 기본값 |
| `.direction = .out`, `.written` | `.contract = .{ .buffer = .{ .output = .{ .written = ... } } }` |
| `.direction = .inout`, `.written` | `.contract = .{ .buffer = .{ .inout = .{ .written = ... } } }` |
| `.buffer = size` | `.contract = .{ .stream = .{ .buffer = size } }` |
| `.retention`, `.thread`, `.reentrancy`, `.go_error` | `.contract.callback` 안의 같은 필드 |
| `.on_callback_failure` | `.contract.callback.on_failure` |
| `.userdata = .{ .param = "ctx" }` | `.contract.callback.userdata = 원본_Zig_인덱스` |
| `.flatten = fields` | `.contract = .{ .flatten = fields }` |
| 함수의 `.cancel` | 대상 Param의 `.contract = .{ .cancel = .{ .canceled = "Canceled" } }` |

userdata 인덱스도 receiver·주입 인자를 포함합니다. 생략한 파라미터는 기존 source 이름과
기본 계약을 사용합니다. 콜백 타입의 `CallbackOptions.params`도 원본 native 인덱스의 sparse
목록입니다. 기존 위치 목록에 `.index`를 넣을 때 userdata와 byte pair의 length도 포함해
다시 세세요. pointer에만 힌트를 붙이며 length·userdata 항목은 제거합니다.
콜백 타입의 `on_callback_failure`도 `on_failure`로 바뀌었습니다.

```zig
// fn (ctx: usize, text: [*]const u8, len: usize, cp: u32) callconv(.c) void
api.callback("Visitor", .{
    .userdata = .first,
    .params = &.{
        .{ .index = 1, .semantic = .utf8_string },
        .{ .index = 3, .semantic = .codepoint },
    },
})
```

초기 declaration tree API에서 옮긴다면 constructor의 nullable `TypeRef` receiver도 바꿔야 합니다.
생략·`.none`은 정적 생성자이고, 멤버 문맥은 `.member`, 명시 타입은
`.{ .type = api.typeRef("Parent") }`입니다. 생성자에 첫 handle 인자가 있어도 `.none`이면
receiver로 추론하지 않습니다.

`zigo.param.output(3, .result)`, `zigo.param.callback(2, options)`,
`zigo.result.releasedBy(api.ref("release"))` 등의 helper는 전체 schema literal과 같은 값을
만듭니다. 반복 계약은 상수로 공유하고, source와 같은 이름만 적던 항목은 생략할 수 있습니다.
명시적 userdata 링크나 cancellation 이름처럼 정규화에서 고정하는 이름은 남기세요.

## 교체 의미와 참조

`.with()`는 적은 필드만 교체합니다. `null`은 기존 값을 지우며, 중첩 옵션은 통째로 교체합니다.
이전 helper의 “null이면 유지” 동작이나 중첩 계약의 누적을 기대하면 안 됩니다.

release·covers·discovery 제외는 `FunctionRef`, receiver·인터페이스 타입은 `TypeRef`를
받습니다. Go 이름을 바꿔도 참조는 유지됩니다. release 함수는 명시적으로 내보내야 합니다.

`scope`의 타입 helper는 **공개 alias**를 받습니다. generic 인스턴스는 바인딩할 라이브러리나
wrapper 모듈에서 `pub const FloatBuffer = Buffer(f32);`처럼 내보내세요. 같은 Zig 타입을
여러 번 등록할 수 없고, 내부 참조가 Go 타입 이름을 키로 쓰므로 등록 이름은 패키지 전체에서
고유해야 합니다.

## 플러그인 작성자

`Plugin.Options`는 `FunctionOptions`와 `TypeOptions`로 나뉩니다. 둘 다 기본값은 빈 struct입니다.
`targets`는 옵션을 붙일 수 있는 대상 목록입니다.

```zig
pub const plugin: plugin_api.Plugin = .{
    .name = "MYPLUGIN",
    .FunctionOptions = struct { checked: bool = false },
    .TypeOptions = struct { label: ?[]const u8 = null },
    .targets = &.{ .function, .value },
};
```

`Context.functionOptions()`는 `FunctionOptions`, `Context.typeOptions()`는 `TypeOptions`를
반환합니다. 직접 읽는 검증기는 `readOptions(plugin, .function, allocator, ext)` 또는
`readOptions(plugin, .type, allocator, ext)`를 사용합니다. 옵션의 JSON 필드 이름을 유지하면
기존 semantic payload의 모양도 유지됩니다.

`.use()`는 같은 이름의 플러그인을 두 번 붙이면 거부합니다. 교체하려면
`.replacePlugin(plugin, options)`를 명시하세요. 명시적인 null은 JSON에도 보존됩니다.
지원 대상은 function·handle·value·enumeration·tagged_union입니다. materialized·callback 타입
attachment는 지원하지 않으며 컴파일 오류입니다.

## 검증과 범위

```bash
zig build go
zig build go-check
(cd go && go test ./...)
```

기존 ABI baseline이 있으면 `abi-check`도 실행하세요. 선언을 타입·패키지로 묶으면 출력 순서가
바뀔 수 있습니다. 이름·패키지·인덱스를 바꾼 경우는 실제 공개 API 차이도 검토해야 합니다.

이 변경은 작성 API의 재설계입니다. 임의 객체를 borrow owner로 잡거나 여러 부모의 수명을
추적하는 새 런타임 기능은 추가하지 않았습니다. borrowed는 receiver, child constructor는
명시한 receiver 부모를 사용합니다. package 기본값 override는 그 안의 명시 함수에 적용되고,
타입 필드와 자동 발견 함수는 Binding 기본값을 사용합니다. 함수별 backend 선택과
파라미터 이름 기반 selector도 제공하지 않습니다.
