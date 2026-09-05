# Tagged union 읽기와 값 전달

같은 `.repr = .tagged_union` 등록에서도 객체를 참조할지 값을 복사할지에 따라 API가 달라집니다.
선언의 기본 형태는 [`bindings.zig` 선언](bindings.md)을 참고하세요.

| 필요한 동작 | 표현 |
|---|---|
| union 객체에서 활성 payload 읽기 | [projection](#tagged-union-projection)의 `Tag`·`As*` |
| Go type switch로 payload 읽기 | [Variant](#variant-타입과-type-switch) |
| 작은 union을 한 번의 native 호출로 읽기 | [snapshot](#tagged-union-snapshot) |
| Zig 함수에 union 값 전달·반환 | [값 전달](#tagged-union-값-전달) |

## Tagged union projection

기본 표현은 union을 pointer handle로 유지하고 variant별 accessor를 생성합니다.

```zig
.types = .{
    .{ .type = mylib.Value, .repr = .tagged_union },
},
```

생성되는 주요 API는 다음과 같습니다.

- `ValueTag`, `Tag() (ValueTag, error)`, `MustTag()`
- payload variant별 `As<Variant>() (payload, bool, error)`
- payload variant별 `MustAs<Variant>() (payload, bool)`

active tag가 다르면 accessor는 `(zero, false, nil)`을 반환하고 payload를 읽지
않습니다. 기본 이름은 handle, native panic과 예기치 않은 status를 error로 반환합니다.
`Must*` 변형은 같은 typed error로 panic합니다.

지원 payload는 `void`, bool, 정수, float, enum, 등록 handle pointer, 숫자 slice입니다.
숫자 slice는 호출마다 Go memory로 복사하고, handle payload는 union wrapper에 수명이 묶인
borrowed `*TRef`입니다. union을 pointer handle로 쓰는 경우에는 이 규칙이 그대로 적용됩니다.

### Variant 타입과 type switch

같은 union에 sealed interface 표현도 함께 생성됩니다. `Tag()` 뒤에 맞는 `As*`를
찾아 부르는 대신 type switch 하나로 읽습니다.

- sealed interface `ValueVariant`
- variant별 concrete type `Value<Variant>`. payload는 exported field `Value`이고,
  payload가 없는 variant는 빈 struct입니다.
- `Variant() (ValueVariant, error)`와 `MustVariant()`

```go
switch active := value.MustVariant().(type) {
case ValueInteger:
    fmt.Println(active.Value)
case ValueChild:
    // borrowed *ChildRef. receiver가 열려 있는 동안만 유효합니다.
    use(active.Value)
case ValueNone:
    fmt.Println("none")
}
```

읽기 전용 표현이며 variant type으로 union을 만들거나 설정할 수는 없습니다. payload
사본과 수명 규칙은 `As*`와 같습니다. 숫자 slice는 호출마다 복사되고, handle payload는
receiver에 수명이 묶인 borrowed `*TRef`입니다. native 호출 횟수는 tag 한 번과 활성
variant의 projection 한 번이며, variant 수만큼 probe하지 않습니다.

variant type 이름이 이미 생성된 다른 이름과 겹치면 `Variant` 접미사, 그다음 숫자
접미사로 결정적으로 회피합니다.

## Tagged union snapshot

작고 모양이 고정된 scalar union을 자주 읽는다면 snapshot을 추가할 수 있습니다.

```zig
.types = .{
    .{ .type = mylib.Signal, .repr = .tagged_union, .access = .snapshot },
},
```

`Snapshot() (SignalSnapshot, error)`와 `MustSnapshot()`이 tag와 payload를 native 호출 한 번으로
가져옵니다. 기존 projection API도 그대로 남습니다.

```go
snapshot := signal.MustSnapshot()
if ticks, ok := snapshot.Ticks(); ok {
    fmt.Println(snapshot.Tag(), ticks)
}
```

snapshot을 쓰는 union은 `Variant()`도 이 한 번의 호출로 만들어집니다. tag를 따로
읽지 않습니다.

모든 payload가 `void`, bool, 정수/부동소수 scalar 또는 등록 enum이어야 합니다. 중첩
aggregate, slice, handle, optional, error union, callback은 `ZIGO011`로 거부됩니다. `tag`라는
variant 이름도 snapshot의 discriminant field와 충돌하므로 사용할 수 없습니다.

snapshot은 zigo 소유 `extern struct`의 전체 크기를 ABI로 고정합니다. variant 추가도 breaking
change입니다. variant가 늘 수 있으면 projection을, 모양이 고정되고 FFI 왕복을 줄여야 하면
snapshot을 선택하세요.

## Tagged union 값 전달

모든 payload가 `void`, bool, C로 표현 가능한 정수/부동소수 scalar, 등록 enum,
integer backing을 가진 `packed struct`, 또는 scalar/enum/그런 struct만 재귀적으로
포함하는 `extern struct`인 union은 함수의 전체 매개변수와 반환값으로 직접 전달할 수
있습니다.

```zig
pub const ScrollViewport = union(enum(u8)) {
    top,
    bottom,
    delta: isize,
    page: usize,
};

pub fn applyViewport(behavior: ScrollViewport) void { ... }
```

```go
ApplyViewport(ScrollViewportTop())
ApplyViewport(ScrollViewportDelta(-3))
```

이 값 표현은 `ScrollViewportTop()`, `ScrollViewportDelta(n)`처럼 variant별 constructor와
`Tag()` accessor를 제공합니다. handle 검사, ownership, poison 상태는 없습니다. C ABI에서는
tag 정수 뒤에 payload가 있는 각 variant의 slot을 선언 순서대로 붙이고, shim이 tag에 맞는
union 값을 재구성합니다. packed struct는 backing integer 하나로 전달하고, extern struct는
중첩된 leaf scalar slot으로 평탄화합니다. 따라서 variant 추가도 C signature를 늘리는 breaking
change입니다.

교차할 수 없는 variant는 등록에 `.omit_variants = .{ "unknown" }`을 지정해 C/Go
surface에서 제외할 수 있습니다. 남은 slice, pointer, auto-layout struct 같은 payload는
`ZIGO006`이 variant를 지목하고 `.omit_variants`를 안내합니다.
값 반환은 같은 tag/slot 순서의 zigo 소유 `extern struct`를 out parameter로 채웁니다.
반환된 active tag가 제외된 variant이면 Go는 `*Error`의 `OmittedVariant`를 받고
snapshot을 읽지 않습니다.
같은 등록 union을 pointer handle과 값 매개변수 양쪽 표현으로 동시에 쓰는 것은 지원하지
않으므로, 값 전달용 union을 별도 타입으로 선언해야 합니다. 다른 타입 안에 중첩된 union
값은 아직 지원하지 않습니다.

pointer projection 표현에서 기존 순서·tag·payload를 보존한 끝부분 variant 추가는 compatible
append입니다. 삭제, 재정렬, 이름·tag·payload 변경은 breaking입니다.
