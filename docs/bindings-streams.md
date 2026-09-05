# 스트림과 취소

Go의 `io.Writer`, `io.Reader`, `context.Context`를 Zig API에 연결합니다. 선언의 기본 형태는 [`bindings.zig` 선언](bindings.md)을 참고하세요.

[Go 스트림을 인자로 넘기기](#stdio-스트림-파라미터),
[Zig 스트림을 Go 메서드로 노출하기](#zig가-내주는-스트림),
[긴 호출 취소하기](#취소-cancel)는 각각 독립적으로 사용할 수 있습니다.

## `std.Io` 스트림 파라미터

`*std.Io.Writer`와 `*std.Io.Reader` 파라미터는 Go의 `io.Writer`와 `io.Reader`가 됩니다.
등록도 메타데이터도 필요 없습니다 — 타입 자체가 결정합니다.

```zig
// Zig
pub fn dump(self: *Document, w: *std.Io.Writer) error{WriteFailed}!void { ... }
pub fn load(self: *Document, r: *std.Io.Reader) error{ReadFailed}!usize { ... }
```

```go
// Go
func (d *Document) Dump(w io.Writer) error
func (d *Document) Load(r io.Reader) (uint, error)
```

shim이 파라미터마다 어댑터를 만들어 대상 함수에 넘깁니다. 어댑터는 staging 버퍼를 들고
있고, 버퍼가 찰 때만 Go의 `Write`/`Read`를 부릅니다. Zig 쪽이 한 줄씩 `writeAll`을 해도
경계를 넘는 횟수는 버퍼 크기가 정합니다: 총 `N` 바이트를 쓰면 `Write` 호출은
`ceil(N / 버퍼)`회를 넘지 않습니다. 함수가 돌아오기 전에 shim이 `flush`하므로 대상 함수가
직접 flush하지 않아도 남은 바이트가 나갑니다.

버퍼 크기는 `param_meta.<name>.buffer`로 바꿉니다. 기본값 65536, 최소 4096, 최대 16 MiB이며,
범위 밖은 `ZIGO023`으로 거부합니다. 262144바이트를 넘으면 스택 배열 대신 힙에서 잡습니다 —
바인딩이 `.allocator`를 정했으면 그 allocator, 아니면 `std.heap.c_allocator`입니다.

```zig
.{ .path = "Document.load", .params = .{"r"}, .param_meta = .{ .r = .{ .buffer = 4096 } } }
```

**실패와 panic.** Go `Write`가 error를 반환하면 그 error가 저장되고, native 호출이 끝난 뒤
공개 함수가 `*StreamError`로 감싸 돌려줍니다. native 결과보다 우선합니다: 출력이 도착하지
않은 작업에 라이브러리가 성공을 보고했더라도 호출자가 원하는 것은 자기 error입니다.
`Unwrap`이 원래 error를 내주므로 `errors.Is`가 그대로 통합니다. short write는
`io.ErrShortWrite`입니다. Go `Read`가 `0, io.EOF`를 주면 스트림 끝이고, 그 외의 error는
`*StreamError`로 돌아옵니다. Go 쪽이 panic하면 기존 콜백 경로와 같이
`*CallbackPanicError`로 재전파되며, 어댑터는 panic한 프레임을 두 번 부르지 않습니다.
`nil` 스트림은 native를 부르기 전에 `ErrNilStream`을 감싼 `*StreamError`로 거부합니다.

스트림 파라미터가 있는 함수는 Zig 반환 타입과 무관하게 Go에서 `error`를 함께 반환합니다.

**`[]byte` 무콜백 경로.** `io.Reader` 인자가 남은 바이트를 통째로 내줄 수 있으면 zigo는
슬라이스 하나를 그대로 넘기고, shim은 `std.Io.Reader.fixed`로 감쌉니다. 이때 경계를 넘는
콜백은 **0회**입니다. 자격이 있는 타입은 두 가지입니다.

- `Bytes() []byte`를 가진 타입 — 표준 라이브러리의 `*bytes.Buffer`가 여기 해당합니다.
  관례상 "아직 읽지 않은 바이트"를 뜻하는 메서드입니다.
- `zigoBytes() []byte`를 가진 타입 — 직접 정의한 타입을 이 경로에 넣는 공개 훅입니다.
  두 메서드가 다 있으면 `zigoBytes()`가 이깁니다.

그 밖의 모든 `io.Reader`(`*bytes.Reader`, 파일, 소켓, `io.LimitReader` 등)는 예전처럼
트램폴린으로 한 덩어리씩 읽습니다. `*bytes.Reader`에는 내부 슬라이스를 내주는 메서드가
없으므로 빠른 경로에 들어가지 않습니다.

빈 슬라이스도 "없음"이 아니라 "비어 있음"입니다: 빈 `*bytes.Buffer`는 빠른 경로로 즉시
스트림 끝이 되고, 콜백으로 되돌아가지 않습니다.

> **주의.** 이 경로를 타면 zigo는 Go reader를 **전진시키지 않습니다**. ABI가 native가
> 몇 바이트를 읽었는지 보고하지 않기 때문입니다. 호출 뒤에도 `*bytes.Buffer`에는 같은
> 바이트가 그대로 남아 있습니다. 한 reader를 여러 호출에 나눠 쓰면서 소비 위치가
> 중요하다면 `bytes.NewReader(...)`처럼 빠른 경로에 들어가지 않는 타입을 쓰십시오.

**스레드.** 콜백은 native 호출 안에서 같은 스레드로 동기 호출되므로, Go 값은 호출한
goroutine이 계속 소유합니다. 대상 함수가 어댑터를 다른 스레드로 넘겨 호출이 끝난 뒤에도
쓰면 동작은 정의되지 않습니다.

**허용되지 않는 위치.** 어댑터가 호출 스택에 살기 때문에 스트림은 파라미터 자리에서만,
그리고 call-scoped로만 쓸 수 있습니다. extern struct 필드, 콜백 시그니처, 슬라이스 원소,
optional, `.retention = .retained`는 각각 이유를 담은 `ZIGO023`으로 거부합니다. 반환 위치는
아래의 규칙을 따릅니다.

## Zig가 내주는 스트림

메서드가 스트림을 **내줄** 수도 있습니다. 포인터 자체는 Go로 건너가지 않습니다 — 그것은
객체의 것이고, 객체보다 오래 사는 Go 값은 안전하게 만들 수 없기 때문입니다. 대신 Go가
그 스트림에 실제로 원하는 것, 즉 `io.Writer`·`io.Reader`가 요구하는 메서드를 handle에
생성합니다.

```zig
// Zig
pub fn writer(self: *Sink) *std.Io.Writer { return &self.inner.writer; }
pub fn reader(self: *Source) *std.Io.Reader { return &self.inner; }
```

```go
// Go
func (s *Sink) Write(bytes []byte) (int, error)
func (s *Sink) Flush() error
func (s *Source) Read(buffer []byte) (int, error)

io.Copy(sink, src)   // 둘 다 그대로 표준 인터페이스다
io.Copy(dst, source)
```

메서드마다 shim이 `writer()`/`reader()`를 **다시 부릅니다**. 포인터를 어디에도 보관하지
않으므로 상하지 않고, 수명 질문은 receiver handle의 기존 획득/해제/poison 규칙이 그대로
답합니다 — 닫힌 handle의 `Write`는 다른 메서드와 똑같이 `ErrInvalidHandle`입니다.

`Read`는 `io.Reader` 규약을 따릅니다: 스트림 끝은 0바이트가 아니라 `io.EOF`입니다. Zig 쪽은
`readSliceShort`가 짧은 개수로 끝을 알리고, 그 0을 Go가 `io.EOF`로 옮깁니다.

규칙: 스트림 반환은 **메서드**여야 하고(생성된 연산이 receiver에게 다시 물어야 하므로),
**파라미터가 없어야 하며**(`Write`/`Read`/`Flush`에 그것을 실을 자리가 없습니다), error
union이나 optional 안이 아니라 **반환 타입 그 자체**여야 합니다. 셋 다 `ZIGO023`입니다.
한 타입이 writer 하나와 reader 하나를 함께 낼 수는 있지만, 같은 방향을 둘 내면 Go 이름이
겹쳐 `ZIGO024`가 됩니다.

`semantic.json`에는 Zig 메서드(`Sink.writer`)가 그대로 기록되고, 연산으로의 확장은 파싱과
lowering 사이에서 일어납니다. `abi-diff`가 비교하는 것은 Zig 표면입니다.

## 취소 (`.cancel`)

긴 native 호출을 Go의 `context.Context`로 끊을 수 있습니다. 함수 메타 `.cancel`이 어느
파라미터가 취소 플래그인지 말하면, 그 파라미터는 Go 시그니처에서 사라지고 대신
`ctx context.Context`가 **첫 인자**로 들어옵니다.

```zig
// Zig — 플래그를 폴링하는 것은 대상 함수의 책임이다.
pub const ReduceError = error{ Empty, Canceled };

pub fn reduce(self: *Hub, rounds: u32, cancel: *const std.atomic.Value(u32)) ReduceError!f64 {
    var round: u32 = 0;
    while (round < rounds) : (round += 1) {
        if (cancel.load(.monotonic) != 0) return error.Canceled;
        // ... 실제 작업 ...
    }
    return total;
}
```

```zig
.{
    .path = "Hub.reduce",
    .params = .{ "rounds", "cancel" },
    .cancel = .{ .param = "cancel" },
}
```

```go
func (h *Hub) Reduce(ctx context.Context, rounds uint32) (float64, error)

ctx, cancel := context.WithTimeout(context.Background(), time.Second)
defer cancel()
total, err := hub.Reduce(ctx, 1 << 30)
errors.Is(err, context.DeadlineExceeded) // true
```

### 취소가 적용되는 시점

Zig 함수는 `*const std.atomic.Value(u32)` 플래그를 주기적으로 읽어야 합니다.
zigo는 native 실행을 강제로 중단하지 않으므로 확인 간격이 곧 취소 지연입니다.
이미 취소된 context를 넘기면 호출 전에 플래그가 설정됩니다. 주소는 호출 동안만 유효하며,
native 코드가 저장하거나 호출이 끝난 뒤 사용하면 안 됩니다.

플래그는 Go가 소유하고 원자적으로 갱신합니다. 메모리 고정과 goroutine 정리의 상세 동작은
[취소 플래그 ABI](generated-abi.md#취소-플래그)를 참고하세요.

함수가 Go callback도 직접 받으면 생성기는 같은 워드의 주소를 callback state에 호출 동안만
연결합니다. callback이 panic하거나 Go `error`를 반환하거나 이미 삭제된 userdata token으로
호출되면 dispatcher가 실패 값을 반환하기 전에 `atomic.StoreUint32(..., 1)`로 플래그를
세웁니다. 따라서 native loop가 callback 반환값을 무시하더라도 다음 폴링 지점에서 멈추며,
panic과 error는 호출이 돌아온 뒤 기존과 같이 Go 호출자에게 다시 전달됩니다. `.cancel`이 없는
함수의 callback state와 dispatcher 출력은 바뀌지 않습니다.

### 취소 오류 이름

`.cancel.canceled`는 취소를 뜻하는 Zig error 이름이며 생략하면
`Canceled`입니다. 예를 들어 라이브러리가 영국식 이름을 쓰면
`.cancel = .{ .param = "cancel", .canceled = "Cancelled" }`로 지정합니다. 대상 함수의
error set에 이 이름이 있어야 합니다(`ZIGO026`). native가 해당 error를 돌려주고
`ctx.Err() != nil`이면 공개 함수는 `ctx.Err()`를 반환합니다 —
`context.Canceled` 또는 `context.DeadlineExceeded`, 호출자의 ctx가 말하는 것 그대로입니다.
ctx가 멀쩡한데 native가 해당 error를 돌려줬다면 그것은 라이브러리의 error이므로 생성된
`ErrCanceled` 또는 `ErrCancelled`가 그대로 나옵니다.

### 잘못된 선언

`.cancel`이 없는 파라미터를 가리키거나, 그 파라미터 타입이
`*const std.atomic.Value(u32)`가 아니거나, error set에 설정한 error 이름이 없거나, 반대로
플래그 파라미터가 있는데 `.cancel`이 그것을 가리키지 않으면 `ZIGO026`으로 거부합니다.

`.cancel`을 추가하거나 제거하면 Go 시그니처의 `ctx`가 생기거나 사라지므로
`abi-diff`는 호환성을 깨뜨리는 변경으로 판정합니다.
