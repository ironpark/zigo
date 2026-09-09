# 스트림과 취소

이 가이드는 Zig `std.Io.Reader`·`Writer`를 Go `io.Reader`·`Writer`에 연결하고 장기 실행 호출을
`context.Context`로 취소하는 방법을 설명합니다.

선언 조각은 별도 표시가 없으면 `src/bindings.zig`의 `zigo.define` 안에 있는
`.declarations` 목록에 넣습니다. `api`와 공통 import는 [최소 선언](README.md)을 사용합니다.
Go 호출 조각은 함수 본문용이며, 전체 import와 실행 방법은 연결된 예제를 참고하세요.

## Reader에서 Writer로 복사하기

[11-io-streams의 Zig 구현](../../examples/11-io-streams/src/root.zig)은 다음 함수를 사용합니다.

```zig
pub fn tee(r: *std.Io.Reader, w: *std.Io.Writer) LoadError!usize {
    return r.streamRemaining(w) catch |err| switch (err) {
        error.ReadFailed => error.ReadFailed,
        error.WriteFailed => error.ReadFailed,
    };
}
```

`std`는 `@import("std")`, `LoadError`는 `error{ ReadFailed, TooLarge }`입니다.
`api.func("tee", .{})`를 등록하면 `func Tee(r io.Reader, w io.Writer) (uint, error)`가
생성됩니다. [전체 바인딩](../../examples/11-io-streams/src/bindings.zig)의 allocator 설정도
함께 사용하세요.

```go
var output bytes.Buffer
n, err := streams.Tee(strings.NewReader("hello\n"), &output)
if err != nil {
    return err
}
fmt.Printf("%d bytes: %q\n", n, output.String()) // 6 bytes: "hello\n"
```

[전체 Go 예제](../../examples/11-io-streams/go/streams/example_test.go)는 import와 출력까지
검증합니다. Zig는 호출이 끝난 뒤 reader와 writer를 보관하지 않으며, Go 호출자는 호출이
끝날 때까지 두 객체를 사용할 수 있게 유지합니다.

## Go 스트림을 Zig에 전달하기

Zig 함수가 `*std.Io.Reader` 또는 `*std.Io.Writer`를 받으면 zigo는 Go 인터페이스를 받는
어댑터를 생성합니다. staging 버퍼 크기를 지정하려면 매개변수 계약을 붙입니다.

```zig
Document.func("load", .{ .params = &.{
    zigo.param.stream(1, 4096),
} })
```

생성되는 Go 메서드는 다음과 같은 모양입니다.

```text
func (d *Document) Load(reader io.Reader) (...) 
```

index는 receiver를 포함한 원래 Zig 시그니처 기준입니다. 버퍼를 `null`로 두면 생성기의
기본 크기를 사용합니다.

## 오류와 짧은 읽기·쓰기

어댑터는 Go의 `(n, err)` 계약을 Zig I/O 결과로 바꿉니다.

- `n > 0, err == io.EOF`이면 먼저 읽은 바이트를 전달하고 다음 읽기에서 EOF를 관찰합니다.
- 짧은 write와 오류가 함께 오면 실제로 쓴 바이트 수를 보존합니다.
- Go I/O error는 콜백 failure와 같은 경계 규칙으로 공개 호출에 전달됩니다.
- Go 메서드가 panic하면 콜백 panic처럼 네이티브 호출 프레임 밖에서 다시 panic합니다.

스트림 구현은 반환한 `n`이 전달한 버퍼 범위 안인지 지켜야 합니다. 위반은 네이티브 호출을
계속하지 않고 오류로 처리됩니다.

## 네이티브 객체가 내주는 스트림

핸들 메서드가 Zig reader나 writer view를 반환하면 생성 패키지가 Go 스트림 핸들로
감쌀 수 있습니다. 이 view는 원래 객체의 수명에 종속될 수 있으므로 부모 핸들을 스트림보다
먼저 닫지 마세요.

구체적인 생성 API는 [11-io-streams](../../examples/11-io-streams/README.md)의 `Sink`와
`Source`를 참고하세요.

## 표준 Go I/O 인터페이스 구현

기존 핸들 메서드를 표준 인터페이스 메서드로 연결할 수 있습니다.

```zig
Document.func("append", .{})
    .use(zigo.features.implements, .{ .kind = .writer }),

Document.func("readInto", .{
    .params = &.{zigo.param.output(1, .result)},
}).use(zigo.features.implements, .{ .kind = .reader }),
```

지원 kind는 다음과 같습니다.

| kind | 생성 메서드 |
|---|---|
| `.writer` | `Write([]byte) (int, error)` |
| `.reader` | `Read([]byte) (int, error)` |
| `.writer_to` | `WriteTo(io.Writer) (int64, error)` |
| `.reader_from` | `ReadFrom(io.Reader) (int64, error)` |

원래 bound 메서드도 유지됩니다. 생성 시그니처가 해당 인터페이스 계약과 호환되지 않으면
진단으로 거부됩니다.

## `context.Context`로 취소하기

[콜백 예제의 Zig 함수](../../examples/04-callback/src/root.zig)는 취소 플래그를
반복 중에 확인합니다. `Observer`는 앞서 등록한 콜백 타입입니다.

```zig
pub fn applyUntilCancelled(
    limit: u32,
    callback: Observer,
    userdata: usize,
    cancel: *const std.atomic.Value(u32),
) error{Canceled}!u32 {
    var runs: u32 = 0;
    while (runs < limit and cancel.load(.seq_cst) == 0) : (runs += 1) {
        _ = callback(@intCast(runs), userdata);
    }
    if (cancel.load(.seq_cst) != 0) return error.Canceled;
    return runs;
}
```

원래 Zig 함수에서 취소 플래그는 인덱스 `3`입니다. 바인딩에 다음 선언을 추가합니다.

```zig
api.func("applyUntilCancelled", .{ .params = &.{
    zigo.param.callback(1, .{ .go_error = true }),
    zigo.param.cancel(3, null).named("cancel"),
} }),
```

생성 API는 `func ApplyUntilCancelled(ctx context.Context, limit uint32, callback Observer) (uint32, error)`입니다.
Go의 `context.Context`는 첫 인자로 이동하고 `userdata`는 숨겨집니다.

```go
ctx, cancel := context.WithCancel(context.Background())
defer cancel()
_, err := callback.ApplyUntilCancelled(ctx, 100, func(value int32) (int32, error) {
    cancel()
    return value, nil
})
fmt.Println(errors.Is(err, context.Canceled)) // true
```

전체 검증은 [취소 테스트](../../examples/04-callback/go/cancel_test.go)를 참고하세요.

`canceled`를 `null`로 두면 기본 Zig error 이름 `Canceled`를 사용합니다. Zig가 해당 error를
반환하고 Go context도 취소 상태라면 공개 래퍼는 `context.Canceled` 또는
`context.DeadlineExceeded`로 연결합니다.

취소는 네이티브 코드를 강제로 중단하지 않습니다. Zig 구현이 flag를 검사하지 않으면 호출은
계속 실행됩니다. 콜백이나 스트림 호출 중에도 종료 순서와 네이티브 자원 정리를 지키는
cooperative cancellation입니다.

실행 가능한 전체 흐름은 [04-콜백](../../examples/04-callback/README.md)과
[11-io-streams](../../examples/11-io-streams/README.md)에 있습니다.
