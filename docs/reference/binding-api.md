# 바인딩 API 참조

이 문서는 `bindings.zig`에서 사용하는 공개 authoring API의 필드와 도우미를 빠르게 찾기 위한
참조입니다. 학습 순서는 [바인딩 작성](../authoring/README.md)을 사용하세요.

## 최상위 바인딩

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
| `root` | 필수 | 모든 경로와 타입 식별 정보의 root 모듈 |
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
const nested = api.in("namespace");
```

| API | 결과 |
|---|---|
| `scope(Root)` | root container의 typed scope |
| `scope.in("Name")` | 중첩 공개 타입 또는 네임스페이스 scope |
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
| `val(name, options)` | extern·packed 구조체 | `fields`, `go` |
| `materialized(name, options)` | 일반 결과 구조체 | `fields` |
| `enumType(name, options)` | 열거형 | `exhaustive`, `go`, `covers` |
| `taggedUnion(name, options)` | tagged union | `access`, `omit` |
| `callback(name, options)` | 함수 포인터 alias | 매개변수, userdata와 failure 계약 |

공통 entry 메서드:

| 메서드 | 동작 |
|---|---|
| `.context()` | 타입 옵션과 소스 scope를 가진 컴파일 시점 context 생성 |
| `.members(entries)` | 전체 member 목록 교체 |
| `.named(name)` | Go 이름 교체; `null`은 override 제거 |
| `.documented(doc)` | Go doc 교체; `null`은 override 제거 |
| `.with(.{...})` | 지정한 옵션 필드만 교체 |
| `.use(plugin, options)` | 플러그인을 중복 없이 추가 |
| `.replacePlugin(plugin, options)` | 같은 플러그인 옵션을 명시적으로 교체 |

타입 context는 `Target`, `source`, `func`, `funcs`, `ref`, `typeRef()`, `define()`과
`select()`를 제공합니다.

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
    .contract = .value,
}
```

계약 도우미:

| 도우미 | 계약 |
|---|---|
| `zigo.param.input(index)` | 입력 버퍼 |
| `zigo.param.output(index, written)` | 출력 버퍼 |
| `zigo.param.inout(index, written)` | input/output 버퍼 |
| `zigo.param.stream(index, buffer)` | `std.Io` 어댑터 |
| `zigo.param.callback(index, options)` | 콜백 수명과 오류 |
| `zigo.param.cancel(index, error_name)` | context cancellation |
| `zigo.param.flatten(index, fields)` | 구조체 필드를 Go 매개변수로 펼침 |
| `zigo.param.options(index, fields, options)` | 구조체 필드를 Go functional options로 펼침 |

`zigo.param.options`의 `options` 사양:
- `.prefix: ?[]const u8 = null`: `With*` 함수 이름 및 옵션 타입 접두사 (`""` 지정 시 접두사 생략)
- `.type_name: ?[]const u8 = null`: 옵션 함수 타입 이름 명시적 지정

`Param.named(name)`은 도우미가 만든 매개변수의 Go 이름을 바꿉니다.

## 반환값

```zig
.{
    .lifetime = .inferred,
    .semantic = null,
    .go = null,
}
```

| 도우미 | 수명 |
|---|---|
| `zigo.result.owned()` | 호출자가 소유하는 핸들 결과 |
| `zigo.result.releasedBy(ref)` | 지정 함수로 해제할 caller-owned 버퍼 결과 |
| `zigo.result.borrowed()` | receiver 수명에 종속된 핸들 결과 |

semantic은 `.c_string`, `.opaque_bytes`, `.utf8_string`, `.codepoint`, `.integer`입니다.

## 콜백 옵션

타입 등록 옵션과 호출 지점의 계약을 구분합니다. `retention`, `reentrancy`, `thread`,
`on_failure`는 양쪽에서 사용할 수 있으며 호출 지점에 지정한 값이 우선합니다.
`go_error`는 `zigo.param.callback`의 호출 지점 전용 옵션입니다.

| 필드 | 의미 |
|---|---|
| `retention` | `.borrowed` 또는 `.retained` |
| `reentrancy` | `.allowed` 또는 `.forbidden` |
| `thread` | `.caller` 또는 `.any` |
| `go_error` | Go 콜백 결과에 `error` 추가 |
| `on_failure.result` | 실패·panic 때 Zig 콜백에 반환할 정수 값 |
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

## built-in feature

| 연결 | 결과 |
|---|---|
| `.use(zigo.features.iterator, .{ .name = "All" })` | `iter.Seq`/`Seq2` 래퍼 |
| `.use(zigo.features.implements, .{ .kind = .reader })` | 표준 I/O 메서드 래퍼 |
| `.use(zigo.features.text, .{})` | 열거형 text 인코딩 API |

외부 플러그인의 연결과 옵션은 [플러그인 문서](../plugins/README.md)를 참고하세요.
