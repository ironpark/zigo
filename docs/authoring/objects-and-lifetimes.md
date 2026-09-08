# 객체와 수명

이 가이드는 Zig가 소유하는 객체를 Go handle로 노출하고 생성, 대여와 해제 관계를 선언하는
방법을 설명합니다.

## handle 등록

opaque 또는 pointer로 다루는 객체 타입을 등록하고 멤버를 묶습니다.

```zig
const Context = api.handle("Context", .{}).context();

const context = Context.define(&.{
    Context.func("create", .{}),
    Context.func("add", .{}),
    Context.func("deinit", .{}),
});
```

일반적인 `create`/`init`, receiver method와 `deinit` 조합은 signature에서 역할을 추론합니다.
생성된 Go API는 대략 다음 형태입니다.

```text
func NewContext(...) (*Context, error)
func (c *Context) Add(...) error
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

## owned와 borrowed

handle 결과의 소유권은 누가 native 객체를 해제하는지를 정합니다.

- owned result는 독립된 Go handle이며 호출자가 `Close`합니다.
- borrowed result는 receiver가 소유하며 receiver보다 오래 사용할 수 없습니다.
- library-owned result는 사용자가 해제하지 않습니다.

```zig
Context.func("clone", .{
    .returns = zigo.result.owned(),
}),
Context.func("view", .{
    .returns = zigo.result.borrowed(),
}),
```

borrowed handle은 별도 `Ref` 형태로 생성될 수 있습니다. 부모가 닫히면 더 이상 사용할 수
없으며 borrowed value에서 `Close`를 호출해 native 객체를 해제하지 않습니다.

## 부모에 속한 child handle

receiver가 새 객체를 만들지만 child 수명이 부모에 종속된다면 constructor에 관계를
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

생성 handle은 호출이 진행 중인 동안 native pointer가 해제되지 않게 보호합니다. 같은 handle의
일반 메서드가 native 구현 자체를 thread-safe하게 만들어 주지는 않습니다. 다음 두 계약을
구분하세요.

- zigo runtime: 호출과 `Close` 사이의 pointer 수명 보호
- Zig 객체 구현: 여러 메서드 호출 사이의 데이터 동기화

`Close`는 여러 번 호출해도 안전한 종료 경로를 제공하지만, 이미 닫혔거나 사용 중인 handle의
오류는 `errors.Is`로 분류해야 합니다. finalizer cleanup은 누락을 줄이는 안전망이지 명시적
`Close`를 대신하지 않습니다.

Zig panic이 native frame을 비정상적으로 끝내면 객체는 안전하게 해제할 수 없다고 판단되어
poison 상태가 될 수 있습니다. 이후 사용과 해제가 제한되고 native allocation이 의도적으로
남을 수 있습니다.

## handle field accessor

단순 getter와 setter는 field path에서 생성할 수 있습니다.

```zig
api.handle("Palette", .{ .fields = &.{
    .{ .path = "flags", .set = true },
    .{ .path = "pinned_mode", .name = "pinnedMode", .set = true },
    .{ .path = "name", .doc = "Name reports the palette name." },
} })
```

중첩 path의 중간 값과 최종 field가 지원되는 shape인지 생성기가 검증합니다. 복잡한 mutation이나
추가 검증이 필요하면 Zig 메서드를 직접 작성하세요.

## iterator wrapper

`?T`를 순차 반환하는 receiver method에는 Go 1.23 `iter.Seq` 또는 `iter.Seq2` wrapper를
추가할 수 있습니다.

```zig
Context.func("next", .{})
    .use(zigo.features.iterator, .{}),

Context.func("nextChecked", .{})
    .use(zigo.features.iterator, .{ .name = "Checked" }),
```

원래 method도 유지되며 wrapper 이름은 충돌하지 않아야 합니다.

## 공통 interface

여러 handle이 같은 Zig method 집합을 제공하면 공개 Go interface를 만들 수 있습니다.

```zig
zigo.interface(.{
    .name = "CounterLike",
    .methods = &.{ "get", "add" },
    .types = &.{ Counter.typeRef(), Accumulator.typeRef() },
    .closer = true,
})
```

각 타입의 생성 Go signature가 실제로 호환되어야 합니다. `closer = true`이면 `Close() error`도
interface에 포함됩니다.

실행 예제는 [03-opaque](../../examples/03-opaque/README.md),
[07-event-queue](../../examples/07-event-queue/README.md)와
[09-type-relations](../../examples/09-type-relations/README.md)를 참고하세요.
