# 값과 데이터

이 가이드는 Zig scalar, enum, struct, string, slice와 중첩 결과를 Go 값으로 표현하는 방법을
설명합니다. 전체 지원 조건은 [타입 대응 참조](../reference/type-mapping.md)가 정본입니다.

## 기본 scalar와 error union

지원되는 scalar는 등록 없이 함수 signature에서 변환됩니다.

```zig
pub fn divide(a: i32, b: i32) error{DivideByZero}!i32 {
    if (b == 0) return error.DivideByZero;
    return @divTrunc(a, b);
}
```

```text
func Divide(a int32, b int32) (int32, error)
```

Zig error tag는 생성된 `ErrDivideByZero`와 `errors.Is`로 판별할 수 있습니다.

## 값의 의미 지정하기

같은 integer나 byte pointer라도 API 의미에 따라 Go 표현이 달라집니다.

```zig
api.func("echo", .{
    .params = &.{.{ .index = 0, .semantic = .utf8_string }},
    .returns = .{ .semantic = .utf8_string },
})
```

지원 semantic은 다음과 같습니다.

| semantic | Go에서의 의미 |
|---|---|
| `.utf8_string` | UTF-8 `string` |
| `.c_string` | sentinel C string |
| `.opaque_bytes` | 의미를 해석하지 않는 `[]byte` |
| `.codepoint` | Go `rune` |
| `.integer` | 코드포인트 자동 추론을 막는 정수 |

프로젝트 전체에서 u21과 sentinel byte slice를 각각 codepoint와 UTF-8로 취급한다면 default를
설정할 수 있습니다.

```zig
.defaults = .{
    .codepoints = .infer_u21,
    .strings = .infer_utf8,
},
```

명시적인 function 또는 field semantic이 default보다 우선합니다.

## enum

```zig
api.enumType("Mode", .{})
```

생성 Go package에는 named integer type과 Zig tag에 대응하는 constant가 생깁니다.
알려지지 않은 값도 왕복해야 하는 open enum은 `.exhaustive = false`로 등록합니다.

```zig
api.enumType("Signal", .{ .exhaustive = false })
    .use(zigo.features.text, .{})
```

`features.text`는 parse, `MarshalText`와 `UnmarshalText`를 추가합니다.

## extern·packed struct 값

ABI가 값 전달에 적합한 struct는 `val`로 등록합니다.

```zig
api.val("Point", .{})
```

필드의 integer나 byte 의미가 자동으로 드러나지 않으면 sparse field hint를 붙입니다.

```zig
api.val("Record", .{ .fields = &.{
    .{ .name = "label", .semantic = .utf8_string },
} })
```

일반 Zig struct는 임의로 값 ABI에 넣지 않습니다. `extern struct`나 지원되는 `packed struct`
조건을 만족하지 않으면 handle 또는 materialized 결과를 선택하세요.

## Go 타입 adapter

public Go API에서 기존 타입을 사용하려면 변환 함수와 함께 adapter를 선언합니다.

```zig
api.val("Point", .{ .go = .{
    .type = "image.Point",
    .import = "image",
    .to_raw = "pointToRaw",
    .from_raw = "pointFromRaw",
} })
```

`to_raw`와 `from_raw` 함수는 사용자가 관리하는 같은 Go package 파일에 구현합니다. zigo는
함수 이름과 import를 생성하지만 사용자 변환 코드의 의미까지 검증하지는 않습니다.

## string과 slice 입력

Go string과 slice 입력은 호출 동안 native 코드에 빌려 줍니다. native 코드가 호출 뒤에도
pointer를 보관하면 안 됩니다. 장기 보관이 필요하면 Zig 쪽에서 복사하고 그 객체의 해제
경로를 따로 설계하세요.

buffer 방향을 명시해야 할 때 helper를 사용합니다.

```zig
api.func("transform", .{ .params = &.{
    zigo.param.input(0),
    zigo.param.output(1, .result),
} })
```

| helper | 의미 |
|---|---|
| `param.input(index)` | 읽기 전용 입력 buffer |
| `param.output(index, .all)` | 호출 성공 시 전체 buffer가 채워짐 |
| `param.output(index, .result)` | 함수 결과가 채운 element 수 |
| `param.inout(index, written)` | 입력을 읽고 같은 buffer에 결과 작성 |

`.result`를 사용하면 원래 Zig 반환값은 Go에서 `n`으로 소비되어야 하며 범위를 벗어난 값은
오류가 됩니다.

## caller-owned 결과

native allocation을 반환하는 slice나 string에는 해제 함수를 연결합니다.

```zig
const owned = zigo.result.releasedBy(api.ref("release"));

api.func("snapshot", .{ .returns = owned }),
api.func("release", .{}),
```

public wrapper는 결과를 Go memory로 복사하고 native release를 호출합니다. release 함수는
public Go API에 노출되지 않을 수 있지만 binding declaration에는 포함되어야 합니다.

## optional

지원되는 `?T`는 Go API의 형태에 따라 pointer, `value, ok`, 또는 nil 가능한 slice·handle로
표현됩니다. error union과 결합하면 `value, ok, error`가 될 수 있습니다. 구체적인 생성
signature는 `zig build go-report`와 생성 diff로 확인하세요.

## materialized 결과

중첩 pointer, slice와 string을 포함한 일반 struct 결과를 한 번의 native 호출로 복사하려면
`materialized`로 등록합니다.

```zig
api.materialized("Leaf", .{}),
api.materialized("Probe", .{ .fields = &.{
    .{ .name = "raw", .semantic = .opaque_bytes },
} }),
api.func("snapshot", .{
    .returns = zigo.result.releasedBy(api.ref("release")),
}),
```

결과 트리는 하나의 버퍼에 직렬화되고 Go decoder가 독립된 Go 값으로 만듭니다. 자주
접근하는 mutable native 객체에는 handle accessor가 더 적합할 수 있습니다.

실행 예제는 [02-errors](../../examples/02-errors/README.md),
[07-event-queue](../../examples/07-event-queue/README.md)와
[12-materialized](../../examples/12-materialized/README.md)를 참고하세요.
