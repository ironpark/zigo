# comptime 인터페이스 패턴의 Go 인터페이스 노출 검토

> 과거 검토 기록입니다. 명시 등록 인터페이스는 이후 구현되었습니다. 아래 제안을 현재의
> 미구현 목록으로 해석하지 마세요. 사용법은 [객체 수명](../../bindings-handles.md),
> 현재 검증은 [interfaces.zig](../../../src/gen/validate/interfaces.zig)를 참고하세요.

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

## 2. 설계

### 2.1 범위

구현 가치가 있는 것은 패턴 A와 D를 함께 덮는 **명시 등록 인터페이스** 하나다. 등록 opaque handle
중 사용자가 고른 집합이 사용자가 고른 메서드 집합을 같은 Go 시그니처로 제공한다는 사실을
검증하고, 그 사실을 Go 인터페이스와 컴파일 타임 단언으로 낸다. 패턴 B(`anytype`)는 1.3의 이유로
노출하지 않고, 문서에 "Zig wrapper를 쓰라"고 적는다. 패턴 C는 이미 있다.

### 2.2 등록 형태

```zig
pub const bindings = zigo.define(.{
    .root = library,
    .types = .{ ... },
    .interfaces = .{
        .{
            .name = "Sink",                       // Go 인터페이스 이름. 필수
            .methods = .{ "write", "flush" },     // Zig 선언 이름. 각 타입에서 같은 이름을 찾는다
            .types = .{ library.FileSink, library.MemorySink },  // 등록된 opaque 타입
            .closer = true,                       // 기본값 true: io.Closer 포함
            .doc = "Sink receives rendered output.",
        },
    },
});
```

- `.types`의 각 항목은 `.repr = .@"opaque"`로 등록된 타입이어야 한다. borrowed view(`*TRef`)나
  value struct는 메서드 집합이 다르므로 받지 않는다.
- `.methods`는 Zig 선언 이름이다. 함수 메타데이터 `.name`으로 Go 이름을 바꾼 메서드는 바뀐 Go
  이름으로 인터페이스에 들어간다. 즉 매칭은 Zig 이름, 시그니처 비교는 Go 표면에서 한다.
- `.closer`는 모든 타입이 생성자 짝을 가질 때만 참일 수 있다.

### 2.3 IR

`Semantic`에 `interfaces: ?[]const Interface = null`을 더한다.

```zig
pub const Interface = struct {
    name: []const u8,
    doc: ?[]const u8 = null,
    /// Zig 선언 이름 순서대로. 인터페이스 메서드 순서가 된다.
    methods: []const []const u8,
    /// 등록 타입 이름. `types[].name`을 가리킨다.
    types: []const []const u8,
    closer: bool = true,
    package: ?[]const u8 = null,
};
```

`Semantic.parse`는 모르는 필드를 거부하므로 이 필드가 있는 `semantic.json`은 옛 zigo에서 파싱에
실패한다. `emit_null_optional_fields = false` 덕에 인터페이스를 등록하지 않은 바인딩의 파일은
바이트 단위로 같다. 따라서 이 기능은 minor 버전(`0.9.0`)이고, `ir_version`은 올리지 않는다.
lowering은 `abi.Program.interfaces`에 메서드별 `*const AbiFn`을 해석해 넣는다.

### 2.4 검증 (새 진단 ZIGO049)

순서대로, 첫 위반이 진단이 된다.

1. 이름이 유효한 Go 식별자이고 등록 타입·함수·다른 인터페이스와 충돌하지 않는다(기존 ZIGO024
   경로에 인터페이스 이름을 합류시킨다).
2. `.types`의 각 이름이 등록된 opaque 타입이다. 아니면 ZIGO049 "interface lists a type that is not an
   opaque handle".
3. 각 타입이 `.methods`의 각 이름을 노출 함수로 가진다(receiver가 그 타입인 함수). 없으면 ZIGO049
   "type `X` has no exposed method `m`".
4. 같은 메서드의 Go 시그니처가 모든 타입에서 같다. 비교는 lowering 뒤 emit의 시그니처 writer로
   각 메서드의 Go 시그니처를 문자열로 렌더링해 비교한다. receiver 이름은 제외한다. 다르면 ZIGO049
   "method `m` has signature `A` on `X` but `B` on `Y`". `Must` 변형 여부(`must_variant`)가 다른 것도
   불일치다.
5. `.closer = true`인데 생성자 짝이 없는 타입이 있으면 ZIGO049.
6. 하위 패키지를 쓰는 문서에서는 인터페이스와 모든 타입이 같은 패키지에 있어야 한다.

4번을 텍스트 비교로 하는 이유는 계획 109가 import와 helper 판정에 쓴 것과 같다. 시그니처를
구조적으로 비교하는 두 번째 규칙을 두면 emit과 어긋날 수 있다.

### 2.5 생성 Go

인터페이스마다 다음을 낸다. 배치는 `<pkg>_interfaces_gen.go` 한 파일이며, tagged union의 sealed
interface가 union 파일에 있는 것과 같은 정신으로 "인터페이스 표면은 자기 파일"에 둔다.

```go
// Sink receives rendered output.
// Sink is implemented by *FileSink and *MemorySink.
type Sink interface {
	// Write ...(FileSink.Write의 doc을 그대로)
	Write(data []byte) (int, error)
	Flush() error
	io.Closer
}

var _ Sink = (*FileSink)(nil)
var _ Sink = (*MemorySink)(nil)
```

- 메서드 doc은 `.types`의 첫 타입 메서드 doc을 쓴다. 인터페이스가 다른 doc을 원하면 등록 `.doc`에
  적는다.
- `Must` 변형이 켜져 있으면 `MustWrite`도 인터페이스에 포함한다. 4번 검증이 이를 보장한다.
- 단언 두 줄은 검증이 놓친 것을 `go build`가 잡게 하는 안전망이다.
- cgo와 purego의 차이는 없다. 인터페이스는 공개 패키지 표면만 건드린다.

### 2.6 abi-diff와 커버리지

- 인터페이스 추가는 compatible, 제거와 메서드 제거는 breaking, 메서드 추가는 Go 인터페이스에
  메서드가 늘면 사용자 구현체(있다면)가 깨지므로 breaking으로 본다. 다만 생성 인터페이스는 등록
  handle만 구현하도록 의도되었으므로, 문서에 "사용자가 직접 구현하지 말 것"을 적고 메서드 추가를
  compatible로 낮추는 선택지도 있다. 초기값은 보수적으로 breaking이다.
- `go-coverage`는 영향이 없다. 인터페이스는 새 Zig 선언을 바인딩하지 않는다.

### 2.7 하지 않는 것

- Go generic 제약(`interface{ Push(T) }`)은 내지 않는다. 사용자 코드에서 `Batch[T]`처럼 쓸 자리가
  없고, zigo가 generic Go를 내기 시작하면 gofmt 버전과 Go 최소 버전 계약이 늘어난다.
- Zig vtable struct 자체를 반영해 메서드 집합을 자동으로 뽑지 않는다. vtable의 fn pointer 필드는
  구현 handle의 메서드와 이름이 같다는 보장이 없고, 등록 한 줄이 그 매핑을 더 분명히 말한다.
- 인터페이스를 파라미터 타입으로 받는 함수(Go 쪽에서 `func Use(s Sink)`)는 내지 않는다. C ABI에는
  구체 포인터만 있으므로 Go 쪽에서 type switch로 구체 타입을 골라 다른 심볼을 불러야 하고, 이는
  B의 specialization 문제로 돌아간다.

## 3. 권고

**부분 구현을 권한다. 명시 등록 인터페이스(2.2)만, `anytype`은 제외.** 이득은 분명하다.
같은 generic에서 나온 handle들과 vtable 구현체들을 Go 쪽에서 하나의 타입으로 다룰 수 있고,
검증이 "메서드 집합이 같다"는 사실을 릴리즈마다 지켜 준다. 비용은 새 semantic 필드 하나, 진단
하나, emitter 하나이며 기존 생성물은 바뀌지 않는다.

우선순위는 소유권 레코드(계획 `10-ownership-model.md`) 뒤다. 인터페이스 메서드 시그니처 비교는
lowered 함수 위에서 하므로, 소유권이 `AbiFn.ownership` 하나로 정리된 뒤가 비교 규칙이 단순하다.

### 후속 계획 초안 (4 phase)

1. `Semantic.interfaces`와 reflector 등록(`zigo.define`의 `.interfaces`), `semantic.json` 골든 추가.
   생성기는 아직 읽지 않는다.
2. 검증 ZIGO049(2.4의 1~6)와 진단 스냅샷 테스트.
3. lowering의 `Program.interfaces`와 `<pkg>_interfaces_gen.go` emitter, golden case
   `interfaces`/`interfaces_purego`, 예제 `05-pipeline`에 `Batch` 인터페이스 적용.
4. `abi-diff` 규칙, `docs/bindings.md` 절, CHANGELOG(`0.9.0` Added).
