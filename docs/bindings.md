# `bindings.zig` 선언

`bindings.zig`는 Zig 구현을 수정하지 않고 Go에 노출할 API와 reflection만으로 알 수 없는
의미를 선언하는 파일입니다. 빌드 연결은 [빌드 설정](configuration.md), 지원하지 않는 타입은
[지원 범위와 제한사항](limitations.md)을 참고하세요.

## 기본 구조

```zig
const zigo = @import("zigo");
const mylib = @import("mylib");

pub const bindings = zigo.define(.{
    .root = mylib,
    .types = .{
        .{ .type = mylib.Context, .repr = .@"opaque" },
    },
    .functions = .{
        .{ .path = "Context.create", .params = .{"name"} },
        .{ .path = "Context.deinit" },
        .{ .path = "root.version" },
    },
});
```

| 그룹 | 역할 |
|---|---|
| `root` | 경로를 해석할 기준 module. 항상 필요 |
| `types` | opaque handle, extern struct 값, tagged union 등록 |
| `functions` | 노출할 함수와 추가 메타데이터 |

`root.<name>`은 module 자유 함수를, `<Type>.<name>`은 등록 타입의 함수를 가리킵니다. 경로가
공개 함수를 가리키지 않으면 compile error입니다. 함수 항목의 `.name`은 경로가 아니라 생성할
Go 이름만 바꿉니다.

## 명시 목록과 자동 발견

안정적인 공개 API가 중요하다면 `functions`에 함수를 명시하세요. 목록에 없는 함수는 노출되지
않으므로 Zig의 새 `pub fn`이 의도치 않게 Go ABI에 들어오지 않습니다.

Zig 공개 API 전체가 바인딩 API인 큰 module은 자동 발견을 선택할 수 있습니다.

```zig
pub const bindings = zigo.define(.{
    .root = mylib,
    .discover = .public,
    .types = .{
        .{ .type = mylib.Context, .repr = .@"opaque" },
    },
    .functions = .{
        // 자동 발견된 함수에 메타데이터를 보강합니다.
        .{ .path = "Context.name", .semantic = .utf8_string },
    },
    .exclude = .{"Context.debugState"},
});
```

자동 발견은 등록한 타입의 공개 함수, 이어서 `root` module의 공개 함수를 찾습니다.
`functions`는 발견 대상을 제한하지 않고 메타데이터를 붙이며, `exclude`가 제외 대상을
지정합니다. 존재하지 않거나 중복된 경로, `functions`와 `exclude`의 충돌은 compile
error입니다.

자동 발견에서는 새 `pub fn`이 C/Go API에도 추가됩니다. 생성물 `go-check`와 독립 배포
계약이 있다면 `abi-check`를 함께 사용하세요.

## 함수 메타데이터

| 필드 | 역할 |
|---|---|
| `path` | `root.<name>` 또는 `<Type>.<name>` 선언 경로 |
| `name` | 공개 Go 함수 이름 override |
| `params` | 함수 파라미터 이름 목록 |
| `param_meta` | 파라미터별 `semantic`과 `retention` |
| `semantic` | 반환값 의미. 예: `.utf8_string` |
| `returns` | 반환 pointer의 ownership |

문자열 의미, 반환 pointer ownership, retained pointer와 callback 수명은 타입만으로 결정할 수
없으므로 명시해야 합니다.

```zig
.{
    .path = "Context.create",
    .params = .{ "name", "callback", "userdata" },
    .param_meta = .{
        .name = .{ .semantic = .utf8_string },
        .callback = .{ .retention = .retained },
    },
}
```

`param_meta`의 field는 파라미터 이름과 일치해야 합니다. 해당 이름을 reflection 단계에서
확실히 식별하려면 같은 항목에 `params`도 적으세요. 이름은 명시적 `params`, 대상 source AST,
`p0` fallback 순으로 결정됩니다.

## 타입 등록 선택

`repr`은 타입의 ABI 표현을, `access`는 tagged union 내용을 Go에서 읽는 방법을 선택합니다.

| `repr` | 용도 |
|---|---|
| `.@"opaque"` | pointer handle과 수명주기 |
| `.value` | 적격한 `extern struct`의 Go 값 mirror |
| `.tagged_union` | pointer handle을 통한 tagged union 접근 |

| `access` | 용도 |
|---|---|
| `.projection` | variant별 tag/payload accessor. 기본값 |
| `.snapshot` | tag와 scalar payload를 한 native 호출로 복사. projection도 유지 |

generic 타입은 구체화한 타입에 고유 이름을 붙여 등록합니다.

```zig
.types = .{
    .{ .name = "FloatBuffer", .type = mylib.Buffer(f32), .repr = .@"opaque" },
    .{ .name = "IntBuffer", .type = mylib.Buffer(i32), .repr = .@"opaque" },
},
```

generic 함수는 구체화 전에는 signature가 없으므로 직접 노출할 수 없습니다.

## Opaque handle

일반 Zig struct나 상태를 가진 객체는 pointer handle로 등록합니다.

```zig
.types = .{
    .{ .type = mylib.Context, .repr = .@"opaque" },
},
```

caller-owned pointer를 반환하는 생성 함수와 대응 deinitializer가 있으면 공개 Go API에
constructor와 멱등 `Close() error`가 생성됩니다. 반환 error는 항상 nil이며 handle이
`io.Closer`를 만족시키기 위한 것입니다. 모든 receiver와 handle 인자는 native 호출 전에
nil·closed 상태를 검사합니다. 검사 결과는 항상 반환값으로 전달되며, 오류 반환 자리가
없던 메서드에는 `error` 결과가 추가됩니다.

retained callback이나 pointer는 소유 객체의 `Close`까지 유효해야 합니다. 동일 handle의
호출과 `Close`를 여러 goroutine에서 동시에 수행할 때의 동기화는 호출자 책임입니다.

## Extern struct 값

Go에서 struct를 값처럼 주고받으려면 Zig 타입을 `extern struct`로 선언하고 등록합니다.

```zig
.types = .{
    .{ .type = mylib.Config, .repr = .value },
},
```

```go
cfg := Config{Width: 120, Mode: ModeActive}
Configure(cfg)
current := DefaultConfig()
```

C 경계에서는 aggregate를 값으로 전달하지 않습니다. 파라미터는 `const T*`, 반환은 `T*`
out parameter로 낮추고 생성 코드가 주소를 관리합니다.

모든 field가 bool, 정수/부동소수 scalar, 등록 enum, 또는 다시 적격한 `extern struct`여야
합니다. slice, pointer, optional, error union, callback, 일반 struct field와 빈 struct는
`ZIGO012`로 거부됩니다. 값 struct를 slice 원소, optional, callback signature 안에 두면
`ZIGO013`입니다. field 추가·삭제·재정렬·타입 변경은 모두 breaking ABI 변경입니다.

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
borrowed `*TRef`입니다. union 자체를 함수 값으로 직접 전달하면 `ZIGO006`이며 pointer로
노출해야 합니다.

기존 순서·tag·payload를 보존한 끝부분 variant 추가는 compatible append입니다. 삭제,
재정렬, 이름·tag·payload 변경은 breaking입니다.

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

## 생성된 Go error 판별

분류에는 내보낸 sentinel과 `errors.Is`를 사용하고, 세부 정보가 필요할 때만 `errors.As`를
사용합니다. 모든 생성 error type은 정확히 하나의 sentinel로 unwrap됩니다.

| `errors.Is` 대상 | 뜻 | 세부 타입 |
|---|---|---|
| `ErrInvalidHandle` | nil·closed·부모가 닫힌 handle | `*HandleError` |
| `ErrNativePanic` | Zig panic | `*NativePanicError` |
| `ErrNativeStatus` | 알려지지 않은 native status | `*StatusError` |
| `ErrLibraryLoad` | purego library·symbol load 실패 | `*LibraryError` |
| `Err<ZigError>` | Zig error set 값 | `*Error` |

```go
switch {
case errors.Is(err, ErrInvalidHandle):
case errors.Is(err, ErrNativePanic):
case errors.Is(err, ErrOutOfMemory):
}

var panicErr *NativePanicError
if errors.As(err, &panicErr) {
    log.Print(panicErr.Operation, panicErr.Message)
}
```

panic하는 `Must*` method에서 복구한 값도 `error`이면 같은 규칙으로 판별할 수 있습니다.

```go
defer func() {
    if err, ok := recover().(error); ok && errors.Is(err, ErrInvalidHandle) {
        // handle use-after-close
    }
}()
```

전체 타입 적격 조건과 runtime 주의사항은 [지원 범위와 제한사항](limitations.md)이 정본입니다.
