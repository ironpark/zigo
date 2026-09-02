# SCOPE

- `src/reflect/walk.zig`: `*std.Io.Writer`/`*std.Io.Reader` 타입 동일성 인식, 새 TypeNode.
- `src/gen/ir/semantic.zig`: `TypeNode.io_stream = { .direction: enum { writer, reader } }`, JSON `"io_writer"`/`"io_reader"`, `param_meta.buffer`.
- `src/gen/validate.zig`: 위치 제한 진단(새 코드, 계획 69 이후 다음 번호).
- `src/gen/lower.zig`: 스트림 파라미터를 callback 모양(cgo: `size_t userdata`; purego: fn pointer + userdata)으로 lowering. `callback_convention` 영향 확인.
- `src/gen/emit.zig`: shim 어댑터(Zig), cgo 트램폴린·purego dispatcher(고정 시그니처 2종), `CallbackState` 확장(io 값과 저장된 Go error), 공개 래퍼 시그니처·error 표면화, rethrow.
- `src/gen/abi_diff.zig`: 타입 변경 breaking 확인.
- 새 예제 `examples/11-io-streams`(cgo·purego), 골든 `tests/generator_cases/io_stream`, 문서.

# CONTEXT

## Current implementation and bottlenecks

- callback 파라미터는 스칼라만 받고(`emit.zig:4911-4926 semanticScalar`, 슬라이스는 `unreachable`), 각 파라미터가 C 스칼라 하나로 lowering된다. 반환은 cgo 자유, purego는 void/i32만(`ZIGO014`).
- call-scoped callback: `renderCallbackHandleSetup`이 `xHandle := newXHandle(x)`와 `defer deleteCallbackHandle(xHandle)`을 내고, `.retained`만 handle에 붙인다.
- cgo 트램폴린은 `cgo.Handle(userdata).Value().(*CallbackState)`로 Go 값을 찾고 `defer recover()`로 패닉을 기록해 `-3`을 반환한다. purego는 시그니처별 영구 dispatcher 하나와 정수 토큰 registry, `-3`(패닉)/`-4`(삭제된 토큰).
- `Writer.VTable.drain(w, data, splat)`은 `buffer[0..end]`를 먼저 소비하고 `data` 각 슬라이스, 마지막 원소를 `splat`번 반복해 쓴다. 반환은 `data`에서 소비한 바이트 수. `Reader.VTable.stream(r, w, limit)`은 `limit` 이하를 `w`에 쓰고 개수를 반환하며, EOF는 `error.EndOfStream`.

## Target structure and invariants

- **인식**: `walk.zig`에서 파라미터 타입이 `*std.Io.Writer` 또는 `*std.Io.Reader`(타입 동일성, `@typeName` 비교 아님)면 `TypeNode.io_stream`. 파라미터 위치에서만 허용. 반환·필드·callback 시그니처·tagged union payload·슬라이스 원소는 거부. `retention == .retained`도 거부(어댑터가 호출 스택에 산다).
- **ABI**: 스트림 파라미터 하나는 고정 시그니처의 callback 하나로 lowering된다.
  - writer: `fn (ptr: [*]const u8, len: usize, userdata: usize) callconv(.c) i32` — 0 성공, `-1` WriteFailed(Go error 저장됨), `-3` Go 패닉.
  - reader: `fn (ptr: [*]u8, cap: usize, userdata: usize) callconv(.c) i32` — `n >= 0` 읽은 바이트(0은 EOF), `-1` ReadFailed, `-3` 패닉. `cap`은 `i32` 범위로 clamp.
  - cgo: `size_t userdata`만 C 시그니처에 실리고 shim이 고정 `//export` 심볼을 참조(기존 `fixed_go_export`). purego: fn pointer + `uintptr_t userdata`(기존 `function_pointer_userdata_v2`). 반환이 i32라 purego 제약을 만족한다.
  - semantic.json: `{"kind": "io_writer"}`/`{"kind": "io_reader"}`, `param_meta.buffer`(기본 65536, 최소 4096, 최대 16 MiB)는 `buffer` 필드로 직렬화. abi_diff: kind 변경 breaking, buffer 변경 compatible.
- **shim 어댑터(Zig)**: 파라미터마다 `var buf: [N]u8 = undefined; var adapter = zigoWriterAdapter{ .interface = .{ .vtable = &.{ .drain = drain }, .buffer = &buf }, .callback = ..., .userdata = ... };` 후 `&adapter.interface`를 대상 함수에 넘긴다. `drain`은 `@fieldParentPtr("interface", w)`로 어댑터를 찾아 `buffer[0..end]` → `data[0..len-1]` → 마지막 원소 `splat`회 순으로 Go 콜백을 부르고, 실패(-1/-3)는 `error.WriteFailed`로. 함수 반환 전 `interface.flush()`를 호출한다(대상 함수가 flush하지 않아도 남은 버퍼가 나가야 한다). Reader 어댑터의 `stream`은 `limit.slice(try w.writableSliceGreedy(1))`에 Go 콜백으로 채우고 `w.advance(n)`, `n == 0`이면 `error.EndOfStream`. `-3`을 받은 뒤에는 이후 콜백을 부르지 않고 즉시 실패한다(패닉한 Go 코드를 재진입하지 않기 위해). 어댑터 코드는 함수마다 복제하지 않고 shim 파일에 한 번 낸다.
- **Go 쪽**: `CallbackState`에 `writer io.Writer`, `reader io.Reader`, `err error`를 추가(또는 스트림 전용 state 타입). 트램폴린은 `w.Write(unsafe.Slice(ptr, len))`으로 쓰고 short write는 `io.ErrShortWrite`, error는 `state.err`에 저장 후 `-1`. 읽기는 `r.Read(buf)`; `n == 0 && err == nil`이면 재시도 없이 0을 돌려주되 `io.EOF`만 EOF로 보고 다른 error는 저장 후 `-1`. 공개 래퍼는 `io.Writer`/`io.Reader`를 받아 call-scoped handle을 만들고, native 호출 뒤 `state.err != nil`이면 native 결과와 무관하게 `&StreamError{Operation, Parameter, Err}`(Unwrap으로 원 error)를 반환한다. 패닉은 기존 `zigoRethrowCallbackPanic`. nil `io.Writer`는 `HandleError`류의 인자 오류로 즉시 반환.
- **스레드**: 콜백은 native 호출 안에서 같은 스레드에서 동기 호출되므로 Go 값은 호출 goroutine이 소유한다. 대상 함수가 다른 스레드로 어댑터를 넘기면 정의되지 않음 — 문서화.
- **버퍼**: `param_meta.<name>.buffer = N`. 스택 배열이므로 상한을 두고, 큰 값은 `std.heap.c_allocator`로 힙 할당(계획 69의 `.allocator`가 있으면 그것) — 임계값 256 KiB.
