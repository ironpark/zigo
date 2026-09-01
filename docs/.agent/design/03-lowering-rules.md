# ABI 하강 규칙 (Zig → C ABI → Go)

`lower` 단계가 수행하는 변환의 완전한 표. emitter(Zig shim / C 헤더 / Go)는
이 표를 다시 구현하지 않고 하강된 `AbiFn`만 읽는다.

## 1. 스칼라

| Zig | C ABI | Go (raw) | Go (public) |
|---|---|---|---|
| `u8 u16 u32 u64` | `uint8_t …` | `uint8 … uint64` | 동일 |
| `i8 i16 i32 i64` | `int8_t …` | `int8 … int64` | 동일 |
| `usize` / `isize` | `size_t` / `ptrdiff_t` | `uintptr` / `int` | `int` |
| `f32 f64` | `float double` | `float32 float64` | 동일 |
| `bool` | `uint8_t` | `uint8` | `bool` |
| `void` | `void` | (없음) | (없음) |

`bool`을 `_Bool` 대신 `uint8_t`로 내리는 이유: 컴파일러/플랫폼 간 `_Bool` 크기 합의를
신뢰하지 않기 위함. 변환 비용은 0에 가깝다.

## 2. enum

`extern`이거나 명시적 정수 태그를 가진 enum만 허용. non-exhaustive enum은 v1에서 거부.

```zig
pub const Format = enum(u32) { pcm, flac };
```
```c
typedef uint32_t zg_format;
#define ZG_FORMAT_PCM  0u
#define ZG_FORMAT_FLAC 1u
```
```go
type Format uint32
const ( FormatPCM Format = 0; FormatFLAC Format = 1 )
func (f Format) String() string   // 생성됨
```

## 3. 슬라이스

Zig 슬라이스는 C ABI 안전하지 않다. 항상 ptr+len 쌍으로 분해한다.

| 방향 | C | Go public |
|---|---|---|
| `[]const T` (in) | `const T* p, size_t p_len` | `p []T` |
| `[]T` (out) | `T* p, size_t p_len, size_t* p_written` | 반환값 `[]T` (호출자 버퍼 또는 신규 할당) |
| `[]const u8`, semantic 없음 | `const uint8_t*, size_t` | `[]byte` |
| `[]const u8`, `semantic=utf8_string` | `const char*, size_t` | `string` |
| `[*:0]const u8` | `const char*` | `string` |
| `[]const []const u8`, `[]const [:0]const u8`, `[]const [*:0]const u8` (string slice) | `const uint8_t* p_data, size_t p_data_len, const size_t* p_lens, size_t p_count` | `[]string` |

`.returns = .caller` slice 반환은 `out_result_ptr`/`out_result_len`을 그대로 쓰고
`release` 함수의 심볼을 AbiFn에 붙인다. 생성된 raw 계층은 복사를 끝낸 직후 같은
`ptr, len`으로 release 심볼을 호출한다(길이 0도 포함해 정확히 한 번). release 함수는
raw 계층에만 내보내고 공개 API에서는 감춘다. abi-check는 release 심볼의 추가·삭제·변경을
breaking으로 분류한다.

slice 반환은 cgo와 purego 모두 호출 시점에 native `ptr + len`에서 새 Go slice로 복사한다.
공개 API가 native 메모리를 alias하지 않으므로, 다음 호출·원본 객체 수명·`Close`와
무관하게 반환값을 보관하고 수정할 수 있다. tagged-union numeric-slice projection도
동일하게 Go-owned copy를 반환한다.
**out 슬라이스에 `p_written`을 항상 추가**하는 이유: Zig의 `!usize` 반환이 흔히
"쓴 개수"를 의미하나 이를 신뢰할 수 없으므로, 명시적 out 파라미터로 계약을 고정한다.

`[*:0]const u8`는 `semantic=c_string`으로 기록되는 별도 길이 없는 문자열이다. cgo raw는
호출 중 `C.CString`으로 임시 C 메모리를 만들고 즉시 해제하며, purego raw는 NUL을 붙인
Go byte buffer를 호출 동안 고정한다. 반환값은 cgo의 `C.GoString`, purego의 NUL 탐색과
복사로 Go `string`이 되므로 native 포인터를 노출하지 않는다. mutable sentinel pointer,
0이 아닌 sentinel, 그 밖의 many-pointer는 reflection 단계에서 거부한다.

string slice 매개변수는 각 문자열의 바이트를 순서대로 이어 붙이고 문자열마다 NUL 하나를
추가한 `p_data`를 사용한다. `p_data_len`은 NUL을 포함한 전체 바이트 수이고, `p_lens[i]`는
해당 문자열의 바이트 길이로 NUL을 제외한다. `p_count`는 문자열 개수다. shim은 개수가
16개 이하이면 고정 스택 배열을, 그보다 크면 `std.heap.page_allocator` 배열을 사용한다.
fallback 할당이 실패하거나 길이 배열이 버퍼 범위를 벗어나면 zigo panic status로 변환한다.
Go raw 양쪽은 `[]byte`와 pointer-free 길이 배열을 한 번만 만들며, 문자열별 C malloc은
사용하지 않는다. 반환에서 `[]string`을 지원하지 않는 것은 이 규칙과 별개다.
element 원형(`[]const u8` / `[:0]const u8` / `[*:0]const u8`)은 semantic IR의
`sentinel`/`sentinel_many`로만 남고 C ABI 모양을 바꾸지 않는다. 따라서 abi-check는 이
두 필드를 시그니처 비교에서 제외하며, element 원형만 바뀐 변경은 breaking이 아니다.

**Go 포인터 규칙 검증:** string slice 예외를 제외하고 `element`가 포인터·슬라이스·문자열을
포함하면 하강 실패한다(Go 포인터를 담은 Go 메모리 전달 금지). 진단 메시지에 대안(핸들 배열)을
제시한다.

## 4. optional

| Zig | C | Go |
|---|---|---|
| `?*T` | `T*` (NULL 허용) | `*T` (nil 허용) |
| `?T` (T가 스칼라) | `T* out` + `uint8_t* has` | `(T, bool)` |
| `?[]const T` | `const T* p` (NULL 허용) `, size_t` | `[]T` (nil 허용) |

`?*T`가 이미 ABI 안전하다는 점을 활용해 추가 파라미터를 만들지 않는 것이 요점.

## 5. error union ★

모든 실패 가능 함수는 **정수 코드 반환 + payload out 파라미터**로 통일한다.

```zig
pub fn process(self: *Context, input: []const f32, output: []f32) !usize
```
```c
int32_t zg_context_process(
    zg_context *self,
    const float *input,  size_t input_len,
    float       *output, size_t output_len, size_t *output_written,
    size_t      *out_result);            // payload
```
```go
// raw
func ContextProcess(self unsafe.Pointer, input *float32, inputLen uintptr,
                    output *float32, outputLen uintptr, outputWritten *uintptr,
                    outResult *uintptr) int32

// public
func (c *Context) Process(input []float32, output []float32) (int, error)
```

- 코드는 `errors.lock.json`의 안정 매핑. `@intFromError` 사용 금지.
- payload가 `void`면 out 파라미터 없음.
- 에러 시 payload out은 **기록하지 않는다** (Go 래퍼가 zero value 반환).
- Go 에러 타입:
  ```go
  type Error struct { Code int32; Name string }
  func (e *Error) Error() string
  var ErrOutOfMemory = &Error{1, "OutOfMemory"}   // errors.Is 대상
  ```

## 6. struct

| Zig 선언 | 노출 방식 |
|---|---|
| `extern struct` | **값 의미, 포인터 전달.** C struct 미러링 + Go struct 미러링 |
| `packed struct` | 미지원. 정수 백킹 노출은 비범위이며 `ZIGO003`으로 거부한다 |
| 일반 `struct` | **opaque only.** 포인터로만 전달 |

일반 struct의 레이아웃은 Zig 명세상 보장되지 않으므로 미러링하지 않는다. Go에서 값처럼
주고받으려면 `extern struct` 선언이 요구된다 (진단이 이를 안내한다).

### 6.1 aggregate는 값으로 넘기지 않는다

`extern struct`도 C 경계를 값으로 건너가지 않는다. 파라미터는 `const T*`, 반환과 out은
`T*`로 내려간다. 이유는 두 가지다. aggregate by-value 전달은 레지스터 분할, 크기 임계값,
숨은 반환 포인터 같은 플랫폼별 ABI 규칙을 그대로 노출한다. 그리고 purego의 raw 시그니처는
스칼라와 포인터만 다룬다. tagged union 값 스냅샷이 out 포인터를 쓰는 것과 같은 이유이며
(§7.1), 그래서 규칙은 하나다. **zigo는 어떤 aggregate도 C 경계를 값으로 넘기지 않는다.**

```c
typedef struct zg_config {
    uint8_t enabled;
    int32_t width;
    zg_mode mode;
} zg_config;

void zg_configure(const zg_config *config);
void zg_default_config(zg_config *out_result);
```

값 의미는 Go 쪽에서 유지된다. 공개 API는 `func Configure(cfg Config)` 와
`func DefaultConfig() Config` 이고, 주소를 잡는 일은 생성 코드 안에서만 일어난다. raw
계층은 struct마다 `<T>Data` 미러를 두는데, cgo는 멤버 단위로 C 값을 채우므로 미러의
배치에 의존하지 않고, purego는 미러의 주소를 그대로 넘기므로 배치가 계약이다. 그래서
미러에는 하강 단계에서 계산한 offset으로부터 패딩을 명시한다.

#### 필드 추가는 breaking이다

`extern struct` 끝에 필드를 하나 더 붙이는 것은 abi-check에서 `.breaking`으로 분류한다.
enum variant 추가나 error 추가처럼 compatible로 볼 수 없는 이유는 aggregate가 포인터로
건너가기 때문이다. C 경계에는 `T*`만 있고 크기는 따라가지 않으므로, 어느 쪽이 버퍼를
할당했는지가 곧 계약이다.

- out 자리(`T *out_result`)에서는 Go가 버퍼를 잡는다. native만 새 필드를 아는 상태로
  갱신되면 native가 옛 Go 버퍼 뒤로 써서 인접 메모리를 덮는다.
- in 자리(`const T *`)에서는 native가 옛 Go 버퍼 뒤를 읽어 쓰레기 값을 새 필드로 본다.
- purego 미러는 배치 자체가 계약이므로(§6.1) 이 어긋남을 잡아낼 방법이 없다.

`.cgo_static`은 archive를 Go 링크 시점에 함께 묶으므로 native와 Go가 항상 같은 세대다.
그래서 정적 cgo만 놓고 보면 필드 추가가 실제로 안전하다. 그러나 abi-check는 링크 방식을
가정하지 않고 판정하므로 기본값은 계속 breaking이다. 이를 compatible로 낮추는 opt-in을
둔다면 `.cgo_static`에서만 받아들이고 그 밖의 `link`에서는 빌드 단계에서 거부해야 한다.
현재는 그 옵션을 두지 않는다.

레이아웃은 `extern`이 이미 고정한다. 헤더는 사용자의 필드를 사용자의 순서대로 미러링하고,
재정렬하거나 패딩을 지어내지 않는다. 중첩 struct는 자신을 품는 struct보다 먼저 나온다.
shim에는 `@sizeOf`/`@alignOf`/`@offsetOf` comptime 단언이 함께 생성되어, Zig 타입이 미러와
어긋나면 빌드가 실패한다.

필드는 재귀적으로 ABI 안전해야 한다. bool, 정수/부동소수 스칼라, 등록된 enum, 그리고 다시
적격한 `extern struct` 만 허용한다. slice·포인터·optional·error union·callback·일반 struct
필드는 `ZIGO012`가 문제된 필드를 지목하며 거부한다. 필드가 하나도 없는 struct는 C 표현이
없으므로 같은 진단으로 거부한다. struct는 파라미터·반환·error union payload 자리와 직접
`slice` 원소 자리에서 쓸 수 있다. 후자는 `const T*`/`T*`와 `size_t` 길이로 내려가며 cgo는
멤버별 C 임시 배열을, purego는 `<T>Data` 미러 배열을 사용한다. optional이나 callback
시그니처 안에 들어가면 `ZIGO013`으로 거부한다.

ABI 판정은 단순하다. 필드 추가·삭제·순서 변경·타입 변경은 모두 struct의 크기나 offset을
움직이므로 **전부 breaking**이다. enum 값 추가나 projection union의 variant 추가와 달리
compatible append는 없다.

opaque 타입은 다음을 생성한다:
```go
type Context struct {
    ptr             unsafe.Pointer
    once            sync.Once       // Close 멱등성
    mu              sync.RWMutex    // 호출과 Close 직렬화
    callbackHandles []zigoCallbackHandle  // 콜백을 받는 생성자를 가진 타입만
    cleanup         runtime.Cleanup // 생성자가 있는 타입만
}
func NewContext(...) (*Context, error)
func (c *Context) Close()   // deinit 대응 함수가 있을 때만
```

수명주기는 하나뿐이다. 프로그램에 콜백이 있는지 여부로 다른 형태를 고르지 않고,
`callbackHandles`만 타입별로 결정한다.

`runtime.SetFinalizer`는 붙이지 않는다. 생성자가 있는 타입은 wrapper를 참조하지 않는 별도
resource state로 `runtime.AddCleanup`을 붙이므로 생성 코드의 Go 하한은 1.24다. 각 메서드는
`mu`의 읽기 잠금을 잡고, 명시적 `Close()`는 쓰기 잠금 아래에서 cleanup을 `Stop`하고 같은
해제 루틴을 호출한다. 각 native 호출은 `runtime.KeepAlive`로 wrapper의 생존 구간도
고정한다. cleanup은 실행 시점과 프로그램 종료 전 실행을 보장하지 않으므로 `Close()`가 항상
기본 계약이다.

## 7. tagged union projection

`.repr = .tagged_union`은 union을 opaque handle로 내리고 실제 layout을 C struct로 복제하지
않는다. discriminant와 payload마다 별도 projection 심볼을 만든다.

```c
uint8_t zg_value_project_tag(const zg_value *self, uint8_t *out_value);
uint8_t zg_value_project_integer(const zg_value *self, int64_t *out_value);
```

모든 projection은 `0 = variant mismatch`, `1 = success`, `2 = invalid handle/required output`,
`3 = Zig panic` 상태를 반환한다. shim은 `activeTag`를 먼저 검사하고 불일치하면 out
파라미터를 쓰지 않는다. 생성된 C wrapper는 null handle과 null out 파라미터를 Zig 호출 전에
거부하고, 실제 Zig panic만 status 3과 `zg_last_error_message()`로 변환한다. 하드웨어 fault나
메모리 손상까지 복구하는 계약은 아니다.

Go public API는 tag 상태를 확인한 뒤 `Tag()`를 반환하고, payload mismatch만
`AsInteger() (int64, bool)`의 `false`로 노출한다. nil/closed handle, 예상하지 못한 상태,
native panic은 설명이 있는 Go panic이 되므로 C/Zig로 잘못된 포인터를 전달하지 않는다.
borrowed `TRef`는 parent handle의 종료 상태도 재귀적으로 확인한다. numeric slice는
pointer+length로 projection한 직후 Go-owned slice로 복사하며, opaque-pointer payload는 union
wrapper를 parent로 보유하는 borrowed `TRef`가 된다.

`Close`, variant 변경, projection 호출을 여러 goroutine에서 동시에 수행하려면 호출자가
동기화해야 한다. `runtime.KeepAlive`는 GC에 의한 조기 cleanup만 막으며 명시적 `Close`와의
data race나 use-after-close를 직렬화하지 않는다.

기존 순서와 tag 값을 유지한 끝부분 variant 추가는 기존 projection 심볼을 보존하므로 ABI
compatible append다. variant 삭제·순서 변경·이름 변경, 기존 discriminant나 payload 타입
변경은 breaking type definition change다. 이름 또는 prefix 변경으로 기존 projection 심볼이
달라지는 경우도 breaking이다.

### 7.1 tagged union 값 스냅샷

projection은 정확하지만 tag 확인과 payload 읽기가 각각 FFI 왕복이다. payload가 전부
스칼라인 작은 union을 반복해서 들여다보는 Go 코드에는 이 비용이 그대로 쌓인다.
`.access = .snapshot`은 같은 union에 **값 스냅샷** 표현을 하나 더 붙여, tag와
payload를 한 번의 native 호출로 함께 읽게 한다. 접근 전략은 타입 종류와 다른 축이므로
`repr`은 그대로 `.tagged_union`이고 기본값은 `.projection`이며,
projection 심볼과 `Tag()`/`As*()`/`TryAs*()`는 그대로 남는다. 스냅샷은 대체가 아니라 추가다.

스냅샷도 Zig union의 메모리 배치를 C로 복제하지 않는다. zigo가 **자기 소유의 `extern
struct`** 를 정의하고 shim이 active variant를 읽어 그 안으로 옮겨 담는다. tag가 맨 앞에 오고
payload는 폭이 넓은 것부터 이어지며, 빈 자리는 전부 `reserved_<n>` 멤버로 명시한다. 폭 내림
차순 배치 덕분에 암묵적 padding이 생기지 않아 C 헤더, Zig shim, Go 구조체 세 표현이 같은
배치로 맞아떨어진다. shim에는 `@sizeOf`/`@alignOf` comptime 단언이 함께 생성된다.

```c
typedef struct zg_signal_snapshot_t {
    zg_signal_tag tag;
    uint8_t reserved_0[7];
    double level;
    uint32_t ticks;
    int16_t offset;
    zg_mode mode;
    uint8_t reserved_1[1];
} zg_signal_snapshot_t;

uint8_t zg_signal_snapshot(const zg_signal *self, zg_signal_snapshot_t *out_snapshot);
```

스냅샷은 반환값이 아니라 out 포인터로 넘긴다. aggregate by-value 반환은 ABI마다 규칙이
다르고 purego는 C struct를 값으로 전달하지 못한다. 상태 코드는 projection과 동일한
`0/1/2/3`이며, null handle과 null out 포인터는 Zig 호출 전에 거부되고 Zig panic은 status 3과
`zg_last_error_message()`로 나온다. shim은 채우기 전에 구조체 전체를 0으로 지우므로 비활성
variant 자리와 padding에 이전 스택 내용이 남지 않는다.

Go에는 `SignalSnapshot` 값 타입과 `TrySnapshot() (SignalSnapshot, error)` / `Snapshot()`이
생성된다. 스냅샷에서 tag는 `Tag()`로, payload는 `Ticks() (uint32, bool)`처럼 활성 여부를 함께
돌려주는 접근자로 읽는다. 이 읽기는 순수 Go이므로 추가 FFI 왕복이 없다.

적격 조건은 **모든 variant payload가 void, bool, 정수/부동소수 스칼라, 또는 등록된 enum** 인
것이다. `bool`은 §1의 스칼라 규칙대로 C ABI에서 `uint8_t`로 내려가고 public Go에서만 `bool`로
복원되므로 스냅샷도 예외를 두지 않는다. slice·opaque handle·중첩 aggregate·optional·error
union·callback payload가 하나라도 있으면 스냅샷으로 옮길 평평한 스칼라 복사본이 성립하지
않으므로 `ZIGO011`이 해당 variant를 지목하고 `.repr = .tagged_union`을 안내한다. 스냅샷
구조체가 discriminant를 `tag` 멤버로 쓰기 때문에 `tag`라는 이름의 variant도 같은 진단으로
거부된다.

ABI 판정은 표현마다 다르다. projection union의 끝부분 variant 추가는 여전히 compatible
append지만, 값 스냅샷 union에서는 구조체의 크기와 배치가 달라지므로 **breaking**이다. 두 표현
사이를 오가는 전환도 breaking이다. 스냅샷을 선택한다는 것은 variant 추가마다 ABI를 깨겠다는
선택이므로, variant가 자주 늘어나는 union은 projection에 두는 편이 낫다.

## 8. 소유권 → Go 매핑

| ownership | Go |
|---|---|
| `callee` (호출자가 해제 책임) | `*T` + `Close()` 생성 |
| `borrowed` | `TRef` 래퍼 (Close 없음, 원본 수명에 종속) |
| `caller` + slice 반환 | Go 소유 복사본 (raw 계층이 `release`를 대신 호출) |

`borrowed` 반환은 Go 래퍼에 원본 객체 참조를 필드로 심어
GC가 원본을 조기 수거하지 않게 한다 (`runtime.KeepAlive` 대신 구조적 보장).

```go
type ContextRef struct {
    ptr    unsafe.Pointer
    parent any      // 수명 고정용
}
```

## 9. 콜백

```zig
pub fn setCallback(
    ctx: *Context,
    cb: *const fn (Event, usize) callconv(.c) i32,
    userdata: usize,
) !void
```
→ C: 그대로. Go public:
```go
type ContextCallback func(Event)

func (c *Context) SetCallback(fn ContextCallback)
```
생성물:
1. `//export zg_context_set_callback_go_callback_cb` Go/C 트램폴린
2. 정의 콜백 타입을 raw trampoline의 익명 함수 타입으로 변환해 `cgo.NewHandle`에 등록하고,
   `uintptr`를 userdata로 전달
3. 트램폴린 내부 `defer func(){ if r:=recover(); r!=nil { … } }()`
4. `retention=borrowed`이면 호출 직후 `Delete()`
5. `retention=retained`이면 handle을 `Context`에 저장, `Close()`에서 `Delete()`

`callconv(.c)`가 아닌 함수 포인터는 하강 실패.

## 10. 심볼 이름 규칙

```
<prefix>_<snake(receiver)>_<snake(fn)>
```
- `prefix`는 build.zig의 `addGoBindings(.{ .prefix = "zg" })`에서 지정
- 자유 함수는 receiver 생략: `zg_open`
- 충돌 시 하강 실패 (자동 번호 부여 금지 — ABI 안정성 우선)

Go 이름:
- 타입: Zig 이름 그대로 (이미 PascalCase 관례)
- 메서드: `camelCase` → `PascalCase`
- 이니셜리즘 보정: `id → ID`, `url → URL`, `utf8 → UTF8` (테이블 기반, 확장 가능)

## 11. 하강이 실패해야 하는 경우

10가지 거부 조건과 진단 코드(`ZIGO001`–`ZIGO010`)는
[`00-constraints.md` §9](00-constraints.md)에 정의되어 있다.
실패는 전부 **선언 위치 + 수정 방법**을 포함한 진단으로 보고하며,
어떤 산출물도 쓰지 않는다.

## 12. cgo 링크 지시자

아래는 `.backend = .cgo`(기본값)에만 해당한다. `.backend = .purego`는 raw 패키지에
링크 지시자 대신 `purego` 기반 로더를 생성하고, 각 심볼을 함수 값으로 해석한다.
공유 라이브러리 경로는 컴파일 시점 플래그가 아니라 런타임 정책(`library_loading`)이
결정한다.

생성기는 빌드 그래프 안에서 동작하므로 install prefix와 `go_dir`의 상대 경로를 알고 있다.
따라서 사용자가 `-L`/`-I`를 손으로 쓰지 않는다.

```go
// go/internal/raw/raw_gen.go  (생성됨)
package raw

/*
#cgo CFLAGS:  -I${SRCDIR}/../../../zig-out/include
#cgo LDFLAGS: -L${SRCDIR}/../../../zig-out/lib -lmylib_zigo
#include "zigo_mylib.h"
*/
import "C"
```

- 경로는 `${SRCDIR}` 상대로만 생성한다. 절대 경로는 커밋되면 다른 머신에서 깨진다.
- 배포 시 라이브러리를 다른 위치에 두려면 `addGoBindings(.{ .cgo_flags = ... })`로 덮어쓴다.

module에 붙은 링크 정보는 입력별로 다음과 같이 전달된다.

| 입력 | 생성 결과 |
|---|---|
| `linkSystemLibrary(name, ...)` (`.no`/`.yes`) | `#cgo LDFLAGS`에 `-lname` |
| `linkSystemLibrary(name, .{ .use_pkg_config = .force })` | `#cgo pkg-config: name` |
| `addLibraryPath(dir)` (`lib_paths`) | `#cgo LDFLAGS`에 `-Ldir` |
| `linkFramework(name, .{})` | `#cgo darwin LDFLAGS`에 `-framework name` |
| `linkFramework(name, .{ .weak = true })` | `#cgo darwin LDFLAGS`에 `-weak_framework name` |
| `addIncludePath` / `rpaths` | 전달하지 않는다(아래 참고) |

`.force`만 pkg-config 줄로 간다. `.yes`는 "pkg-config를 시도하고 안 되면 `-lname`"이라는
뜻인데 `#cgo pkg-config:`에는 그 fallback이 없어서, 그대로 옮기면 pkg-config가 없는 머신에서
빌드가 깨진다.

`#cgo pkg-config:` 줄은 CFLAGS·LDFLAGS 줄보다 먼저 쓴다. cgo가 pkg-config 결과를 같은
블록의 두 줄과 합치기 때문이다. pkg-config 대상이 없으면 그 줄 자체를 생략한다.

`include_dirs`와 `rpaths`는 zigo가 전달하지 않는다. header는 zigo가 생성한 것 하나만
필요하고, rpath는 배포 정책이라 빌드 그래프가 정할 일이 아니기 때문이다. 둘 다 필요하면
`cgo_flags`로 직접 쓴다.

`cgo_flags`는 zigo가 계산한 include·library 경로 부분만 대체하고, module에서 온 system
library·framework·pkg-config 정보는 그대로 덧붙인다. 이 정보까지 빼려면 module에서 링크
자체를 하지 않아야 한다.

`.backend = .purego`는 어떤 링크 지시자도 내보내지 않는다. 시스템 라이브러리는 native
공유 라이브러리 자신이 이미 링크하고 있어야 한다. 반대로 `.cgo_static`은 Go 링크 시점에
archive를 푸는 것이므로, native가 쓰는 시스템 라이브러리가 이 블록에 모두 나타나야 한다.
