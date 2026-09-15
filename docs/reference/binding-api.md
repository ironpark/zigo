# 바인딩 API 참조

이 문서는 `bindings.zig`에서 사용하는 공개 authoring API의 필드와 도우미를 빠르게 찾기 위한
참조입니다. 학습 순서는 [바인딩 작성](../authoring/README.md)을 사용하세요.

## 최상위 바인딩

```zig
const api = zigo.scope(library);

pub const bindings = zigo.define(api, .{
    .allocator = null,
    .io = null,
    .defaults = .{},
    .discovery = .explicit,
    .string_release = null,
    .declarations = &.{},
});
```

root 모듈은 `zigo.scope(library)`가 한 번 말하고, `zigo.define`은 그 scope를 첫 인자로 받습니다.

| 필드 | 기본값 | 의미 |
|---|---|---|
| `allocator` | `null` | allocator 주입과 임시 변환 storage |
| `io` | `null` | `std.Io` 주입 값 |
| `defaults.codepoints` | `null` | `.infer_u21` 또는 `.explicit`; `null`은 최상위에서 `.explicit`, 하위 패키지에서 상위 설정 상속 |
| `defaults.strings` | `null` | `.infer_utf8` 또는 `.explicit`; `null`은 최상위에서 `.explicit`, 하위 패키지에서 상위 설정 상속 |
| `discovery` | `.explicit` | explicit, 공개 또는 recursive 함수 선택 |
| `string_release` | `null` | caller-owned 문자열의 기본 해제 함수 ref |
| `declarations` | `&.{}` | 함수, 타입, 패키지와 인터페이스 entry |

allocator 주입에는 `.c_allocator`, `.page_allocator`, `.smp_allocator` 또는
`.{ .path = "declaration.path" }`를 사용합니다. `io`에는 `std.Io` 값을 제공하는 선언의
`.{ .path = "declaration.path" }`를 지정합니다.

## scope와 reference

```zig
const api = zigo.scope(library);
const nested = api.namespace("namespace");
```

| API | 결과 |
|---|---|
| `scope(Root)` | root container의 typed scope |
| `scope.namespace("name")` | 중첩 네임스페이스(struct container) scope. 등록 타입의 멤버는 `.context()`로 접근합니다 |
| `scope.ref("name")` | checked `FunctionRef` |
| `scope.typeRef("Name")` | checked `TypeRef` |
| `scope.func("name", options)` | 함수 entry |
| `scope.funcs(selector)` | 선택한 함수 entry 목록 |

선택자는 `.{ .names = &.{...} }` 또는
`.{ .public = .{ .prefix = "", .exclude = &.{...} } }`입니다.

## 타입 entry

| API | Zig 대상 | 주요 옵션 |
|---|---|---|
| `handle(name, options)` | 구조체, opaque 또는 union 객체 | `fields` |
| `value(name, options)` | extern·packed 구조체 | `fields`, `go` |
| `materialized(name, options)` | 일반 결과 구조체 | `fields` |
| `enumeration(name, options)` | 열거형 | `exhaustive`, `text`, `go`, `covers`, `fields` |
| `taggedUnion(name, options)` | tagged union | `access`, `omit` |
| `callback(name, options)` | 함수 포인터 alias | 매개변수, userdata와 `contract` |

`enumeration`의 `.text = true`는 `Parse<Enum>`, `MarshalText`와 `UnmarshalText`를 생성합니다.

`fields`는 멤버별 hint와 문서입니다.

```zig
api.value("RenderCell", .{ .fields = &.{
    .{ .name = "text", .semantic = .utf8_string },
    .{ .name = "fg", .doc = "0xRRGGBB." },
} }),
api.enumeration("CursorStyle", .{ .fields = &.{
    .{ .name = "block", .doc = "The filled cell the terminal starts in." },
} }),
```

| 필드 | 의미 |
|---|---|
| `name` | Zig 필드 또는 태그 이름. 없는 이름을 적으면 컴파일 시점에 거절됩니다 |
| `semantic` | 필드의 semantic hint (`value`·`materialized`만) |
| `doc` | 그 멤버의 Go doc |

멤버 문서의 우선순위는 `.doc` → Zig 소스의 `///` → 생성기의 기본 문장입니다. 태그를
테이블에서 만드는 enum처럼 소스에 `///`를 붙일 자리가 없는 타입은 `.doc`이 유일한
경로입니다.

공통 entry 메서드:

| 메서드 | 동작 |
|---|---|
| `.context()` | 타입 옵션과 소스 scope를 가진 컴파일 시점 context 생성 |
| `.with(.{ .name, .doc })` | 지정한 옵션 필드만 교체; `null`은 override 제거 |
| `.use(plugin, options)` | 플러그인을 중복 없이 추가 |
| `.replacePlugin(plugin, options)` | 같은 플러그인 옵션을 명시적으로 교체 |

선언뿐 아니라 선언 안쪽의 node에도 플러그인을 붙일 수 있습니다. `.use`는 모두 같은
규칙입니다: 옵션은 그 node에 해당하는 플러그인 옵션 타입으로 comptime 검사되고, 같은
플러그인을 두 번 붙이면 컴파일 error입니다.

| 위치 | 연결 | 옵션 타입 |
|---|---|---|
| 매개변수 | `zigo.param.input(1).use(P, .{ ... })` | `P.ParamOptions` |
| 반환값 | `zigo.result.owned().use(P, .{ ... })` | `P.ResultOptions` |
| 구조체 field | `(zigo.ValueField{ .name = "x" }).use(P, .{ ... })` | `P.FieldOptions` |
| enum tag | `(zigo.EnumField{ .name = "idle" }).use(P, .{ ... })` | `P.TagOptions` |
| handle field | `(zigo.HandleField{ .path = "x" }).extend(P, .{ ... })` | `P.FunctionOptions` |

플러그인 옵션 field의 타입이 `plugin.ref.*`이면 그 자리에는 이름 문자열이 아니라 선언을
씁니다. 위 표의 모든 자리가 같습니다: 선언의 `use`도, 매개변수·반환값·field·enum tag·handle
field의 `use`와 `extend`도 이 형태를 받습니다.

| 옵션 field 타입 | 바인딩이 쓰는 값 |
|---|---|
| `plugin.ref.Type` | `api.typeRef("Context")` 또는 `Handle.typeRef()` |
| `plugin.ref.Function` | `api.ref("open")` 또는 `Handle.ref("close")` |
| `plugin.ref.Interface` | `.{ .entry = readable }`(= `zigo.interface(...)`가 돌려준 entry) 또는 `.{ .name = "Readable" }` |

optional과 slice도 같은 방식으로 적습니다.

```zig
const readable = zigo.interface(.{ .name = "Readable", .methods = &.{"read"}, .types = &.{api.typeRef("Counter")} });
const Counter = api.handle("Counter", .{}).context();

Counter.members(&.{api.func("read", .{})}).use(refs.plugin, .{
    .target = api.typeRef("Context"),
    .satisfies = &.{.{ .entry = readable }},
})
```

참조는 선언 시점에 검사합니다. 종류가 맞지 않거나 다른 `zigo.define`의 선언을 가리키면
컴파일 error입니다. `semantic.json`에는 Go 이름이 아니라 native Zig path가 실리므로 이후의
rename이 해석을 깨뜨리지 않고, 가리키는 선언이 없으면 생성 시점에 `<NAME>002` 진단이
나옵니다.

handle field는 getter와 setter 함수로 펼쳐지므로 함수 옵션을 받으며, 두 함수가 모두
같은 옵션을 가집니다. 붙인 옵션은 `semantic.json`의 해당 node `ext`에 실려 플러그인에
전달됩니다. 플러그인이 `subjects`로 선언하지 않은 node에 붙이면 그 자리에서 컴파일
error입니다.

타입 context는 `Target`, `source`, `func`, `funcs`, `ref`, `typeRef()`, `members(entries)`와
`select(selector)`를 제공합니다. 멤버는 `.context().members(...)` 또는 `.select(...)`로만
선언합니다.

## 함수 옵션

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

## 매개변수

`.params`는 original Zig 시그니처 index 기반 필요한 항목만 지정하는 목록입니다.

```zig
.{
    .index = 0,
    .go_name = null,
    .semantic = null,
    .go = null,
}
```

값이 아닌 계약은 도우미로만 적습니다. 도우미는 완성된 `Param`을 돌려주므로 `.index`와
계약을 함께 정합니다.

| 도우미 | 계약 |
|---|---|
| `zigo.param.input(index)` | 입력 버퍼 |
| `zigo.param.output(index, written)` | 출력 버퍼 |
| `zigo.param.inout(index, written)` | input/output 버퍼 |
| `zigo.param.stream(index, buffer)` | `std.Io` 어댑터 |
| `zigo.param.callback(index, site)` | 콜백 호출 지점 계약 (`contract`, `go_error`, `userdata`) |
| `zigo.param.cancel(index, error_name)` | context cancellation |
| `zigo.param.flatten(index, fields)` | 구조체 필드를 Go 매개변수로 펼침 |
| `zigo.param.options(index, fields, options)` | 구조체 필드를 Go functional options로 펼침 |

`zigo.param.options`의 `options` 사양:
- `.prefix: ?[]const u8 = null`: `With*` 함수 이름 및 옵션 타입 접두사. 기본은 소유 타입 이름(`TerminalOption`, `WithTerminalRows`)이고 `""`를 지정하면 접두사를 생략합니다(opt-in)
- `.type_name: ?[]const u8 = null`: 옵션 함수 타입 이름 명시적 지정

`Param.named(name)`은 도우미가 만든 매개변수의 Go 이름을 바꾸고,
`Param.use(plugin, options)`는 그 매개변수에 플러그인 옵션을 붙입니다.

## 반환값

```zig
.{
    .semantic = null,
    .go = null,
}
```

소유권은 도우미로만 적습니다. 도우미는 완성된 `Returns`를 돌려주며, `.returns`를 새로 지정하면
이전 해제 참조는 남지 않습니다. `Returns.use(plugin, options)`는 그 결과에 플러그인 옵션을
붙입니다.

| 도우미 | 소유권 |
|---|---|
| `zigo.result.owned()` | 호출자가 소유하는 핸들 결과 |
| `zigo.result.releasedBy(ref)` | 지정 함수로 해제할 caller-owned 버퍼 결과 |
| `zigo.result.borrowed()` | receiver 수명에 종속된 핸들 결과 |

semantic은 `.c_string`, `.opaque_bytes`, `.utf8_string`, `.codepoint`, `.integer`입니다.

## 콜백 옵션

콜백 타입 등록과 호출 지점은 같은 `CallbackContract`를 `.contract`로 받습니다. 타입에 적은
값이 기본이고, 호출 지점이 적은 필드가 그 필드만 덮어씁니다.

```zig
api.callback("Observer", .{
    .params = &.{},
    .returns = .{ .semantic = null },
    .userdata = null,
    .contract = .{ .retention = .retained, .on_failure = .{ .result = 0 } },
}),
api.func("apply", .{ .params = &.{
    zigo.param.callback(1, .{ .contract = .{ .retention = .borrowed }, .go_error = true }),
} }),
```

| 필드 | 의미 |
|---|---|
| `contract.retention` | `.borrowed` 또는 `.retained` |
| `contract.reentrancy` | `.allowed` 또는 `.forbidden` |
| `contract.thread` | `.caller` 또는 `.any` |
| `contract.on_failure.result` | 실패·panic 때 Zig 콜백에 반환할 정수 값 |
| `go_error` | 호출 지점 전용. Go 콜백 결과에 `error` 추가 |
| `userdata` | 타입 등록: `.first`, `.last`, `.{ .index = n }`; 호출 지점: 원래 Zig 함수의 토큰 인자 인덱스 |

## 패키지와 인터페이스

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

```zig
zigo.session(.{
    .name = "Session",
    .primary = Parent.typeRef(),
    .children = &.{
        .{ .type = Child.typeRef() },
        .{ .type = Search.typeRef(), .accessor = "Searches" },
    },
    .doc = null,
})
```

| 필드 | 의미 |
|---|---|
| `name` | 생성할 Go 타입 이름. primary 접근자는 그 타입 이름을 그대로 씁니다 |
| `primary` | 마지막에 닫히는 주 핸들. `.handle`로 등록된 타입이어야 합니다 |
| `children` | primary가 `.parent = .receiver`로 내주는 자식 핸들 목록 |
| `children[].type` | 자식 핸들 타입. `.handle`로 등록되어 있어야 합니다 |
| `children[].accessor` | 접근자 이름 전체. 기본값은 타입 이름 + `s` |
| `doc` | 생성 타입의 doc comment. 닫는 순서는 생성기가 별도로 적습니다 |

입양 메서드는 항상 `Add<Type>`입니다. 접근자는 타입 이름에 `s`를 붙이므로, 그 규칙으로
닿지 않는 복수는 `.accessor`로 이름을 그대로 적습니다. `Search`는 `.accessor = "Searches"`가
필요하고, `Stats` 같은 이미 복수인 타입은 `.accessor = "Stats"`로 `Statss`를 피합니다.

## built-in feature

| 연결 | 결과 |
|---|---|
| `.use(zigo.features.iterator, .{})` | `iter.Seq`/`Seq2` 래퍼. 이름은 `.name`, 기본은 `All`(메서드가 `Checked`로 끝나면 `AllChecked`) |
| `.use(zigo.features.implements, .{ .kinds = &.{.reader} })` | 표준 I/O 메서드 래퍼. kind는 `.writer`, `.reader`, `.writer_to`, `.reader_from`, `.string_writer`이며 항상 목록으로 적습니다. `.string_writer`는 string semantic이 있으면 인자를 그대로, 없으면 string의 바이트를 빌려 넘깁니다. 래퍼만 공개되며 bound 메서드는 숨겨집니다. `.keep_original = true`면 원래 이름도 함께 내보냅니다 |

열거형 text 인코딩은 feature가 아니라 `enumeration`의 `.text = true` 옵션입니다.

외부 플러그인의 연결과 옵션은 [플러그인 문서](../plugins/README.md)를 참고하세요.
