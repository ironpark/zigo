# Tagged union

이 가이드는 Zig tagged union을 Go에서 안전하게 검사하고 읽거나 값으로 전달하는 방법을
설명합니다.

선언 조각은 별도 표시가 없으면 `src/bindings.zig`의 `zigo.define` 안에 있는
`.declarations` 목록에 넣습니다. `api`와 공통 import는 [최소 선언](README.md)을 사용합니다.
Go 호출 조각은 함수 본문용이며, 전체 import와 실행 방법은 연결된 예제를 참고하세요.

## 등록

기본 표현은 네이티브 객체를 가리키는 핸들과 variant 접근자입니다.

```zig
const Value = api.taggedUnion("Value", .{}).context();

const value = Value.select(.{ .names = &.{
    "create",
    "setFlag",
    "deinit",
} });
```

생성 패키지에는 태그 열거형, `Tag`, variant별 `As*`와 sealed variant 인터페이스가 생깁니다.

```go
tag, err := value.Tag()
n, ok, err := value.AsInteger()
variant, err := value.Variant()
```

`AsInteger`의 `ok`는 현재 태그가 정수인지 나타냅니다. 태그를 따로 읽고 다시 접근자를
호출하면 두 호출 사이에 네이티브 값이 바뀔 수 있습니다. 태그와 값을 함께 복사하려면
스냅샷을 선택하되, 복사 중 변경을 막는 동기화는 원래 라이브러리나 호출자가 제공해야 합니다.

[예제의 Zig 원본](../../examples/10-tagged-union/src/root.zig)에서 `Value`는
`union(enum(u8))`이며 `integer: i64`, `flag: bool` 등의 variant를 갖습니다.
`create(initial: i64)`는 정수 상태의 `*Value`를 만들고 `deinit`은 이를 해제합니다.
위 `value` 선언을 `.declarations`에 넣으면 다음처럼 호출할 수 있습니다.

```go
value, err := taggedunion.NewValue(42)
if err != nil {
    return err
}
defer value.Close()
n, ok, err := value.AsInteger()
if err != nil {
    return err
}
fmt.Println(n, ok) // 42 true
```

`taggedunion`은 `example.com/zigo/tagged_union/tagged_union`의 import 별칭입니다.
예제 원본의 모든 variant를 사용하려면 연결된
[전체 바인딩](../../examples/10-tagged-union/src/bindings.zig)처럼 `Mode`와 `Child`도 등록합니다.

## projection

`.access = .projection`은 기본값입니다. 각 접근자가 현재 네이티브 페이로드를 읽습니다.

장점:

- 큰 페이로드에서 필요한 variant만 읽습니다.
- 변경 가능한 union의 최신 상태를 볼 수 있습니다.

주의점:

- `Tag`와 `As*`는 별도 네이티브 호출입니다.
- 반환 슬라이스나 borrowed 핸들의 수명 규칙을 각각 따라야 합니다.

sealed `Variant()` 결과는 타입 switch에 적합합니다.

```go
switch item := variant.(type) {
case taggedunion.ValueInteger:
    fmt.Println(item.Value)
case taggedunion.ValueFlag:
    fmt.Println(item.Value)
}
```

## 스냅샷

한 시점의 태그와 페이로드를 함께 복사하려면 스냅샷 access를 선택합니다.

```zig
api.taggedUnion("Signal", .{ .access = .snapshot })
```

```go
snapshot, err := signal.Snapshot()
if err != nil {
    return err
}
ticks, ok := snapshot.Ticks()
```

스냅샷의 접근자는 `Ticks()`처럼 variant 이름을 사용합니다. 핸들의 `AsTicks()`와
구분하세요. 스냅샷은 독립된 Go 값이므로 원래 핸들의 이후 변경과 분리됩니다. 지원 페이로드 전체를
복사해야 하므로 큰 데이터에서 projection보다 비용이 클 수 있습니다.

## 값 tagged union

ABI-safe 페이로드만 가진 tagged union은 함수 매개변수나 결과에서 값으로 전달될 수 있습니다.
이 경우 생성 Go 구조체가 태그와 페이로드를 소유하며 접근자는 네이티브 호출 없이 동작합니다.

포인터, 슬라이스, 핸들 또는 중첩 구조체 페이로드가 있으면 자동으로 값 ABI라고 가정하지 마세요.
[지원 범위](../reference/support-matrix.md)와 생성 진단을 확인해야 합니다.

결과 자리는 union 그 자체와 union을 감싼 error union 둘입니다.

```zig
pub fn parse(text: []const u8) error{Invalid}!ScrollViewport { ... }
```

```go
func Parse(text string) (ScrollViewport, error)
```

Zig 오류는 평소처럼 `Err<Tag>` sentinel이 되고, `.omit`으로 뺀 variant가 실제로 돌아오면
그것과 구분되는 `OmittedVariant` 오류가 됩니다. 한 자리 더 들어간 곳 — `?Attribute`,
`[]Attribute` — 은 아직 ZIGO006으로 거절됩니다.

## variant 제외

Go API에 공개할 수 없거나 의도적으로 숨길 variant는 `.omit`에 나열합니다.

```zig
api.taggedUnion("ScrollViewport", .{
    .omit = &.{"unknown"},
})
```

제외된 variant가 런타임에 나타날 가능성이 있다면 공개 API가 이를 어떻게 오류로 처리할지
함께 테스트하세요.

## 페이로드별 주의사항

- 스칼라, bool과 등록 열거형은 값으로 반환됩니다.
- 슬라이스와 문자열은 해당 소유권 및 semantic 계약을 따릅니다.
- 핸들 페이로드는 owned인지 borrowed인지 union을 소유한 객체 관계로 판단합니다.
- 변경 가능한 슬라이스 projection은 네이티브 mutation과 동시에 사용하지 않습니다.
- 지원되지 않는 페이로드는 명시적인 접근자 함수나 materialized 결과로 바꿉니다.

실행 가능한 projection, 스냅샷, `Variant()`와 JSON 확장은
[10-tagged-union](../../examples/10-tagged-union/README.md)에서 확인할 수 있습니다.
