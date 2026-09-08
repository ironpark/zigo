# 바인딩 작성

`bindings.zig`는 Zig 구현에서 어떤 API를 Go에 공개할지 선언하는 compile-time 문서입니다.
이 문서는 공통 구조를 설명하고 기능별 가이드로 안내합니다.

## 최소 선언

```zig
const zigo = @import("zigo");
const library = @import("mylib");

const api = zigo.scope(library);

pub const bindings = zigo.define(.{
    .root = library,
    .declarations = &.{
        api.func("add", .{}),
    },
});
```

`scope`에서 만드는 entry는 실제 Zig 선언을 compile time에 확인합니다. 존재하지 않는 함수나
타입을 문자열로 적어도 생성 단계까지 미뤄지지 않고 Zig compile error가 됩니다.

## 선언 트리

최상위 `.declarations`에는 네 종류의 entry를 넣을 수 있습니다.

| entry | 만드는 함수 | 용도 |
|---|---|---|
| 함수 | `api.func` | 자유 함수 또는 메서드 |
| 타입 | `api.handle`, `api.val`, `api.materialized`, `api.enumType`, `api.taggedUnion`, `api.callback` | Go 표현 선택 |
| 패키지 | `zigo.package` | 공개 Go 하위 패키지 |
| 인터페이스 | `zigo.interface` | 여러 handle의 공통 Go interface |

타입과 그 멤버는 한 트리로 묶는 것이 읽기 쉽습니다.

```zig
const Context = api.handle("Context", .{}).context();

pub const bindings = zigo.define(.{
    .root = library,
    .declarations = &.{
        Context.define(&.{
            Context.func("create", .{}),
            Context.func("add", .{}),
            Context.func("deinit", .{}),
        }),
    },
});
```

`context()`는 타입 entry의 옵션과 원래 Zig scope를 함께 보존합니다. `define()`은 전체 멤버
목록을 지정하고 `select()`는 selector로 멤버를 고릅니다.

## 공통 조합

- `.named("GoName")`: 생성 Go 이름을 바꿉니다.
- `.documented("...")`: 생성 문서 주석을 바꿉니다.
- `.with(.{ ... })`: 지정한 옵션만 교체합니다.
- `.members(&.{ ... })`: 타입의 멤버 목록 전체를 교체합니다.
- `.use(plugin, options)`: built-in feature 또는 외부 plugin을 붙입니다.
- `.replacePlugin(plugin, options)`: 같은 plugin의 기존 옵션을 명시적으로 교체합니다.

중첩 계약은 deep merge하지 않고 필드 전체를 교체합니다. 예를 들어 `.returns`를 새로 지정하면
이전 lifetime이나 release 설정이 암묵적으로 남지 않습니다.

## 기능별 가이드

- [함수와 패키지](functions-and-packages.md)
- [값과 데이터](values-and-data.md)
- [객체와 수명](objects-and-lifetimes.md)
- [콜백과 오류](callbacks-and-errors.md)
- [스트림과 취소](streams-and-cancellation.md)
- [Tagged union](tagged-unions.md)

모든 option과 entry field의 목록은 이후 [binding API 참조](../reference/binding-api.md)에서
확인합니다. 완전한 선언은 [예제 인덱스](../examples.md)에서 찾을 수 있습니다.
