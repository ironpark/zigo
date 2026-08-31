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

**out 슬라이스에 `p_written`을 항상 추가**하는 이유: Zig의 `!usize` 반환이 흔히
"쓴 개수"를 의미하나 이를 신뢰할 수 없으므로, 명시적 out 파라미터로 계약을 고정한다.

**Go 포인터 규칙 검증:** `element`가 포인터·슬라이스·문자열을 포함하면 하강 실패
(Go 포인터를 담은 Go 메모리 전달 금지). 진단 메시지에 대안(핸들 배열)을 제시한다.

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
| `extern struct` | 값 전달. C struct 미러링 + Go struct 미러링 |
| `packed struct` | 정수 백킹으로 전달 (`u32` 등) + Go 비트 접근자 |
| 일반 `struct` | **opaque only.** 포인터로만 전달 |

일반 struct의 레이아웃은 Zig 명세상 보장되지 않으므로 값 전달을 시도하지 않는다.
사용자가 값 전달을 원하면 `extern struct` 선언이 요구된다 (진단이 이를 안내한다).

opaque 타입은 다음을 생성한다:
```go
type Context struct {
    ptr  unsafe.Pointer
    once sync.Once          // Close 멱등성
}
func NewContext(...) (*Context, error)
func (c *Context) Close()   // deinit 대응 함수가 있을 때만
```

`runtime.SetFinalizer`는 붙이지 않는다. `.auto_cleanup = true`인 Go 1.24+ 프로젝트만
wrapper를 참조하지 않는 별도 resource state로 `runtime.AddCleanup`을 붙인다. 명시적
`Close()`가 cleanup을 `Stop`하고 같은 해제 루틴을 호출하며, 각 native 호출은
`runtime.KeepAlive`로 wrapper의 생존 구간을 고정한다. cleanup은 실행 시점과 프로그램
종료 전 실행을 보장하지 않으므로 `Close()`가 항상 기본 계약이다.

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

## 8. 소유권 → Go 매핑

| ownership | Go |
|---|---|
| `callee` (호출자가 해제 책임) | `*T` + `Close()` 생성 |
| `borrowed` | `TRef` 래퍼 (Close 없음, 원본 수명에 종속) |

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
- `linkSystemLibrary`는 `-l...`로, `linkFramework`는 Darwin 전용 `-framework ...`로
  자동 반영한다.
