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
| `param_meta` | 파라미터별 `semantic`, `retention`, `direction`, `written` |
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

### 콜백 타입 이름

콜백 파라미터마다 Go 함수 타입이 하나씩 생깁니다. 이름은 기본적으로 소유 타입이나 함수와
파라미터 이름에서 파생되므로(`ContextCallback`, `ApplyCallback`), 같은 Zig 시그니처를 여러
함수가 받으면 Go 타입도 여러 개가 됩니다. Zig의 `pub const Observer = *const fn (...)`은
alias라 reflection이 이름을 알 수 없으니, 하나의 이름을 원하면 `types`에 등록합니다.

```zig
.types = .{
    .{ .name = "Observer", .type = mylib.Observer, .repr = .callback },
},
```

같은 시그니처의 모든 콜백 파라미터가 `Observer` 하나로 생성됩니다. 시그니처가 같은 alias
둘을 등록하면 먼저 등록한 이름이 둘 다에 쓰입니다 — Zig에게는 같은 타입입니다.

## 정수 폭

C는 8, 16, 32, 64비트 정수만 이름 붙일 수 있습니다. `u21`이나 `i24`처럼 그 밖의 폭은
파라미터·반환값·error union payload 자리에 한해 다음 폭으로 승격되어 건너갑니다.

| Zig | C | Go |
| --- | --- | --- |
| `i8`, `u8`, `i16`, `u16`, `i32`, `u32`, `i64`, `u64` | 같은 폭 | 같은 폭 |
| `u21` | `uint32_t` | `uint32` |
| `i24` | `int32_t` | `int32` |
| `usize`, `isize` | `size_t`, `ptrdiff_t` | `uint`, `int` |

`semantic.json`에는 원래 폭(`"bits": 21`)이 그대로 기록되므로 `abi-diff`는 21 → 32 변경을
여전히 breaking으로 봅니다. shim이 진입 시점에 범위를 검사하므로, Go가 `u21`에 담기지 않는
값을 넘기면 잘리는 대신 native panic이 납니다. 그 호출은 `errors.Is(err, ErrNativePanic)`으로
판별합니다(오류를 반환하지 않는 함수는 panic을 보고할 자리가 없습니다.
[제한사항](limitations.md#런타임-주의사항) 참고).

승격은 값 하나가 shim을 지나갈 때만 가능합니다. `extern struct` 필드, slice 원소(`[]u21`),
콜백 시그니처는 C로 바이트 그대로 비추므로 그 자리의 비정규 폭은 `ZIGO018`로 거부됩니다.

## 슬라이스 반환 소유권

슬라이스를 반환하는 함수는 호출 시점에 native 메모리에서 Go가 소유한 새 사본을 만듭니다.
따라서 반환된 `[]T`는 다음 native 호출이나 원본 객체의 `Close`와 독립적이며, 호출자는
반환된 사본만 수정할 수 있습니다. tagged-union의 숫자 slice payload도 같은 복사 계약을
따릅니다. 이 복사가 부담이라면 결과를 `.direction = .out` 파라미터로 받는
[`...Into(dst)` 패턴](#큰-결과는-out-파라미터로)을 쓰세요.

실패할 수 있는 slice 반환(`![]T`)도 같은 방식으로 내려갑니다. C 시그니처는 정수 코드를
반환하고 `T** out_result_ptr, size_t* out_result_len`을 그대로 받으며, 공개 Go는
`([]T, error)`가 됩니다. 오류일 때 생성된 코드는 out 파라미터를 읽지 않고 `nil`과 오류를
돌려주므로, native가 아무것도 기록하지 않은 상태를 그대로 안전하게 표현합니다. 원소는
스칼라·enum·`extern struct`만 쓸 수 있고 `![]string`이나 `!?[]T`는 지원하지 않습니다.

## Sentinel C 문자열

Zig API가 NUL 종료 포인터를 쓴다면 `[*:0]const u8`를 그대로 노출할 수 있습니다. 이 타입은
별도 `.semantic` 메타데이터 없이 `string`으로 반영됩니다.

```zig
pub fn echoCString(text: [*:0]const u8) [*:0]const u8 {
    return text;
}
```

cgo raw는 호출 중 `C.CString`을 만들고 호출이 끝나면 `free`하며, purego raw는 NUL을 붙인
Go byte buffer를 호출 동안만 native에 전달합니다. 반환 문자열도 호출 시점에 Go `string`으로
복사합니다. 따라서 Go 포인터가 native 메모리로 넘어가지 않습니다. mutable `[*:0]u8`,
0이 아닌 sentinel, 기타 many-pointer는 지원하지 않습니다.

## 문자열 slice 매개변수

여러 문자열을 입력으로 넘길 때는 `[]const []const u8`에 `.utf8_string`을 지정하거나,
element를 `[:0]const u8` 또는 `[*:0]const u8`로 선언할 수 있습니다. 세 형태 모두 public
Go에서는 `[]string`이 됩니다. 일반 unsentinel 형태는 sidecar에서 의미를 지정해야 합니다.

```zig
pub fn extractPaths(paths: []const []const u8) usize { /* ... */ }

// bindings.zig
.{
    .path = "Context.extractPaths",
    .params = .{"paths"},
    .param_meta = .{ .paths = .{ .semantic = .utf8_string } },
},
```

native ABI는 `paths_data`, `paths_data_len`, `paths_lens`, `paths_count` 네 scalar 인자로
내려갑니다. 각 문자열의 바이트 뒤에 NUL을 하나 붙이고 `paths_lens`에는 NUL을 제외한 길이를
기록합니다. cgo와 purego 모두 pointer-free Go 배열 하나씩만 만들어 호출 중 빌려주며
문자열별 malloc은 하지 않습니다. 빈 `[]string`과 빈 문자열 원소도 지원합니다. `[]string`
반환은 지원하지 않습니다.

## 타입 등록 선택

`repr`은 타입의 ABI 표현을, `access`는 tagged union 내용을 Go에서 읽는 방법을 선택합니다.

| `repr` | 용도 |
|---|---|
| `.@"opaque"` | pointer handle과 수명주기 |
| `.value` | 적격한 `extern struct`의 Go 값 mirror |
| `.tagged_union` | pointer handle을 통한 tagged union 접근 |
| `.callback` | `*const fn` alias에 Go 타입 이름을 부여. `.name` 필수 |

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

`init`/`create`/`new`/`open` 이름을 쓰지 않는 factory도 `.returns = .caller`를 붙이면
같은 owned handle을 돌려줍니다. 이름이 아니라 ownership metadata가 기준이므로,
`clone`이나 `openChild` 같은 메서드도 `newX` helper를 거쳐 cleanup과 retained callback
등록을 그대로 받습니다.

```zig
.{
    .path = "EventQueue.clone",
    .params = .{ "observer", "userdata" },
    .param_meta = .{ .observer = .{ .retention = .retained } },
    .returns = .caller,
},
```

감쌀 handle이 없는 `.returns = .caller`는 `ZIGO015`로 거부됩니다(slice 반환은 아래의
`ZIGO016` 규칙을 따릅니다). 반환 타입이 opaque
pointer가 아니거나, 그 타입에 constructor와 deinitializer가 등록되어 있지 않은
경우입니다.

## 호출자 소유 slice 반환

slice 반환은 `.returns = .caller`로 소유권을 넘길 수 있습니다. 이때는 감쌀 handle 대신
버퍼를 되돌려줄 함수가 필요하므로 `.release`로 그 함수의 경로를 함께 지정합니다. release
함수는 반환된 slice와 같은 원소 타입의 slice 하나만 받고 아무것도 반환하지 않아야 합니다.

```zig
pub fn extractSamples(self: *EventQueue) []f32 { /* 새 버퍼를 할당해 반환 */ }
pub fn freeSamples(_: *EventQueue, samples: []f32) void { /* 버퍼 해제 */ }

// bindings.zig
.{
    .path = "EventQueue.extractSamples",
    .returns = .caller,
    .release = "EventQueue.freeSamples",
},
.{ .path = "EventQueue.freeSamples", .params = .{"samples"} },
```

생성된 raw 계층은 native가 채운 `ptr, len`을 먼저 Go slice로 복사한 뒤 곧바로 release
심볼을 같은 `ptr, len`으로 호출합니다. 따라서 반환된 slice는 항상 Go 메모리이고, 호출자가
따로 해제할 것이 없습니다. release 함수는 공개 Go API에 나타나지 않습니다. 이미 복사된
Go slice를 다시 넘기는 실수를 막기 위해서입니다.

`![]T` 반환에도 같은 조합을 쓸 수 있습니다. 이때 복사와 release는 모두 성공했을 때에만
일어납니다. 오류 코드가 돌아오면 생성된 코드는 out 파라미터를 읽지 않고 release도 부르지
않은 채 `nil`과 오류를 돌려주므로, 아무것도 넘겨받지 않은 실패 경로에서 존재하지 않는
버퍼를 해제하는 일이 없습니다.

```zig
pub fn extractSamplesChecked(self: *EventQueue) ProcessError![]f32 { /* 실패 또는 새 버퍼 */ }

// bindings.zig
.{
    .path = "EventQueue.extractSamplesChecked",
    .returns = .caller,
    .release = "EventQueue.freeSamples",
},
```

`.release`가 없거나, 이름이 가리키는 함수가 없거나, 그 함수의 매개변수가 반환 slice와
맞지 않으면 `ZIGO016`으로 거부됩니다. `![]T`는 payload slice의 원소 타입으로 비교합니다.
slice가 아닌 반환에 `.release`를 붙여도 같은 코드입니다. abi-check는 release 함수가 바뀌면
breaking으로 봅니다.

`?*T`/`?*const T` 매개변수는 nil을 받을 수 있는 handle 인자가 됩니다. Go에서 nil을
넘기면 native 쪽에는 NULL이 전달되고 `*HandleError`는 발생하지 않습니다. 다만 optional은
"인자가 없어도 된다"는 뜻이지 "닫힌 handle을 넘겨도 된다"는 뜻은 아니므로, nil이 아닌 채
이미 닫힌 handle은 여전히 `*HandleError`입니다. optional은 선언된 opaque type의
pointer에만 쓸 수 있고, 그 밖의 optional은 reflection 단계에서 거부됩니다.

retained callback이나 pointer는 소유 객체의 `Close`까지 유효해야 합니다.

생성된 handle은 모두 같은 수명주기를 씁니다. 종류에 따라 달라지지 않습니다.

- 모든 메서드와 tagged-union projection(`Tag`/`As*`/`Snapshot`/`Variant`), borrowed
  `Ref`의 모든 호출은 native 호출 전에 handle을 **획득**하고(`zigoAcquire`) 돌아온 뒤
  놓습니다(`zigoRelease`). 획득은 handle의 `sync.Mutex` 아래에서 진행 중 호출 수를
  하나 늘리는 것뿐이고, 그 잠금은 native 호출 동안 잡혀 있지 않습니다. `Ref`는 부모
  사슬을 따라 부모를 획득합니다. 이미 닫힌 handle을 쓰는 호출은 use-after-free 대신
  `*HandleError`를 돌려받습니다.
- `Close`는 기다리지 않습니다. handle을 닫힘으로 표시하고, 그 순간 native 안에 있는
  호출이 없으면 바로 해제하며, 있으면 그 호출들 중 마지막으로 돌아오는 것이 해제합니다.
  `Close` 이후의 호출은 진행 중인 호출 뒤에서 기다리지 않고 즉시 `*HandleError`를
  받습니다. 그래서 어느 goroutine의 `Close`도 다른 goroutine의 호출을 막지 못합니다.
  긴 native 호출이 handle을 쓰는 동안 다른 스레드가 `cancel` 같은 메서드를 부르는 타입에
  특히 중요합니다. 동시에 여러 번 불러도 해제는 한 번만 일어납니다.
- native 호출이 Zig panic으로 끝나면(`*NativePanicError`) 그 호출이 닿은 모든 handle,
  즉 receiver와 handle 인자, projection의 소유자가 **poison** 됩니다. panic은 `longjmp`로
  native 프레임을 건너뛰어 그 안의 `defer`/`errdefer`가 실행되지 않았으므로 handle 뒤의
  상태는 알 수 없습니다. 이후 그 handle의 모든 호출은 처음 panic한 작업과 메시지를 담은
  `*NativePanicError`를 돌려주고(`errors.Is(err, ErrNativePanic)`), `Close`와 cleanup
  안전망은 native deinit을 부르지 않고 객체를 **누수**시킵니다. 반쯤 바뀐 상태를
  해제하다 fault를 내는 것보다 누수가 낫기 때문입니다. retained callback 등록은 그래도
  해제됩니다.
- 생성자가 만든 handle은 만들어질 때 `runtime.AddCleanup`을 등록합니다. `Close`를 잊고
  handle을 버려도 GC가 회수하는 시점에 native 메모리와 retained callback 등록이 함께
  풀립니다. `Close`가 먼저 실행되면 `cleanup.Stop()`으로 이 안전망을 떼어냅니다.
- 콜백을 받는 생성자를 가진 타입만 `callbackHandles`를 들고 다닙니다.

안전망은 실행 시점을 보장하지 않으므로 명시적 `Close`를 대체하지 않습니다. 획득은
receiver뿐 아니라 handle **인자**에도 걸리므로, 인자로 넘긴 handle을 다른 goroutine이
그 사이에 닫아도 native 메모리는 호출이 돌아온 뒤에 해제됩니다. 다만 그 `Close`는 호출자
관점에서 여전히 계약 위반이고, 이후의 호출이 `*HandleError`를 받는 것으로 드러납니다.

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
`ZIGO012`로 거부됩니다. 이런 scalar-only struct는 직접 slice 원소로도 사용할 수 있습니다.
다만 optional이나 callback signature 안에 값을 넣으면 `ZIGO013`입니다. field
추가·삭제·재정렬·타입 변경은 모두 breaking ABI 변경입니다.

```zig
pub fn estimate(output: []Stats) !usize { /* ... */ }

// bindings.zig
.{
    .path = "Context.estimate",
    .params = .{"output"},
    .param_meta = .{ .output = .{ .direction = .out, .written = .@"return" } },
},
```

직접 slice 원소인 `extern struct`는 C에서 `const T*`/`T*`와 길이로 전달됩니다. Go public
API는 `[]T`를 받습니다. bool field가 없는 struct는 Go mirror가 C layout과 byte 단위로
같으므로 slice 주소를 그대로 넘깁니다 — 들어갈 때도 나올 때도 복사가 없고, native는
호출자의 버퍼에 직접 씁니다. 이 동일성은 생성된 compile 시점 layout 단정이 지키므로,
어긋나면 Go build가 실패합니다. bool field가 있는 struct만 원소별 복사 경로를 씁니다.
반환 slice는 어느 쪽이든 `[]T`의 새 사본이며 native 메모리를 alias하지 않습니다.
out slice로 선언하려면 해당 파라미터에 `param_meta.direction = .out`을 명시해야 합니다.

### 얼마나 채워졌는가: `written`

`.direction = .out`인 slice는 기본값 `.written = .all`로, 호출이 끝나면 버퍼 전체가
채워진 것으로 봅니다. `.written = .@"return"`을 붙이면 함수가 반환한 개수만큼만
채워진 것으로 보고, **그 뒤의 원소는 호출 전 값 그대로**입니다 — `io.Reader`와 같은
모양입니다. 오류로 끝난 호출은 0을 보고하므로 버퍼는 전혀 건드려지지 않습니다.

`.@"return"`은 반환 payload가 `usize`(또는 `!usize`)일 때만 쓸 수 있고, `.out`이 아닌
파라미터에 붙이면 `ZIGO017`로 거부됩니다.

### 큰 결과는 out 파라미터로

slice를 반환하면 호출마다 Go 쪽 할당과 복사가 한 번씩 일어납니다. 결과가 크거나 호출이
잦다면 호출자가 버퍼를 재사용하는 `...Into(dst)` 모양이 낫습니다.

```zig
pub fn extractSamplesInto(self: *Queue, dst: []f32) usize {
    const wanted = self.items.len + 1;
    if (dst.len < wanted) return 0;
    // ... dst[0..wanted] 를 채운다
    return wanted;
}

// bindings.zig
.{
    .path = "Queue.extractSamplesInto",
    .params = .{"dst"},
    .param_meta = .{ .dst = .{ .direction = .out, .written = .@"return" } },
},
```

```go
buf := make([]float32, 1024) // 한 번 할당해 계속 재사용
n, err := queue.ExtractSamplesInto(buf)
// buf[:n] 이 이번 호출의 결과, buf[n:] 는 그대로
```

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
| `ErrCallbackPanic` | Go 콜백 안에서 발생한 panic (반환이 아니라 **rethrow**) | `*CallbackPanicError` |
| `Err<ZigError>` | Zig error set 값. 반환된 값의 `Operation`이 어느 호출에서 났는지 말한다 | `*Error` |

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

var zigErr *Error
if errors.As(err, &zigErr) {
    log.Print(zigErr.Operation, zigErr.Name) // 예: "Pipeline.Process", "Disabled"
}
```

`Err*` sentinel은 `==`가 아니라 `errors.Is`로 비교합니다. 반환되는 값은 호출 이름을 담은
새 `*Error`이고, `Is`는 stable code로 판별합니다.

panic하는 `Must*` method에서 복구한 값도 `error`이면 같은 규칙으로 판별할 수 있습니다.

### Go 콜백의 panic

Go 콜백이 native 호출 안에서 panic하면 trampoline이 그것을 복구합니다 — panic은 native
frame을 풀 수 없기 때문입니다. native 쪽은 부호 있는 32비트 결과에서 `-3`을 받아 스스로
정리하고 반환할 수 있고, 그 호출이 돌아온 직후 생성된 함수가 **같은 goroutine에서 panic을
다시 일으킵니다**. 다시 일어난 값은 `*CallbackPanicError`이며 원래 panic 값(`Value`)과 복구
시점의 stack(`Stack`)을 담습니다. `Unwrap`은 `Value`가 `error`일 때 그것을 돌려주므로
`errors.Is`·`errors.As`가 원인까지 닿습니다.

```go
defer func() {
    if recovered := recover(); recovered != nil {
        var panicErr *CallbackPanicError
        if err, ok := recovered.(error); ok && errors.As(err, &panicErr) {
            log.Print(panicErr.Operation, panicErr.Value, string(panicErr.Stack))
            return
        }
        panic(recovered)
    }
}()
```

이 규칙은 콜백을 인자로 받은 호출과, 콜백을 retained로 보유한 handle의 모든 method에
적용됩니다. native 코드가 `-3`을 자기 error로 바꿔 반환하더라도 Go 호출자는 그 error가
아니라 panic을 봅니다 — 콜백의 panic은 호출자 자신의 Go 코드가 실패한 것이고, 생성된 호출은
그것이 복구 가능한지 판단할 수 없기 때문입니다.

```go
defer func() {
    if err, ok := recover().(error); ok && errors.Is(err, ErrInvalidHandle) {
        // handle use-after-close
    }
}()
```

전체 타입 적격 조건과 runtime 주의사항은 [지원 범위와 제한사항](limitations.md)이 정본입니다.

## Doc 주석

Zig 쪽 doc은 그대로 생성된 Go doc이 됩니다. 본문을 다시 쓰지는 않고 형식만 맞춥니다.

수집 순서는 다음과 같습니다.

1. 선언 바로 앞의 `///` 블록.
2. `///`가 없으면, 선언 바로 위에 빈 줄 없이 붙은 평범한 `//` 줄들. `///`, `////`, `//!`로
   시작하는 줄은 여기에 포함되지 않습니다.
3. 자기 doc이 없고 앞 선언과 빈 줄 없이 이어지는 선언은 그 묶음이 시작할 때의 doc을
   물려받습니다. 빈 줄 하나가 묶음을 끊습니다.

```zig
// The selection flag bits shared by the setters below.
pub fn select(self: *Flags) void { ... }
pub fn selectSilent(self: *Flags) void { ... }  // 위 doc을 공유합니다

pub fn detached(self: *Flags) void { ... }      // 빈 줄이 묶음을 끊습니다
```

출력은 Go 관례대로 항상 식별자로 시작합니다. 본문이 선언 이름으로 시작하거나 소문자
동사로 시작할 때만 한 줄로 이어 붙이고, 그 밖의 대문자로 시작하는 문장은 자기 줄을
가집니다.

```go
// Len reports how many events are queued.

// SelectionSilent
// The selection flag bits shared by the setters below.
```

doc이 없는 함수는 `// Name calls the Zig function Owner.name.` 한 문장을 받습니다.

패키지 doc은 공개 패키지마다 정확히 한 파일에 생성됩니다. 본문은 `go_package_doc` 빌드
옵션, `bindings.zig` 최상위의 `//!` 블록, 그리고 기본 문장
`// Package {name} provides Go bindings generated by zigo.` 순으로 결정됩니다. 본문이
`Package {name}`으로 시작하면 그대로 쓰고, 소문자 동사로 시작하면 `// Package {name}` 뒤에
이어 붙입니다. 그 밖의 본문(대문자로 시작하는 문장 등)은 기본 문장 뒤에 빈 `//` 줄을 두고
별도 문단으로 이어집니다. godoc은 연속된 주석 줄을 한 문단으로 합치므로, 이름만 적은 줄 뒤에
본문을 붙이면 `Package scalar Scalar arithmetic…`처럼 읽히기 때문입니다. raw 패키지는
지원 API가 아니라는 사실을 밝히는 자체 doc을 받습니다.
