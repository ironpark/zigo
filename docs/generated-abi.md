# 생성 ABI와 메타데이터 참조

C 헤더를 검토하거나 바인딩의 호환성을 판단할 때 사용하는 상세 문서입니다.
일상적인 생성·검사 명령은 [생성물과 CI 관리](generated-code.md)에 있습니다.

| 확인할 계약 | 관련 절 |
|---|---|
| 구조체·optional·출력 slice 표현 | [구조체 변경](#extern-struct에-필드를-더하는-일), [optional](#optional의-c-표현), [written](#out-slice가-채운-개수) |
| 스트림·콜백·취소의 C 경계 | [스트림](#stdio-스트림-어댑터), [콜백 오류](#콜백이-돌려주는-go-error), [취소](#취소-플래그) |
| 버퍼 복사와 레이아웃 검사 | [struct slice](#값-struct-slice의-캐스트-경로) |
| 호환성 비교에 기록되는 필드 | [메타데이터 계약](#메타데이터-계약) |
| materialized 결과 버퍼 형식 | [Materialized 버퍼 ABI](abi.md) |

## `extern struct`에 필드를 더하는 일

`extern struct`에 필드를 추가하면 `abi-check`가 breaking으로 보고합니다. Go에 보이는 것은
값이지만 C 경계는 포인터(`const T*` 또는 `T*`)만 주고받고 크기는 함께 넘기지 않기 때문에,
버퍼를 잡은 쪽과 읽고 쓰는 쪽의 필드 수가 다르면 곧바로 메모리 문제가 됩니다.

- 반환·out 자리에서는 Go가 버퍼를 잡습니다. native만 새 필드를 아는 상태라면 native가 옛
  버퍼의 끝을 넘어 씁니다.
- 입력 자리에서는 native가 옛 버퍼의 끝을 넘어 읽어 새 필드를 쓰레기 값으로 봅니다.
- purego는 미러 struct의 주소를 그대로 넘기므로 이 어긋남이 그대로 드러납니다.

`.cgo_static`은 native archive를 Go 바이너리에 함께 링크합니다. Go 생성 코드와 archive를
같은 선언에서 다시 만들면 함께 갱신할 수 있지만, 정적 링크 자체가 두 버전의 일치를
보장하지는 않습니다. `abi-check`는 링크 방식을 가정하지
않으므로 판정은 계속 breaking입니다. 필드를 더해야 한다면 새 struct와 새 함수를 추가하거나,
소비자와 native를 같은 시점에 배포하세요.

## optional의 C 표현

`?T`는 presence와 값을 함께 나릅니다. 어느 쪽도 값 하나에 겹쳐 넣지 않으므로 부재와
"값이 0인 present"가 언제나 구별됩니다.

- 매개변수는 nullable pointer 하나입니다. `?u32`는 `const uint32_t *value`, `?Point`는
  `const zg_point *origin`이 되고, NULL이 부재입니다. scalar에도 별도의 `bool has_x`를
  두지 않는 이유는 포인터 하나가 이미 두 상태를 다 담기 때문이고, 덕분에 `extern struct`
  optional과 lowering이 한 갈래로 유지됩니다.
- 반환은 presence를 C 반환값으로 올립니다. `?T`를 돌려주는 함수는 `uint8_t`를 반환하고
  값은 `T *out_result`로 씁니다. 부재일 때 shim은 `out_result`를 건드리지 않습니다.
- error union과 겹치면 상태 코드가 이미 error에 쓰이므로 presence가 자기 out parameter를
  갖습니다: `int32_t f(..., uint8_t *out_result_has, T *out_result)`.

`?[]T`는 다릅니다. slice는 이미 포인터를 갖고 있으므로 presence 플래그를 더하지 않고
그 포인터의 NULL을 부재로 씁니다. 매개변수는 `const T *x_ptr, size_t x_len` 그대로이고,
반환은 `T **out_result_ptr, size_t *out_result_len`에 NULL을 쓰는 것으로 부재를 알립니다.
길이 0인 **존재하는** slice는 여전히 non-NULL 포인터로 건너가므로 두 상태가 섞이지
않습니다 — 생성된 Go raw 계층이 존재하지만 비어 있는 slice에 대해 자기 자리 표시자 주소를
넘기는 이유입니다.

caller-owned optional slice는 이 포인터 표현에 기존 copy/release 경로를 결합합니다.
`?[]T`와 `!?[]T` 모두 포인터가 non-NULL인 성공 경로에서만 Go 메모리로 복사하고 release
심볼을 호출합니다. 부재나 error에서는 out buffer를 읽거나 release하지 않습니다. 공개 결과는
`([]T, bool)`/`([]T, bool, error)`이고, c_string variant는 `string`을 반환합니다.

purego도 같은 시그니처를 씁니다. scalar child는 `*T`로, `extern struct` child는
`unsafe.Pointer`로 바인딩 테이블에 선언됩니다.

`semantic.json`은 기존 `optional` 노드를 그대로 씁니다. `abi-check`는 `T`와 `?T`의
교체를 breaking으로 봅니다.

## 취소 플래그

`.cancel = .{ .param = "..." }`이 붙은 함수는 C 시그니처에 `const uint32_t *<이름>`을
그대로 유지하고, Go 공개 시그니처에서는 그 파라미터가 사라지고 `ctx context.Context`가
첫 인자로 들어옵니다. shim은 포인터를 `@ptrCast`로 `*const std.atomic.Value(u32)`에
맞춰 대상 함수에 넘길 뿐, 아무것도 만들지 않습니다 — 워드는 Go의 것입니다.

생성된 Go는 호출 프레임에 `var zigoCancel uint32`를 두고, `ctx.Done()`을 기다리는
goroutine이 `atomic.StoreUint32`로 그것을 세웁니다(`zigoStop` 채널로 호출 종료 시 정리).
이미 취소된 ctx는 goroutine 없이 호출 전에 세우고, 취소될 수 없는 ctx는 goroutine을
만들지 않습니다. cgo는 C에 넘긴 Go 포인터를 호출 동안 고정하므로 그대로 넘기고, purego
백엔드는 보장이 없으므로 `runtime.Pinner`로 고정하고 호출 뒤 `runtime.KeepAlive`합니다.

상태 코드가 `Canceled`로 풀리고 `ctx.Err() != nil`이면 공개 래퍼는 `ctx.Err()`를 반환합니다.
`.cancel`이 없는 함수의 생성물은 바이트 그대로입니다.

## Zig가 내주는 스트림

`fn writer(self) *std.Io.Writer`는 파싱과 lowering 사이에서 연산으로 확장됩니다
(`src/gen/stream_return.zig`): writer는 `write`·`flush` 둘, reader는 `read` 하나입니다.
확장된 함수는 그때부터 평범한 메서드라 헤더·shim·raw·공개 Go가 모두 기존 경로를 씁니다.
`semantic.json`에는 확장 전의 Zig 메서드가 남으므로 `abi-diff`는 Zig 표면을 비교합니다.

| Zig | C | Go |
|---|---|---|
| `fn writer(self) *std.Io.Writer` | `int32_t <p>_<t>_write(T*, const uint8_t*, size_t, ptrdiff_t*)` | `Write([]byte) (int, error)` |
| | `int32_t <p>_<t>_flush(T*)` | `Flush() error` |
| `fn reader(self) *std.Io.Reader` | `int32_t <p>_<t>_read(T*, uint8_t*, size_t, ptrdiff_t*)` | `Read([]byte) (int, error)` |

개수는 `usize`가 아니라 `isize`(`ptrdiff_t`)입니다. Go가 그것을 `int`로 적어야
`io.Writer`·`io.Reader`를 만족하기 때문입니다. shim은 연산마다 헬퍼
(`<symbol>_stream`)를 하나 내고, 그 안에서 접근자를 **다시 불러** 스트림을 얻습니다 —
포인터는 헬퍼 밖으로 나가지 않습니다. `read`는 `readSliceShort`를 쓰므로 스트림 끝이
짧은 개수로 오고, 공개 Go가 0을 `io.EOF`로 옮깁니다.

## 콜백이 돌려주는 Go error

`param_meta.<이름>.go_error`가 켜진 콜백은 Go 타입이 `func(...) (int32, error)`가 되고, C
시그니처는 그대로입니다. trampoline(cgo)과 dispatcher(purego)는 `err != nil`이면 그 error를
`CallbackState`/registry entry의 error 자리에 저장하고 결과로 **`-5`**를 돌려줍니다 —
`-3`(Go panic), `-4`(삭제된 토큰), `-1`(스트림 실패)과 구별되는 값입니다. 저장 자리는 스트림
error와 같은 필드입니다: 저장 규칙이 같고(먼저 온 것이 이긴다, 가져가면 지워진다) 이름만
`TakeStreamError`/`TakeCallbackError`로 갈립니다.

공개 래퍼는 native 상태 코드를 보기 전에 `zigoCallbackError`로 그것을 가져와 `*CallbackError`
로 반환합니다. retained 콜백은 native 호출 뒤 handle의 콜백 슬롯을 확인합니다.
따라서 동기적으로 발생한 오류는 해당 호출에서, 호출 사이에 발생한 오류는 다음 호출에서
전달될 수 있습니다. 생성자 경로에서 반환할 때는 이미 등록한 retained handle을
먼저 해제합니다.

`go_error`는 파라미터가 아니라 ABI 시그니처의 성질입니다: Go 타입 하나와 purego dispatcher
하나를 시그니처마다 공유하기 때문에, 같은 시그니처를 쓰는 파라미터는 모두 같은 답을 씁니다.

## `std.Io` 스트림 어댑터

`*std.Io.Writer`/`*std.Io.Reader` 파라미터는 고정 시그니처 콜백 하나로 내려갑니다.

| 방향 | 콜백 | 결과 |
|---|---|---|
| writer | `i32 (const uint8_t *ptr, size_t len, size_t userdata)` | `0` 성공, `-1` Go error 저장, `-3` Go panic |
| reader | `i32 (uint8_t *ptr, size_t capacity, size_t userdata)` | `n >= 0` 읽은 바이트(`0`은 스트림 끝), `-1` error, `-3` panic |

cgo에서는 C 시그니처에 userdata만 실리고 shim이 바인딩마다 하나씩 있는 고정 `//export`
심볼(`<prefix>_zigo_stream_write`, `_read`)을 이름으로 참조합니다. purego에서는 dispatcher
포인터가 userdata 앞에 함께 실리고, 진입점은 다른 콜백과 같이 `_purego_v2` 접미사를 받습니다.
reader에는 `(const uint8_t *<name>_data, size_t <name>_data_len)` 한 쌍이 더 붙어 있습니다.
이것이 무콜백 경로입니다: `_data`가 널이 아니면 shim은 `std.Io.Reader.fixed`로 그 슬라이스를
감싸고 트램폴린을 한 번도 부르지 않으며, 널이면 예전처럼 어댑터를 씁니다. 생성된 Go는
`io.Reader`가 `zigoBytes() []byte`나 `Bytes() []byte`를 가질 때만 슬라이스를 채웁니다
(`zigoReaderBytes` 헬퍼). 빈 슬라이스도 "없음"과 구별해야 하므로 길이 0일 때는 raw 계층의
`zigoEmptyStreamData` 주소를 넘겨 포인터가 널이 되지 않게 합니다. 이 경로는 소비한 바이트
수를 되돌려 주지 않으므로 Go reader는 전진하지 않습니다.

shim은 어댑터 타입 두 개를 파일당 한 번만 내고, 파라미터마다 staging 버퍼와 어댑터를 만들어
`&adapter.interface`를 대상 함수에 넘깁니다. writer 어댑터의 `drain`은 버퍼에 들어가는
조각은 버퍼에 채우고 큰 조각은 직접 전달해 작은 쓰기를 모읍니다. 실제 호출 횟수는 총량,
버퍼 크기, 명시적 flush와 writer 동작에 따라 달라집니다. 정상 반환 전에 `defer`로 `flush`합니다.
reader 어댑터의 `stream`은 대상 writer의 쓰기 가능한 영역을 Go가 직접 채우게 하므로 읽기당
복사가 없습니다. `-1`이나 `-3`을 한 번 받은 어댑터는 이후 Go를 다시 부르지 않습니다.

Go 쪽에서는 `CallbackState`(cgo)와 토큰 레지스트리 항목(purego)이 스트림 값과 저장된 error를
함께 들고, 공개 래퍼가 native 호출 뒤 `TakeStreamError`로 그것을 가져와 `*StreamError`로
반환합니다. 이 검사는 native 상태 코드 검사보다 먼저 일어납니다.

## out slice가 채운 개수

`.direction = .out` slice가 얼마나 채워졌는지는 `written` 힌트가 정합니다. 기본값
`.all`은 C 시그니처에 `{name}_written`(`size_t *`) 파라미터를 하나 더 붙이고, shim이
거기에 버퍼 길이를(오류 경로에서는 0을) 씁니다. `.@"return"`은 개수를 함수의 반환값으로
알리므로 파라미터를 붙이지 않고, raw 계층도 그 반환값을 그대로 읽습니다. 두 힌트의 C
시그니처가 다르므로 힌트를 바꾸는 것은 breaking입니다.

오류 경로의 작성 개수 0은 native 쓰기를 롤백하지 않습니다. 직접 전달되는 버퍼는
이미 변경되었을 수 있습니다. [출력 버퍼 계약](bindings-buffers.md#얼마나-채워졌는가-written)을 참고하세요.

## 값 struct slice의 캐스트 경로

bool·atomic 필드가 없는 `extern struct`는 Go mirror(`TData`)와 공개 타입 `T`, 그리고 C struct가
모두 같은 배치를 가집니다. 이런 원소의 slice 파라미터는 어느 계층에서도 복사하지 않고
주소만 넘어갑니다.

- 공개 계층: `[]T`를 `unsafe.Slice`로 `[]TData`로 재해석합니다.
- cgo raw 계층: `(*C.x)(unsafe.Pointer(&values[0]))`를 넘깁니다.
- purego raw 계층: 원래부터 mirror의 주소를 넘겼으므로 그대로입니다.

즉 두 백엔드가 같은 경로를 씁니다. native는 호출자의 버퍼에 직접 쓰고, 돌아오는 복사도
없습니다.

반환 방향도 같은 배치를 씁니다. raw 계층은 반환 slice를 C 메모리에서 `[]TData`로 한 번에
`copy`해 핸들 수명과 끊어 놓고(`.returns = .caller`는 복사한 뒤 release합니다), 공개 계층은 그
결과를 `zigo{T}SliceView`로 `[]T`로 재해석하기만 합니다. 복사는 계층 전체에서 한 번뿐이고,
길이가 0이면 `nil`입니다. bool·atomic 필드가 있어 캐스트할 수 없는 원소도 raw 계층의 `copy`는
같고, 공개 계층에서만 `zigo{T}SliceFromRaw`로 원소별 변환을 한 번 합니다.

배치가 같다는 전제는 생성 코드가 compile 시점에 못 박습니다. shim의 `zigoAbiGuard`가
Zig 타입을 헤더에 대해 고정하고, cgo raw 파일이 모든 `TData`를 `C.x`에 대해, 공개 struct 파일이
캐스트 가능한 `T`를 `TData`에 대해 크기와 필드 offset까지 단정합니다.

```go
var _ = [1]struct{}{}[unsafe.Sizeof(Point{})-unsafe.Sizeof(raw.PointData{})]
var _ = [1]struct{}{}[unsafe.Offsetof(Point{}.X)-unsafe.Offsetof(raw.PointData{}.X)]
```

배열 index가 상수로 평가되므로 배치가 어긋나면 `go build`가 그 자리에서 실패합니다.
bool·atomic 필드가 있는 struct는 공개 계층에서 원소별 변환 경로를 사용합니다.

## 상태 코드 범위

error union 함수와 projection·snapshot 접근자는 모두 `int32_t`를 돌려줍니다.

| 코드 | 의미 |
|---|---|
| `0` | 성공 (함수) / variant 불일치 (projection) |
| `1` | 성공 (projection·snapshot) |
| `2` | 잘못된 handle (projection·snapshot) |
| `1` 이상 | `errors.lock.json`에 잠긴 Zig 오류 (함수) |
| `-2` | 예약. 이전 릴리스의 panic 코드이며 지금은 생성되지 않음 |
| `-3`, `-4` | 콜백: Go panic, 삭제된 토큰 |
| `-256` 이하 | 붙잡힌 Zig panic. `-(256 + 시퀀스)`이며 `{prefix}_caught_panic_message(code)`가 메시지를 돌려줌 |

## UTF-8 문자열의 복사 횟수

`.semantic = .utf8_string`인 `[]const u8` 입력은 raw 계층까지 Go `string`으로 내려가고,
raw는 `unsafe.StringData`로 그 바이트를 호출 동안만 native에 빌려줍니다. 복사가 없습니다.
optional 입력은 `*string`입니다. 반환은 raw가 native 메모리에서 바로 `string`을 만들어
(cgo `C.GoStringN`, purego `string(unsafe.Slice(...))`) 공개 계층은 그대로 돌려줍니다.
복사는 한 번입니다. `.c_string`은 NUL이 필요하므로 입력을 계속 복사합니다.

## 메타데이터 계약

`semantic.json`은 reflection 이후 확정된 바인딩 계약이며 `abi-check`의 비교 단위입니다.
`go-check`는 `go_dir`의 Go 생성 파일만 비교하므로 metadata도 `go` 실행 후 같은 commit에
포함되었는지 리뷰에서 확인해야 합니다.

함수의 소속은 두 축입니다. `namespace`는 함수가 **선언된** Zig 컨테이너이고, 심볼과 raw Go
이름이 여기서 나옵니다. Go의 소속은 `go_owner`이며, 타입 밖에 선언된 생성자를
`.constructs`로 짝지었거나 한 handle의 메서드가 다른 handle을 생성할 때처럼 둘이 다를 때만
문서에 나타납니다. 후자의 `receiver`는 호출 대상을, `go_owner`는 반환 handle을 가리킵니다.
shim이 부를 Zig 선언이
`<소유자>.<이름>`으로 적히지 않는 경우(타입 밖에 선언된 소멸자, `.name`으로 이름을 바꾼
함수)에는 `zig_path`가 그 경로를 그대로 적습니다. 둘 다 기본값과 같으면 생략됩니다.
receiver 앞에 주입 파라미터가 선언된 함수(`fn free(gpa: Allocator, self: *T) void`)는
`receiver_at`에 receiver 앞의 `params` 항목 수를 적고, shim은 그 자리에 `self`를 넣어
호출합니다. C와 Go 시그니처는 영향을 받지 않으므로 이 필드도 `abi-diff` 대상이 아닙니다.

주입 파라미터는 C 시그니처에도 Go 시그니처에도 없으므로 `abi-diff`는 그것을 빼고 비교하고,
`go_owner`가 바뀌면 Go 표면이 움직이므로 breaking으로 봅니다.
`child_of_receiver: true`는 설정한 constructor에만 나타납니다. gain/loss는 C signature를
움직이지 않지만 부모 `Close`의 동작과 생성된 Go handle 구조를 바꾸므로 ABI-compatible
Go-surface 변경으로 보고됩니다.
`borrowed_return: true`도 `.returns = .borrowed`를 명시한 함수에만 나타납니다. 생략된
`ownership: borrowed`와 구분되며, borrowed/caller 변경은 공개 Go handle의 cleanup 계약을
바꾸므로 breaking입니다.

하위 패키지가 선언되면 최상위 `packages` 배열은 `{path,name,doc}`을 기록하고, 각 type과
function은 기본 패키지가 아닐 때만 `package` 이름을 기록합니다. 기본 패키지의 필드는 생략되어
기존 단일 패키지 문서는 바이트 단위로 그대로입니다. type이나 function의 `package` 변경은
Go import path가 달라지는 breaking 변경입니다.

함수의 `symbol` 필드는 그 함수가 export되는 C 심볼 이름입니다. 규칙은 하나뿐이고
(`{prefix}_{owner}_{name}`, owner는 `receiver` 또는 `namespace`, 모두 snake_case로
정규화), 소유 타입이 없으면 `{prefix}_{name}`입니다. `namespace`가 중첩 경로를 담고 있으면
segment마다 따로 정규화해 `_`로 잇습니다 — `unicode.codepointWidth`는
`zg_unicode_codepoint_width`입니다. raw Go 이름도 같은 segment 단위로 Pascal 결합해
`UnicodeCodepointWidth`가 되고, ABI identity는 `unicode.codepointWidth`입니다. 헤더, 링커, 심볼 충돌 검사, 그리고
이 메타데이터가 모두 같은 규칙 함수(`naming.functionSymbolAlloc`)에서 이름을 받습니다.
백엔드가 덧붙이는 장식은 포함하지 않습니다 — purego의 callback 변형이 쓰는 `_purego_v2`
접미는 lowering 단계의 산물이므로 `symbol`에는 나타나지 않습니다.

0.x의 이전 판은 소유 타입을 빠뜨린 `{prefix}_{name}`을 기록해 같은 문서 안에서
`zg_deinit` 같은 이름이 중복됐습니다. `abi-check`는 옛 값이 그 옛 규칙과 일치하고 새 값이
현재 규칙과 일치하는 경우에 한해 이를 `exported C symbol metadata corrected`라는
compatible 변경으로 보고합니다. 실제로 심볼이 옮겨간 변경은 그대로 breaking입니다.

`errors.lock.json`은 Zig error set 이름에 배정한 양수 code를 보존하는 append-only
상태입니다. 기존 이름의 삭제·변경·code 재사용은 거부됩니다. 새 오류가 생기면 Go 생성물과
lock 변경을 같은 커밋에 포함하세요.

함수는 선택 필드 `source: { path, line, column }`을 가질 수 있습니다. `names.zig`가
`bindings.zig`(또는 그것이 `@import`하는 소스)를 AST로 스캔해 함수 선언 이름 토큰의
위치를 채우고, 함수의 각 파라미터에도 선택 필드 `source: { line, column }`(경로는 함수와
같으므로 생략)을 채웁니다. 둘 다 처음 일치한 소스 파일의 값을 쓰고 이후 갱신하지 않으며,
없으면 진단이 지금처럼 `semantic.json`을 가리킵니다. `abi_diff`는 이 필드를 비교하지
않습니다 — ABI가 아니라 진단이 가리키는 위치일 뿐입니다.

생성기는 파일을 모두 메모리에서 준비한 뒤 소스 트리에 반영합니다. validation이나 rendering
실패에는 기존 트리를 유지하지만, 최종 쓰기 중 전원 또는 filesystem 장애까지 하나의
transaction으로 복구하지는 않습니다.
