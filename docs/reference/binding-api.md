# Binding API 참조

이 문서는 `bindings.zig`에서 사용하는 public authoring API의 필드와 helper를 빠르게 찾기 위한
참조입니다. 학습 순서는 [바인딩 작성](../authoring/README.md)을 사용하세요.

## 최상위 binding

```zig
pub const bindings = zigo.define(.{
    .root = library,
    .allocator = null,
    .io = null,
    .defaults = .{},
    .discovery = .explicit,
    .string_release = null,
    .declarations = &.{},
});
```

| 필드 | 기본값 | 의미 |
|---|---|---|
| `root` | 필수 | 모든 path와 type identity의 root module |
| `allocator` | `null` | allocator injection과 임시 변환 storage |
| `io` | `null` | `std.Io` injection 값 |
| `defaults.codepoints` | `null` | `.infer_u21` 또는 명시적 semantic |
| `defaults.strings` | `null` | `.infer_utf8` 또는 명시적 semantic |
| `discovery` | `.explicit` | explicit, public 또는 recursive 함수 선택 |
| `string_release` | `null` | caller-owned string의 기본 release function ref |
| `declarations` | `&.{}` | 함수, 타입, package와 interface entry |

injection 값은 `.c_allocator`, `.page_allocator`, `.smp_allocator` 또는
`.{ .path = "declaration.path" }`입니다.

## scope와 reference

```zig
const api = zigo.scope(library);
const nested = api.in("namespace");
```

| API | 결과 |
|---|---|
| `scope(Root)` | root container의 typed scope |
| `scope.in("Name")` | 중첩 public type 또는 namespace scope |
| `scope.ref("name")` | checked `FunctionRef` |
| `scope.typeRef("Name")` | checked `TypeRef` |
| `scope.func("name", options)` | function entry |
| `scope.funcs(selector)` | 선택한 function entry 목록 |

selector는 `.{ .names = &.{...} }` 또는
`.{ .public = .{ .prefix = "", .exclude = &.{...} } }`입니다.

## type entry

| API | Zig 대상 | 주요 option |
|---|---|---|
| `handle(name, options)` | struct, opaque 또는 union object | `fields` |
| `val(name, options)` | extern·packed struct | `fields`, `go` |
| `materialized(name, options)` | 일반 result struct | `fields` |
| `enumType(name, options)` | enum | `exhaustive`, `go`, `covers` |
| `taggedUnion(name, options)` | tagged union | `access`, `omit` |
| `callback(name, options)` | function pointer alias | parameter, userdata와 failure contract |

공통 entry method:

| method | 동작 |
|---|---|
| `.context()` | type option과 source scope를 가진 compile-time context 생성 |
| `.members(entries)` | 전체 member 목록 교체 |
| `.named(name)` | Go 이름 교체; `null`은 override 제거 |
| `.documented(doc)` | Go doc 교체; `null`은 override 제거 |
| `.with(.{...})` | 지정한 option field만 교체 |
| `.use(plugin, options)` | plugin을 중복 없이 추가 |
| `.replacePlugin(plugin, options)` | 같은 plugin option을 명시적으로 교체 |

type context는 `Target`, `source`, `func`, `funcs`, `ref`, `typeRef()`, `define()`과
`select()`를 제공합니다.

## function option

```zig
api.func("name", .{
    .name = null,
    .doc = null,
    .role = .auto,
    .params = &.{},
    .returns = .{},
    .covers = &.{},
    .symbol = null,
})
```

role:

```zig
.auto
.free
.{ .method = Type.typeRef() }
.{ .constructor = .{
    .type = Type.typeRef(),
    .receiver = .none, // .member 또는 .{ .type = ... }
    .parent = .none,   // 또는 .receiver
} }
.{ .destructor = Type.typeRef() }
```

## parameter

`.params`는 original Zig signature index 기반 sparse 목록입니다.

```zig
.{
    .index = 0,
    .go_name = null,
    .semantic = null,
    .go = null,
    .contract = .value,
}
```

contract helper:

| helper | contract |
|---|---|
| `zigo.param.input(index)` | input buffer |
| `zigo.param.output(index, written)` | output buffer |
| `zigo.param.inout(index, written)` | input/output buffer |
| `zigo.param.stream(index, buffer)` | `std.Io` adapter |
| `zigo.param.callback(index, options)` | callback lifetime와 오류 |
| `zigo.param.cancel(index, error_name)` | context cancellation |
| `zigo.param.flatten(index, fields)` | struct field를 Go parameter로 펼침 |

`Param.named(name)`은 helper가 만든 parameter의 Go 이름을 바꿉니다.

## 반환값

```zig
.{
    .lifetime = .inferred,
    .semantic = null,
    .go = null,
}
```

| helper | lifetime |
|---|---|
| `zigo.result.owned()` | caller가 소유하는 handle result |
| `zigo.result.releasedBy(ref)` | 지정 함수로 해제할 caller-owned buffer result |
| `zigo.result.borrowed()` | receiver 수명에 종속된 handle result |

semantic은 `.c_string`, `.opaque_bytes`, `.utf8_string`, `.codepoint`, `.integer`입니다.

## callback option

type entry와 call-site contract가 같은 field를 가질 수 있습니다. call site가 명시한 값이 해당
함수에서 우선합니다.

| 필드 | 의미 |
|---|---|
| `retention` | `.borrowed` 또는 `.retained` |
| `reentrancy` | `.allowed` 또는 `.forbidden` |
| `thread` | `.caller` 또는 `.any` |
| `go_error` | Go callback 결과에 `error` 추가 |
| `on_failure.result` | 실패·panic 때 Zig callback에 반환할 정수 값 |
| `userdata` | callback token 위치 |

## package와 interface

```zig
zigo.package(.{
    .path = "types",
    .name = null,
    .doc = null,
    .defaults = .{},
    .declarations = &.{},
})
```

```zig
zigo.interface(.{
    .name = "Resource",
    .methods = &.{"read"},
    .types = &.{File.typeRef(), Buffer.typeRef()},
    .closer = true,
    .doc = null,
})
```

## built-in feature

| attachment | 결과 |
|---|---|
| `.use(zigo.features.iterator, .{ .name = "All" })` | `iter.Seq`/`Seq2` wrapper |
| `.use(zigo.features.implements, .{ .kind = .reader })` | 표준 I/O method wrapper |
| `.use(zigo.features.text, .{})` | enum text encoding API |

외부 plugin의 연결과 option은 [plugin 문서](../plugins/README.md)를 참고하세요.
