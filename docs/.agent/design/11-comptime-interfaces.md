# comptime 인터페이스 패턴의 Go 인터페이스 노출 검토

계획 `110-ownership-and-interface-review`의 두 번째 결과 문서다. 1절은 Zig 코드가 인터페이스를
표현하는 패턴과 reflector(`src/reflect/walk.zig`)가 comptime에 볼 수 있는 것의 조사이고, 2절은
등록 형태와 생성 Go의 설계, 3절은 권고다. 코드 변경은 없다.

## 1. 조사

### 1.1 지금 있는 것

- **generic 타입 instantiation.** `Buffer(comptime T: type) type` 같은 generic 컨테이너는 구체화한
  타입을 고유 `.name`으로 등록한다(`examples/04-callback`의 `FloatBuffer`/`IntBuffer`,
  `examples/05-pipeline`의 `IntBatch`/`FloatBatch`). 두 instantiation은 같은 메서드 이름
  `create`/`push`/`len`/`deinit`을 갖지만 `push`의 파라미터 타입이 다르다. Go에는 서로 무관한
  두 handle 타입이 생기고, 공통 메서드 집합이라는 개념은 없다.
- **generic 함수.** `has_comptime_params`가 참인 함수는 파라미터를 반영하지 않고(`walk.zig`의
  `if (info.is_generic) continue`) ZIGO008로 거부된다. `docs/limitations.md`가 "구체화 전에는
  시그니처가 없다"고 적는다.
- **콜백 타입.** `*const fn (...) callconv(.c)` alias는 `.repr = .callback`으로 이름을 얻고 Go
  함수 타입이 된다. 이는 함수 하나짜리 인터페이스이며 이미 잘 다룬다.
- **tagged union sealed interface.** `public_types.zig`의 `renderPublicUnionVariants`가 union마다
  `type XVariant interface{ isXVariant() }`와 variant별 구체 타입, 마커 메서드를 낸다. 생성기가
  Go 인터페이스를 내는 유일한 자리이고, "닫힌 집합의 구체 타입이 마커 메서드로 한 인터페이스를
  만족한다"는 형태는 이 검토가 원하는 것과 같다.
- **`std.Io.Writer`/`Reader`.** Zig 표준 라이브러리의 vtable 인터페이스다. zigo는 이를 일반
  규칙으로 다루지 않고 파라미터 위치에서만 고정 콜백 시그니처 두 개로 내린다(`io_stream`). vtable
  인터페이스를 "받는" 쪽의 특수 사례이며, "내는" 쪽(Go 인터페이스)이 아니다.

### 1.2 패턴별로 reflector가 볼 수 있는 것

| 패턴 | Zig 예 | comptime에 보이는 것 | 보이지 않는 것 | 원하는 Go |
|---|---|---|---|---|
| A. vtable struct | `Allocator{ ptr, vtable: *const VTable }`, `std.Io.Writer` | struct 필드와 fn pointer 필드의 시그니처. 구현체 목록은 안 보인다 | 어떤 타입이 이 vtable을 채우는지 | 인터페이스 `X`와, 등록한 구현 handle이 그것을 만족한다는 단언 |
| B. `anytype` duck typing | `fn use(sink: anytype) void { sink.write(...) }` | 함수가 generic이라는 사실뿐. 본문이 어떤 메서드를 부르는지는 타입 정보가 아니다 | 메서드 집합, 허용 타입 | 명시적 specialization마다 Go 메서드 하나 |
| C. tag 분기 tagged union | `switch (value) { .integer => ..., }` | union 필드와 payload 타입 전부 | — | 이미 있는 `XVariant` sealed interface |
| D. generic 컨테이너 instantiation | `Batch(i32)`, `Batch(f64)` | 각 instantiation의 메서드 이름과 시그니처. 같은 generic에서 나왔다는 사실은 `@typeName`의 접두사로만 추정 가능 | 원소 타입을 추상화한 공통 시그니처(`push(T)`) | 원소 타입에 독립인 메서드(`Len`, `Close`)만 담은 인터페이스, 또는 Go generic 제약 |

핵심 관찰은 두 가지다. 첫째, reflector가 볼 수 있는 것은 언제나 "구체 타입의 메서드 집합"이고
"인터페이스"는 사용자가 등록으로 이름 붙이는 것이다. 둘째, 원소 타입이 시그니처에 들어가는
메서드(D의 `push`)는 Go 인터페이스 하나로 묶을 수 없다. Go generic 제약(`interface{ Push(T) }`)은
가능하지만 zigo가 지금까지 generic Go 코드를 내지 않았고, 사용자 쪽 이득이 작다.

### 1.3 패턴별 Go 스케치

**A. vtable.** 사용자가 이름과 메서드 집합, 구현 handle을 등록한다.

```zig
.interfaces = .{
    .{ .name = "Sink", .methods = .{ "write", "flush" }, .types = .{ library.FileSink, library.MemorySink } },
},
```

```go
// Sink is implemented by *FileSink and *MemorySink.
type Sink interface {
    Write(data []byte) (int, error)
    Flush() error
    io.Closer
}

var _ Sink = (*FileSink)(nil)
var _ Sink = (*MemorySink)(nil)
```

Go 쪽 시그니처는 각 handle의 메서드에서 이미 생성되는 것을 그대로 쓰고, 생성기는 세 타입의
시그니처가 같은지만 검증한다(`Close`는 생성자 짝이 있는 handle에 항상 있으므로 `io.Closer`를 넣을
수 있다).

**B. `anytype`.** 노출 대상은 specialization이다. 등록은 이미 있는 generic 타입 등록과 같은
정신으로 "구체 타입마다 하나"다.

```zig
.functions = .{
    .{ .path = "root.render", .specialize = .{ .sink = library.FileSink }, .name = "renderToFile" },
    .{ .path = "root.render", .specialize = .{ .sink = library.MemorySink }, .name = "renderToMemory" },
},
```

reflector가 `anytype` 자리에 지정한 타입을 넣어 `@TypeOf(fn)`을 얻을 수는 없다. Zig에서 generic
함수의 instantiation은 호출로만 생기고, 호출 없이 시그니처를 얻는 방법은 없다. 따라서 B는
바인딩 작성자가 Zig 쪽에 wrapper 함수를 쓰는 것(`pub fn renderToFile(sink: *FileSink) ...`)과
같고, zigo가 대신할 수 있는 것은 이름 규칙뿐이다. 실익이 없다.

**C. tagged union.** 이미 있다. 이 검토는 A의 구현을 C의 emitter 옆에 두고 이름 규칙(`XVariant`,
`isXVariant`)과 파일 배치(union 파일)를 따르라는 데 그친다.

**D. generic 컨테이너.** A의 등록으로 원소 독립 메서드만 묶는다.

```zig
.{ .name = "Batch", .methods = .{ "len" }, .types = .{ library.IntBatch, library.FloatBatch } },
```

```go
type Batch interface { Len() (int, error); io.Closer }
```

`push`처럼 원소 타입을 받는 메서드는 인터페이스에 넣을 수 없고, 넣으려 하면 시그니처 불일치
진단이 난다.

## 2. 설계 (phase 3에서 작성)

## 3. 권고 (phase 3에서 작성)
