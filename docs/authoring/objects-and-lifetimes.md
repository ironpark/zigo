# 객체와 수명

이 가이드는 Zig가 소유하는 객체를 Go 핸들로 노출하고 생성, 대여와 해제 관계를 선언하는
방법을 설명합니다.

선언 조각은 별도 표시가 없으면 `src/bindings.zig`의 `zigo.define` 안에 있는
`.declarations` 목록에 넣습니다. `api`와 공통 import는 [최소 선언](README.md)을 사용합니다.
Go 호출 조각은 함수 본문용이며, 전체 import와 실행 방법은 연결된 예제를 참고하세요.

## 핸들 등록

opaque 또는 포인터로 다루는 객체 타입을 등록하고 멤버를 묶습니다.

```zig
const Context = api.handle("Context", .{}).context();

const context = Context.define(&.{
    Context.func("create", .{}),
    Context.func("add", .{}),
    Context.func("deinit", .{}),
});
```

일반적인 `create`/`init`, receiver 메서드와 `deinit` 조합은 시그니처에서 역할을 추론합니다.
[03-opaque의 Zig 구현](../../examples/03-opaque/src/root.zig)에서 `create`는
`CreateError!*Context`, `add(self: *Context, value: i64)`는 `i64`,
`deinit(self: *Context)`는 `void`를 반환합니다. 위 세 멤버를 등록하면 다음 API가 생성됩니다.

```text
func NewContext() (*Context, error)
func (c *Context) Add(value int64) (int64, error)
func (c *Context) Close() error
```

추론이 모호하거나 타입 밖의 함수를 묶을 때는 역할을 명시합니다.

```zig
api.func("newTicker", .{
    .role = .{ .constructor = .{ .type = Ticker.typeRef() } },
}),
api.func("tickerAdvance", .{
    .name = "advance",
    .role = .{ .method = Ticker.typeRef() },
}),
api.func("freeTicker", .{
    .role = .{ .destructor = Ticker.typeRef() },
}),
```

## 생성한 객체 호출하기

[03-opaque의 호출 예제](../../examples/03-opaque/go/opaque/example_test.go)처럼
생성 오류를 확인한 다음 소유한 객체의 정리를 예약합니다.

```go
counter, err := opaque.NewContext()
if err != nil {
    return err
}
defer counter.Close()

total, err := counter.Add(3)
if err != nil {
    return err
}
fmt.Println(total) // 3
```

이 조각은 `error`를 반환하는 함수 본문용입니다. 정리 오류도 작업 결과에 반영해야 하는
애플리케이션에서는 `defer` 함수에서 `Close`의 오류를 처리하거나 명시적으로 닫으세요.
Zig의 `add`는 오류를 반환하지 않지만 Go 메서드는 핸들 유효성 검사 때문에 `error`를 반환합니다.

## owned와 borrowed

핸들 결과의 소유권은 누가 네이티브 객체를 해제하는지를 정합니다.

- owned 결과는 독립된 Go 핸들이며 호출자가 `Close`합니다.
- borrowed 결과는 receiver가 소유하며 receiver보다 오래 사용할 수 없습니다.
- 라이브러리-owned 결과는 사용자가 해제하지 않습니다.

```zig
Context.func("clone", .{
    .returns = zigo.result.owned(),
}),
Context.func("view", .{
    .returns = zigo.result.borrowed(),
}),
```

borrowed 핸들은 별도 `Ref` 형태로 생성될 수 있습니다. 부모가 닫히면 더 이상 사용할 수
없으며 borrowed value에서 `Close`를 호출해 네이티브 객체를 해제하지 않습니다.

## 부모에 속한 child 핸들

receiver가 새 객체를 만들지만 child 수명이 부모에 종속된다면 생성자에 관계를
명시합니다.

```zig
Parent.func("newChild", .{
    .role = .{ .constructor = .{
        .type = Child.typeRef(),
        .receiver = .member,
        .parent = .receiver,
    } },
})
```

부모 `Close`는 진행 중인 호출과 child 사용이 끝날 때까지 조정됩니다. 부모와 child를 서로
다른 goroutine에서 닫는 코드는 항상 반환 오류를 처리해야 합니다.

## 동시 호출과 `Close`

생성 핸들은 호출이 진행 중인 동안 네이티브 포인터가 해제되지 않게 보호합니다. 같은 핸들의
일반 메서드가 네이티브 구현 자체를 동시 호출에 안전하게 만들어 주지는 않습니다. 다음 두 계약을
구분하세요.

- zigo 런타임: 호출과 `Close` 사이의 포인터 수명 보호
- Zig 객체 구현: 여러 메서드 호출 사이의 데이터 동기화

`Close`는 여러 번 호출해도 안전한 종료 경로를 제공하지만, 이미 닫혔거나 사용 중인 핸들의
오류는 `errors.Is`로 분류해야 합니다. 자동 정리는 누락을 줄이는 안전망이지 명시적
`Close`를 대신하지 않습니다.

Zig panic이 네이티브 호출 프레임을 비정상적으로 끝내면 객체는 안전하게 해제할 수 없다고 판단되어
poison 상태가 될 수 있습니다. 이후 사용과 해제가 제한되고 네이티브 할당이 의도적으로
남을 수 있습니다.

## 핸들 필드 접근자

단순 getter와 setter는 필드 경로에서 생성할 수 있습니다.

```zig
api.handle("Palette", .{ .fields = &.{
    .{ .path = "flags", .set = true },
    .{ .path = "pinned_mode", .name = "pinnedMode", .set = true },
    .{ .path = "name", .doc = "Name reports the palette name." },
} })
```

중첩 경로의 중간 값과 최종 필드가 지원되는 shape인지 생성기가 검증합니다. 복잡한 mutation이나
추가 검증이 필요하면 Zig 메서드를 직접 작성하세요.

## iterator 래퍼

`?T`를 순차 반환하는 receiver 메서드에는 `iter.Seq` 또는 `iter.Seq2` 래퍼를
추가할 수 있습니다.

```zig
Context.func("next", .{})
    .use(zigo.features.iterator, .{}),

Context.func("nextChecked", .{})
    .use(zigo.features.iterator, .{ .name = "Checked" }),
```

원래 메서드도 유지되며 래퍼 이름은 충돌하지 않아야 합니다.

## 공통 인터페이스

여러 핸들이 같은 Zig 메서드 집합을 제공하면 공개 Go 인터페이스를 만들 수 있습니다.

```zig
zigo.interface(.{
    .name = "CounterLike",
    .methods = &.{ "get", "add" },
    .types = &.{ Counter.typeRef(), Accumulator.typeRef() },
    .closer = true,
})
```

각 타입의 생성 Go 시그니처가 실제로 호환되어야 합니다. `closer = true`이면 `Close() error`도
인터페이스에 포함됩니다.

실행 예제는 [03-opaque](../../examples/03-opaque/README.md),
[07-event-queue](../../examples/07-event-queue/README.md)와
[09-타입-relations](../../examples/09-type-relations/README.md)를 참고하세요.
