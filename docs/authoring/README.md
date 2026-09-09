# 바인딩 작성

`bindings.zig`는 Zig 구현에서 어떤 API를 Go에 공개할지 선언하는 컴파일 시점 문서입니다.
이 문서는 공통 구조를 설명하고 기능별 가이드로 안내합니다.

## Go에 어떤 형태로 공개할까요?

| 필요한 동작 | 선언 | 수명과 비용 |
|---|---|---|
| 숫자·불리언을 함수 인자와 결과로 전달 | `api.func` | 지원 스칼라는 별도 타입 등록 없이 변환 |
| 열거형 또는 ABI에 적합한 작은 구조체 전달 | `api.enumType`, `api.val` | Go 값으로 사용; 지원 필드·위치는 타입 참조 확인 |
| 상태를 변경하며 같은 객체를 여러 번 호출 | `api.handle` | 네이티브 객체를 유지; 소유한 핸들은 `Close` 필요 |
| 포인터·문자열·슬라이스가 중첩된 결과를 한 번에 읽기 | `api.materialized` | Go 소유 값으로 복사; 직렬화 버퍼 해제 계약 필요 |
| 현재 태그에 따라 다른 데이터를 읽기 | `api.taggedUnion` | 값·projection·스냅샷별 지원 조건과 비용 확인 |

일반 Zig 구조체를 값으로 전달하기 위해 무조건 `extern`으로 바꾸지는 마세요.
원래 라이브러리의 메모리 배치와 사용 방식을 유지하면서 적합한 표현을 선택합니다.

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

`scope`에서 만드는 entry는 실제 Zig 선언을 컴파일 시점에 확인합니다. 존재하지 않는 함수나
타입을 문자열로 적어도 생성 단계까지 미뤄지지 않고 Zig 컴파일 error가 됩니다.

## 선언 트리

최상위 `.declarations`에는 네 종류의 entry를 넣을 수 있습니다.

| entry | 만드는 함수 | 용도 |
|---|---|---|
| 함수 | `api.func` | 자유 함수 또는 메서드 |
| 타입 | `api.handle`, `api.val`, `api.materialized`, `api.enumType`, `api.taggedUnion`, `api.callback` | Go 표현 선택 |
| 패키지 | `zigo.package` | 공개 Go 하위 패키지 |
| 인터페이스 | `zigo.interface` | 여러 핸들의 공통 Go 인터페이스 |

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
목록을 지정하고 `select()`는 선택자로 멤버를 고릅니다.

## 공통 조합

- `.named("GoName")`: 생성 Go 이름을 바꿉니다.
- `.documented("...")`: 생성 문서 주석을 바꿉니다.
- `.with(.{ ... })`: 지정한 옵션만 교체합니다.
- `.members(&.{ ... })`: 타입의 멤버 목록 전체를 교체합니다.
- `.use(plugin, options)`: built-in feature 또는 외부 플러그인을 붙입니다.
- `.replacePlugin(plugin, options)`: 같은 플러그인의 기존 옵션을 명시적으로 교체합니다.

중첩 계약은 deep merge하지 않고 필드 전체를 교체합니다. 예를 들어 `.returns`를 새로 지정하면
이전 수명이나 해제 설정이 암묵적으로 남지 않습니다.

## 기능별 가이드

- [함수와 패키지](functions-and-packages.md)
- [값과 데이터](values-and-data.md)
- [객체와 수명](objects-and-lifetimes.md)
- [콜백과 오류](callbacks-and-errors.md)
- [스트림과 취소](streams-and-cancellation.md)
- [Tagged union](tagged-unions.md)

모든 옵션과 entry 필드의 목록은 이후 [바인딩 API 참조](../reference/binding-api.md)에서
확인합니다. 완전한 선언은 [예제 인덱스](../examples.md)에서 찾을 수 있습니다.
