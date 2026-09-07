# `bindings.zig` 선언

`bindings.zig`는 Zig API 중 무엇을 Go에 노출할지, 값과 객체를 어떻게 전달할지 정합니다.
빌드 연결은 [시작 가이드](getting-started.md), 이전 작성 API에서 옮기는 방법은
[작성 API 마이그레이션](migration-authoring.md)을 참고하세요.

## 기본 구조

`scope`는 실제 Zig 모듈에서 함수와 타입을 찾습니다. `declarations`에는 함수·타입·패키지를
하나의 트리로 적고, `define`이 이를 검증한 뒤 reflection에 전달합니다.

```zig
const zigo = @import("zigo");
const mylib = @import("mylib");
const api = zigo.scope(mylib);

pub const bindings = zigo.define(.{
    .root = mylib,
    .declarations = &.{
        api.func("add", .{}),
    },
});
```

`pub fn add(a: i32, b: i32) i32`는 `func Add(a int32, b int32) int32`가 됩니다.
기본값만 쓰는 함수에는 파라미터 목록을 반복하지 않아도 됩니다.

| Binding 필드 | 역할 |
|---|---|
| `root` | 바인딩할 Zig 모듈. `scope`의 루트와 같아야 함 |
| `declarations` | `[]const zigo.Entry`. 함수·타입·패키지·인터페이스 선언 |
| `defaults` | `strings`, `codepoints` 추론 기본값 |
| `discovery` | `.explicit` 기본값. `.public` 또는 `.recursive`는 명시적 opt-in |
| `allocator`, `io` | Zig 인자에 주입할 값 |
| `string_release` | caller-owned 문자열에 쓸 기본 해제 함수의 `FunctionRef` |

## 타입과 멤버

`in()`은 Zig namespace를 선택합니다. 타입의 `.members`는 Go receiver와 패키지 배치를
함께 정리하는 자리입니다. 실제 함수가 그 타입 안에 있을 필요는 없습니다.

```zig
const store = api.in("Store");

const store_entry = api.handle("Store", .{}).members(&.{
    store.func("create", .{}),
    store.func("len", .{}),
    store.func("deinit", .{}),
});

const storage = zigo.package(.{
    .path = "storage",
    .declarations = &.{store_entry},
});
```

`storage`를 바인딩의 `declarations`에 넣으면 됩니다. 같은 함수를 별도 목록에 다시 넣으면
중복 선언 오류입니다. 하위 패키지도 `declarations` 안에 중첩할 수 있습니다.

| 타입 helper | 용도 |
|---|---|
| `api.handle("T", options)` | Zig에 남는 객체와 수명주기 |
| `api.val("T", options)` | 적격한 `extern struct` 또는 정수 기반 `packed struct`의 Go 값 |
| `api.enumType("T", options)` | enum. `.exhaustive = false`로 열린 enum 허용 |
| `api.taggedUnion("T", options)` | tagged union. `.access = .projection` 또는 `.snapshot` |
| `api.materialized("T", options)` | 포인터를 포함한 결과 트리를 복사해 반환 |
| `api.callback("T", options)` | 공개 `*const fn` alias와 공통 콜백 계약 |

helper의 옵션은 표현별로 다릅니다. 공통 이름·문서·멤버는 `.named()`, `.documented()`,
`.members(entries)`로 설정합니다. 타입의 Go 기본 이름은 공개 Zig alias 이름입니다.

## 제네릭 타입 문맥

타입 이름과 source scope를 함께 관리하려면 타입 선언의 `.context()`를 사용합니다.
Context는 제네릭이 반환한 타입이며, `.define()` 또는 `.select()`가 기존 `Entry`를 만듭니다.

```zig
const Document = api.handle("Document", .{}).context();

const document = Document.define(&.{
    Document.func("create", .{}),
    Document.func("readInto", .{
        .params = &.{zigo.param.output(1, .result)},
    }),
    Document.func("deinit", .{}),
});
```

`document`를 `declarations`에 넣습니다. Context 타입인 `Document`를 직접 넣지는 않습니다.
타입 문맥은 대문자, 최종 선언 값은 소문자로 구분하면 읽기 쉽습니다.

| Context 항목 | 역할 |
|---|---|
| `Target` | 실제 Zig 대상 타입 |
| `source` | 원본 Scope. 중첩 namespace는 `source.in("nested")`로 접근 |
| `function(name, options)`, `functions(selector)` | 기존 source 함수 선언·선택 |
| `ref(name)` | 원본 함수 참조 |
| `typeRef()` | 현재 대상의 TypeRef. 이름을 다시 적지 않음 |
| `define(entries)` | 멤버 전체를 교체하고 타입 Entry 반환 |
| `select(selector)` | 함수 선택 결과를 멤버로 넣은 타입 Entry 반환 |

예를 들어 `Buffer.select(.{ .names = &.{ "create", "push", "len", "deinit" } })`로
공통 export 목록을 재사용할 수 있습니다. 이름·문서·plugin은 `.context()` 전 또는
`.define()` 후의 Entry에 적용하며, 기존 전체 교체 규칙이 유지됩니다.

Context 내부의 `Self = @This()`는 바인딩 문맥 타입입니다. 실제 대상 타입은 `Target`이며
Go 이름을 바꿔도 source 경로와 참조는 유지됩니다. 멤버의 receiver는 기존 normalizer가
결정하므로 root 함수도 `Document.define(&.{api.func("readDocument", .{})})`로 묶을 수
있습니다. 정적 생성자의 `.none`, 자식 생성자의 `.member` 규칙도 그대로입니다.

handle·value·enumeration·taggedUnion·materialized 선언에 사용할 수 있습니다.
callback은 함수 포인터여서 자체 멤버 문맥을 제공하지 않습니다.
기존 `.members()`도 계속 사용할 수 있습니다.

실제 작성 예시는 [콜백](../examples/04-callback/src/bindings.zig),
[event-queue](../examples/07-event-queue/src/bindings.zig),
[스트림](../examples/11-io-streams/src/bindings.zig),
[materialized](../examples/12-materialized/src/bindings.zig)를 참고하세요.
Context·selector·자동 발견의 조합은 [작성 기능별 예제](examples.md#바인딩-작성-기능별-예제)에서 찾을 수 있습니다.

## 계약과 참조

파라미터는 **receiver·allocator·userdata를 포함한 원본 Zig 인자 인덱스**로 선택합니다.
필요한 인자만 적으면 되며 나머지는 타입과 source에서 추론합니다.

```zig
// Zig: fn read(self: *Store, gpa: Allocator, dst: []u8) usize
const read = store.func("read", .{
    .params = &.{zigo.param.output(2, .result)},
});
```

| 계약 | 선택지 |
|---|---|
| `role` | `.auto`, `.free`, `.method`, `.constructor`, `.destructor` |
| `returns.lifetime` | `.inferred`, `.owned`, `.borrowed = .receiver`, `.library` |
| `Param.contract` | `.value`, `.buffer`, `.stream`, `.callback`, `.cancel`, `.flatten` |

`zigo.param`과 `zigo.result`는 기존 `Param`·`Returns` 값을 만드는 작은 helper입니다.
전체 schema literal과 함께 쓸 수 있고, 별도의 정규화나 계약 누적 규칙은 없습니다.
소스와 같은 이름은 생략하고 의도적으로 바꿀 때만 `go_name` 또는 `.named("name")`을 씁니다.

각 계약은 tagged union이므로 생성자와 소멸자, owned와 borrowed, stream과 callback 같은
서로 다른 역할을 동시에 적을 수 없습니다. 함수 참조는 `api.ref("release")`, 타입 참조는
`api.typeRef("Store")`로 만듭니다. Go 이름을 바꿔도 원본 Zig 참조는 유지됩니다.

`.with()`는 적은 필드만 교체하고 **명시적인 `null`은 기존 값을 지웁니다**. 중첩 계약은
전체를 교체하며 deep merge하지 않습니다. 예를 들어 `.returns`를 교체하면 이전 release가
새 lifetime에 남지 않습니다. `.members(entries)`도 기존 멤버 목록을 전체 교체합니다. 자세한 조합 예시는 [함수 문서](bindings-functions.md)에 있습니다.

## 기능과 플러그인

선언에 붙는 내장 기능과 외부 플러그인은 `.use()`로 연결합니다.

```zig
const next = store.func("next", .{}).use(zigo.features.iterator, .{});
const mode = api.enumType("Mode", .{}).use(zigo.features.text, .{});
```

내장 기능은 `iterator`, `implements`, `text`입니다. `Must*`는 빌드 옵션으로,
사용자 Go 인터페이스는 `zigo.interface(...)`로 선언합니다. 외부 플러그인의 대상별 옵션과
명시적 교체는 [플러그인 문서](plugins.md)를 참고하세요.

## 필요한 기능 찾아보기

| 하고 싶은 일 | 문서 |
|---|---|
| 함수 선택·이름·자동 발견·패키지 배치 | [함수 선택, 이름과 패키지](bindings-functions.md) |
| 정수·enum·struct·atomic·중첩 결과 | [값 타입과 결과 트리](bindings-types.md) |
| 생성자·소멸자·borrowed·부모와 자식·인터페이스 | [객체 수명과 Go 인터페이스](bindings-handles.md) |
| 문자열·반환 slice·버퍼·optional | [문자열, 슬라이스와 optional](bindings-buffers.md) |
| 콜백 수명·오류·panic | [콜백과 Go 오류 처리](bindings-callbacks.md) |
| Reader·Writer·취소 | [스트림과 취소](bindings-streams.md) |
| Union projection·snapshot | [Tagged union](bindings-unions.md) |

## 생성하고 확인하기

```bash
zig build go
zig build go-report
(cd go && go test ./...)
```

`go-report`에서 최종 Go 이름과 수명 결정을 확인합니다. 생성된 파일을 직접 수정하지 말고
바인딩 선언을 바꿔 다시 생성하세요. CI 연결은 [생성물과 CI 관리](generated-code.md),
지원 범위는 [제한사항](limitations.md)을 참고하세요.

## 짧은 선언 이름

작성 API는 `func(name, options)`, `funcs(selector)`, `val(name, options)`,
`enumType(name, options)`를 사용합니다. Context에서도 `func`와 `funcs`를 제공합니다.
기존 `function`·`functions`·`value`·`enumeration` 메서드는 이 이름으로 교체했습니다.
`enum`은 Zig 예약어이므로 enum 타입 선언에는 `enumType`을 사용합니다.
