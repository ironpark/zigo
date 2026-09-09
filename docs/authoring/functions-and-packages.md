# 함수와 패키지

이 가이드는 공개할 함수를 선택하고 생성 Go 이름, 메서드와 하위 패키지를 구성하는 방법을
설명합니다.

선언 조각은 별도 표시가 없으면 `src/bindings.zig`의 `zigo.define` 안에 있는
`.declarations` 목록에 넣습니다. `api`와 공통 import는 [최소 선언](README.md)을 사용합니다.
Go 호출 조각은 함수 본문용이며, 전체 import와 실행 방법은 연결된 예제를 참고하세요.

## 함수 하나를 끝까지 연결하기

[최소 예제의 Zig 구현](../../examples/00-quick-start/src/root.zig)은 다음 함수를 공개합니다.

```zig
pub fn add(a: i32, b: i32) i32 {
    return a + b;
}
```

바인딩의 `.declarations`에 `api.func("add", .{})`를 넣으면 공개 패키지에
`func Add(a int32, b int32) int32`가 생성됩니다. 예제의 Go 호출은 다음과 같습니다.

```go
fmt.Println(calculator.Add(2, 3)) // 5
```

`calculator`의 import 경로와 전체 프로그램은
[Go 실행 코드](../../examples/00-quick-start/go/cmd/demo/main.go)에 있습니다.
함수 이름을 바꾸려면 같은 선언에 `.name`을 추가하고 생성 결과를 확인합니다.

## 함수를 명시적으로 선택하기

가장 안전한 기본값은 공개할 함수를 하나씩 나열하는 것입니다.

```zig
const api = zigo.scope(library);

.declarations = &.{
    api.func("open", .{}),
    api.func("version", .{ .name = "VersionString" }),
},
```

`.name`은 Go 이름만 바꿉니다. Zig 선언 경로와 기본 C 심볼은 원래 선언의 식별 정보를
기준으로 검증됩니다. C ABI 이름까지 고정해야 할 때만 `.symbol`을 사용하세요.

## 네임스페이스와 타입 안으로 이동하기

`in()`은 중첩 container를 컴파일 시점에 선택합니다.

```zig
const text = api.in("text");
const unicode = text.in("unicode");

.declarations = &.{
    text.func("width", .{}),
    unicode.func("codepointWidth", .{}),
},
```

핸들이나 열거형 멤버를 작성할 때는 타입 entry에서 context를 만드는 편이 좋습니다.

```zig
const Counter = api.handle("Counter", .{}).context();

const counter = Counter.define(&.{
    Counter.func("create", .{}),
    Counter.func("add", .{}),
    Counter.func("deinit", .{}),
});
```

멤버 context의 함수는 Zig 시그니처와 소유 타입을 기준으로 receiver를 추론합니다. 원래
시그니처의 receiver도 매개변수 index에는 포함됩니다.

## 여러 함수를 선택하기

이름 목록이나 공개 함수 선택자를 사용할 수 있습니다.

```zig
const Buffer = api.handle("Buffer", .{}).context();

const buffer = Buffer.select(.{ .names = &.{
    "create",
    "push",
    "len",
    "deinit",
} });
```

```zig
const parser_functions = api.funcs(.{ .public = .{
    .prefix = "parse",
    .exclude = &.{"parseInternal"},
} });
```

선택자는 작성 시점의 선언을 펼쳐 고정합니다. 큰 API 전체를 의도적으로 공개할 때만 최상위
자동 발견을 사용하세요.

```zig
pub const bindings = zigo.define(.{
    .root = library,
    .discovery = .{ .public = .{
        .exclude = &.{api.ref("internalProbe")},
    } },
    .declarations = &.{ /* discovered API overrides */ },
});
```

`.recursive` discovery는 중첩 네임스페이스까지 탐색하므로 공개 surface가 예상보다 커질 수
있습니다. `zig build go-coverage`와 생성 diff를 함께 검토하세요.

## 함수 옵션

자주 쓰는 옵션은 다음과 같습니다.

```zig
api.func("process", .{
    .name = "ProcessBatch",
    .doc = "ProcessBatch validates and stores one batch.",
    .params = &.{
        .{ .index = 0, .go_name = "batch" },
    },
    .returns = .{},
})
```

- `.params`는 필요한 매개변수만 original Zig index로 지정하는 필요한 항목만 지정하는 목록입니다.
- `.returns`는 semantic, 수명과 Go 어댑터를 지정합니다.
- `.role`은 free 함수, 메서드, 생성자 또는 소멸자를 명시합니다.
- `.covers`는 이 래퍼가 대신하는 공개 Zig 함수를 coverage에 알려 줍니다.
- `.symbol`은 외부 ABI가 이미 정해진 경우에만 사용합니다.

## 자유 함수를 메서드로 만들기

Zig container 밖에 있는 함수도 첫 인자가 등록 타입이면 Go 메서드로 만들 수 있습니다.

```zig
api.func("counterAdd", .{
    .name = "add",
    .role = .{ .method = api.typeRef("Counter") },
})
```

생성자와 소멸자를 명시하는 방법은 [객체와 수명](objects-and-lifetimes.md)에서
설명합니다.

## 매개변수 일부를 펼치기

설정 구조체의 일부 필드만 Go 매개변수로 받고 나머지는 Zig 기본값을 유지할 수 있습니다.

```zig
Terminal.func("init", .{
    .params = &.{
        zigo.param.flatten(1, &.{ "cols", "rows", "max_scrollback_bytes" }),
    },
})
```

index는 receiver나 주입된 매개변수를 제거하기 전의 원래 Zig 시그니처 기준입니다.
`go-report`에서 최종 매개변수 구성을 확인하세요.

## 공개 Go 하위 패키지

관련 선언을 별도 패키지 entry로 묶습니다.

```zig
zigo.package(.{
    .path = "types",
    .name = "types",
    .doc = "Package types contains shared values.",
    .declarations = &.{
        api.enumType("Mode", .{}),
        api.val("Point", .{}),
        api.func("defaultMode", .{}),
    },
})
```

같은 소스 선언을 서로 다른 공개 패키지에 중복 배치하지 마세요. 타입 관계가 있는
선언은 함께 옮기고 생성된 import 관계를 Go 테스트로 확인합니다.

실행 예제는 [07-event-queue](../../examples/07-event-queue/src/bindings.zig)와
[08-telemetry-hub](../../examples/08-telemetry-hub/src/bindings.zig)를 참고하세요.
