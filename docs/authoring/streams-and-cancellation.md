# 스트림과 취소

이 가이드는 Zig `std.Io.Reader`·`Writer`를 Go `io.Reader`·`Writer`에 연결하고 장기 실행 호출을
`context.Context`로 취소하는 방법을 설명합니다.

## Go stream을 Zig에 전달하기

Zig 함수가 `*std.Io.Reader` 또는 `*std.Io.Writer`를 받으면 zigo는 Go interface를 받는
adapter를 생성합니다. staging buffer 크기를 지정하려면 parameter contract를 붙입니다.

```zig
Document.func("load", .{ .params = &.{
    zigo.param.stream(1, 4096),
} })
```

생성되는 Go method는 다음과 같은 모양입니다.

```text
func (d *Document) Load(reader io.Reader) (...) 
```

index는 receiver를 포함한 원래 Zig signature 기준입니다. buffer를 `null`로 두면 생성기의
기본 크기를 사용합니다.

## 오류와 짧은 읽기·쓰기

adapter는 Go의 `(n, err)` 계약을 Zig I/O 결과로 바꿉니다.

- `n > 0, err == io.EOF`이면 먼저 읽은 byte를 전달하고 다음 읽기에서 EOF를 관찰합니다.
- 짧은 write와 오류가 함께 오면 실제로 쓴 byte 수를 보존합니다.
- Go I/O error는 callback failure와 같은 경계 규칙으로 public call에 전달됩니다.
- Go method가 panic하면 callback panic처럼 native frame 밖에서 다시 panic합니다.

stream 구현은 반환한 `n`이 전달한 buffer 범위 안인지 지켜야 합니다. 위반은 native 호출을
계속하지 않고 오류로 처리됩니다.

## native 객체가 내주는 stream

handle method가 Zig reader나 writer view를 반환하면 생성 package가 Go stream handle로
감쌀 수 있습니다. 이 view는 원래 객체의 수명에 종속될 수 있으므로 부모 handle을 stream보다
먼저 닫지 마세요.

구체적인 생성 API는 [11-io-streams](../../examples/11-io-streams/README.md)의 `Sink`와
`Source`를 참고하세요.

## 표준 Go I/O interface 구현

기존 handle method를 표준 interface method로 연결할 수 있습니다.

```zig
Document.func("append", .{})
    .use(zigo.features.implements, .{ .kind = .writer }),

Document.func("readInto", .{
    .params = &.{zigo.param.output(1, .result)},
}).use(zigo.features.implements, .{ .kind = .reader }),
```

지원 kind는 다음과 같습니다.

| kind | 생성 method |
|---|---|
| `.writer` | `Write([]byte) (int, error)` |
| `.reader` | `Read([]byte) (int, error)` |
| `.writer_to` | `WriteTo(io.Writer) (int64, error)` |
| `.reader_from` | `ReadFrom(io.Reader) (int64, error)` |

원래 bound method도 유지됩니다. 생성 signature가 해당 interface 계약과 호환되지 않으면
진단으로 거부됩니다.

## `context.Context`로 취소하기

Zig 함수가 취소 flag로 `*const std.atomic.Value(u32)`를 받으면 해당 parameter를 cancel
contract로 바꿉니다.

```zig
api.func("reduce", .{ .params = &.{
    zigo.param.cancel(2, "Cancelled").named("cancel"),
} })
```

생성 Go API는 atomic pointer 대신 `context.Context`를 받습니다. context가 취소되면 flag가
설정되고 Zig 코드는 안전한 지점에서 이를 읽어 지정한 error를 반환해야 합니다.

```go
ctx, cancel := context.WithCancel(context.Background())
defer cancel()

result, err := library.Reduce(ctx, input)
```

`canceled`를 `null`로 두면 기본 Zig error 이름 `Canceled`를 사용합니다. Zig가 해당 error를
반환하고 Go context도 취소 상태라면 public wrapper는 `context.Canceled` 또는
`context.DeadlineExceeded`로 연결합니다.

취소는 native 코드를 강제로 중단하지 않습니다. Zig 구현이 flag를 검사하지 않으면 호출은
계속 실행됩니다. callback이나 stream 호출 중에도 종료 순서와 native 자원 정리를 지키는
cooperative cancellation입니다.

실행 가능한 전체 흐름은 [04-callback](../../examples/04-callback/README.md)과
[11-io-streams](../../examples/11-io-streams/README.md)에 있습니다.
