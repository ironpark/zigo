# SCOPE

- callback error: `src/reflect/walk.zig`(callback 반환의 Go 표면 표시는 semantic 수준 — Zig 시그니처는 그대로 i32), `src/gen/emit.zig`(트램폴린이 `err`를 state에 저장하고 실패 코드 반환, 공개 래퍼가 저장 error 우선 반환), `validate.zig`(Go error를 돌려주려면 Zig callback 반환이 i32여야 함).
- `[]byte` 경로: `emit.zig` 공개 래퍼의 타입 단정과 shim의 `Reader.fixed` 분기(스트림 파라미터 ABI에 "슬라이스로 전달" 변형 추가 — lowering에 두 인자 세트가 필요).
- 스트림 반환: `walk.zig`·`semantic.zig`(반환 위치의 `io_stream` 허용, borrowed만), `emit.zig`(handle 메서드 `Write`/`Read`/`Flush` 생성, `*std.Io.Writer`를 handle에 보관하지 않고 매 호출 Zig에서 다시 얻음).
- 취소: `param_meta`/함수 메타 `.cancel = .{ .flag = "<decl path or param name>" }`, shim이 `std.atomic.Value(bool)`를 만들어 대상 함수의 취소 파라미터로 넘기고, Go가 `ctx.Done()` 감시 goroutine으로 raw `cancel` 심볼을 호출.

# CONTEXT

## Current implementation and bottlenecks

- callback 트램폴린은 `defer recover()`로 패닉만 기록하고 `-3`을 돌려준다(`emit.zig:2486-2540`). Go error 채널은 없다. purego dispatcher는 시그니처별 하나(`:1866-1953`).
- 70이 만드는 스트림 `CallbackState`는 `err error`를 갖는다. 같은 필드를 모든 callback state에 두면 1이 된다.
- 스트림 파라미터 ABI(70)는 콜백 하나. 슬라이스 변형은 `ptr, len` 두 스칼라가 추가로 필요하며 "둘 중 하나가 유효"를 shim이 구별해야 한다(콜백 fn pointer/userdata가 0이면 슬라이스 경로).
- Zig 함수가 `*std.Io.Writer`를 반환하는 경우 그 포인터는 대상 객체가 소유하며 수명이 handle에 묶인다. handle 획득/해제 모델 안에서 매 `Write` 호출마다 `writer()`를 다시 얻으면 포인터를 보관하지 않아도 된다.
- 취소: Zig 쪽에 표준 규약이 없다. zigo가 규약을 정해야 한다: 대상 함수가 `*const std.atomic.Value(bool)`(또는 `*std.atomic.Value(bool)`) 파라미터를 받고 폴링한다.

## Target structure and invariants

- **callback error**: Go callback 타입은 Zig 반환이 i32일 때 `func(...) (int32, error)`로 생성(옵션 `param_meta.<cb>.go_error = true`, 기본 false로 기존 골든 불변). 트램폴린은 `err != nil`이면 state에 저장하고 `-5`(새 코드, `-3` 패닉·`-4` 삭제 토큰과 구별)를 반환. Zig 대상 함수는 `-5`를 자기 규약대로 처리(대개 error 반환). 공개 래퍼는 native 결과와 무관하게 저장 error를 `&CallbackError{Operation, Callback, Err}`로 반환. retained callback의 error는 다음 메서드 호출에서 반환(패닉 규칙과 동일).
- **`[]byte` 경로**: Go 공개 래퍼가 `io.Reader`에 대해 `interface{ Bytes() []byte }`(`bytes.Buffer`)와 `*bytes.Reader`(`Len`+`ReadAt`… 단순히 `*bytes.Reader`는 내부 슬라이스 접근이 없으므로 `bytes.Buffer`와 사용자 정의 `interface{ zigoBytes() []byte }`만) 단정 후 슬라이스 경로. ABI: 스트림 파라미터가 `(callback, userdata, ptr, len)` 네 인자로 확장 — 70과 함께 설계되지 않았다면 breaking이므로 70 진행 중이면 70에 합쳐 넣는 것을 우선 검토.
- **스트림 반환**: `fn writer(self) *std.Io.Writer` → Go `Write(p []byte) (int, error)`, `Flush() error`; `fn reader(self) *std.Io.Reader` → `Read(p []byte) (int, error)`(0바이트+EOF 규약). shim은 `self.writer().writeAll(p)`/`readSliceShort`를 호출하는 export 함수를 만든다. handle 획득/해제·poison 규칙 그대로.
- **취소**: 함수 메타 `.cancel = .{ .param = "cancel" }` — 대상 함수의 해당 파라미터 타입은 `*const std.atomic.Value(bool)`이어야 한다(검증). shim은 호출마다 플래그를 만들고 그 주소를 `size_t token`으로 Go에 노출하는 대신, 더 단순하게 **Go가 소유하는 플래그**: C 시그니처에 `const uint8_t *cancel` 하나를 추가하고 Go가 `atomic.Bool` 주소를 넘긴다(Go 메모리를 C에 넘기는 규칙 준수, 호출 동안만 유효). Go 래퍼는 `ctx`를 첫 인자로 받고 `ctx.Done()`을 기다리는 goroutine이 플래그를 세운 뒤 호출 종료 시 goroutine을 정리. 취소되어 Zig가 `error.Canceled`(대상 함수의 error set에 있어야 함)를 돌려주면 `context.Canceled`(또는 `ctx.Err()`)로 매핑. shim은 Go 플래그를 `std.atomic.Value(bool)` 로 재해석하지 않고 폴링 함수 포인터를 넘기는 방식과 비교해 단순한 쪽 선택 — 계획 시작 시 결정하고 기록.
