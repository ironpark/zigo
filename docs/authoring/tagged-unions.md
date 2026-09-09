# Tagged union

이 가이드는 Zig tagged union을 Go에서 안전하게 검사하고 읽거나 값으로 전달하는 방법을
설명합니다.

## 등록

기본 표현은 native 객체를 가리키는 handle과 variant accessor입니다.

```zig
const Value = api.taggedUnion("Value", .{}).context();

const value = Value.select(.{ .names = &.{
    "create",
    "setInteger",
    "setFlag",
    "deinit",
} });
```

생성 package에는 tag enum, `Tag`, variant별 `As*`와 sealed variant interface가 생깁니다.

```go
tag, err := value.Tag()
n, ok, err := value.AsInteger()
variant, err := value.Variant()
```

`AsInteger`의 `ok`는 현재 tag가 integer인지 나타냅니다. tag를 따로 읽고 다시 accessor를
호출하면 두 호출 사이에 native 값이 바뀔 수 있으므로, 동시 변경 가능성이 있으면 snapshot을
사용하세요.

## projection

`.access = .projection`은 기본값입니다. 각 accessor가 현재 native payload를 읽습니다.

장점:

- 큰 payload에서 필요한 variant만 읽습니다.
- mutable union의 최신 상태를 볼 수 있습니다.

주의점:

- `Tag`와 `As*`는 별도 native 호출입니다.
- 반환 slice나 borrowed handle의 수명 규칙을 각각 따라야 합니다.

sealed `Variant()` 결과는 type switch에 적합합니다.

```go
switch item := variant.(type) {
case taggedunion.ValueInteger:
    fmt.Println(item.Value)
case taggedunion.ValueFlag:
    fmt.Println(item.Value)
}
```

## snapshot

한 시점의 tag와 payload를 함께 복사하려면 snapshot access를 선택합니다.

```zig
api.taggedUnion("Signal", .{ .access = .snapshot })
```

```go
snapshot, err := signal.Snapshot()
if err != nil {
    return err
}
ticks, ok := snapshot.AsTicks()
```

snapshot은 독립된 Go 값이므로 원래 handle의 이후 변경과 분리됩니다. 지원 payload 전체를
복사해야 하므로 큰 데이터에서 projection보다 비용이 클 수 있습니다.

## 값 tagged union

ABI-safe payload만 가진 tagged union은 함수 parameter나 결과에서 값으로 전달될 수 있습니다.
이 경우 생성 Go struct가 tag와 payload를 소유하며 accessor는 native 호출 없이 동작합니다.

pointer, slice, handle 또는 중첩 struct payload가 있으면 자동으로 값 ABI라고 가정하지 마세요.
[지원 범위](../reference/support-matrix.md)와 생성 진단을 확인해야 합니다.

## variant 제외

Go API에 공개할 수 없거나 의도적으로 숨길 variant는 `.omit`에 나열합니다.

```zig
api.taggedUnion("ScrollViewport", .{
    .omit = &.{"unknown"},
})
```

제외된 variant가 runtime에 나타날 가능성이 있다면 public API가 이를 어떻게 오류로 처리할지
함께 테스트하세요.

## payload별 주의사항

- scalar, bool과 등록 enum은 값으로 반환됩니다.
- slice와 string은 해당 ownership 및 semantic 계약을 따릅니다.
- handle payload는 owned인지 borrowed인지 union을 소유한 객체 관계로 판단합니다.
- mutable slice projection은 native mutation과 동시에 사용하지 않습니다.
- 지원되지 않는 payload는 명시적인 accessor 함수나 materialized 결과로 바꿉니다.

실행 가능한 projection, snapshot, `Variant()`와 JSON 확장은
[10-tagged-union](../../examples/10-tagged-union/README.md)에서 확인할 수 있습니다.
