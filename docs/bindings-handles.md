# 객체 수명과 Go 인터페이스

native 객체를 Go handle로 노출하고, 누가 언제 닫을지 정합니다. 선언의 기본 형태는 [`bindings.zig` 선언](bindings.md)을 참고하세요.

처음에는 [opaque 등록](#opaque-handle)과 [생성자·소멸자 짝](#타입-밖에-선언된-생성자와-소멸자)을
확인하세요. 부모 객체에 의존하면 [borrowed 반환](#receiver가-소유하는-borrowed-handle-반환)과
[자식 생성자](#다른-handle의-메서드인-생성자)를 구분해야 합니다.

## Opaque handle

일반 Zig struct나 상태를 가진 객체는 pointer handle로 등록합니다.

```zig
.types = .{
    .{ .type = mylib.Context, .repr = .@"opaque" },
},
```

caller-owned pointer를 반환하는 생성 함수와 대응 deinitializer가 있으면 공개 Go API에
constructor와 멱등 `Close() error`가 생성됩니다. 보통 반환 error는 항상 nil이며 handle이
`io.Closer`를 만족시키기 위한 것입니다. 단, 아래의 `child_of_receiver` 관계를 가진 부모는
열린 자식이 있으면 `*HandleInUseError`를 반환합니다. 모든 receiver와 handle 인자는 native 호출 전에
nil·closed 상태를 검사합니다. 검사 결과는 항상 반환값으로 전달되며, 오류 반환 자리가
없던 메서드에는 `error` 결과가 추가됩니다.

등록한 opaque struct는 파라미터에서 값으로 받을 수도 있습니다. `fn isBottom(self: Screen)`은
Go에서 pointer receiver와 같은 `func (s *Screen) IsBottom() (..., error)` 메서드가 되고,
`fn compare(expected: bool, other: Screen)`의 `other`는 Go에서 `*Screen`입니다. 두 경우 모두
C 시그니처는 `const Screen *` handle을 받고, shim이 Zig 호출 직전에 `self.*` 또는
`other.*`로 역참조합니다. 따라서 nil·closed·poison 검사와 호출 중 lifecycle guard는 pointer
handle과 같습니다.

역참조는 Zig의 값 전달 규칙에 따라 **복사본**을 만듭니다. callee가 값 파라미터 안의 필드를
바꿔도 Go handle이 가리키는 원본에는 반영되지 않습니다. 반대로 opaque 타입을 값으로 반환하는
것은 `ZIGO003`으로 계속 거부됩니다. 소유할 값을 반환하려면 pointer를 반환하고
`.constructs`를 지정하거나, `.allocator`를 설정해 값 생성자를 boxing하는 경로를 사용하십시오.

`init`/`create`/`new`/`open` 이름을 쓰지 않는 factory도 `.returns = .caller`를 붙이면
같은 owned handle을 돌려줍니다. 이름이 아니라 ownership metadata가 기준이므로,
`clone`이나 `openChild` 같은 메서드도 `newX` helper를 거쳐 cleanup과 retained callback
등록을 그대로 받습니다. 다만 이것은 **그 타입에 이미 짝지어진 생성자와 소멸자가 있을 때**의
이야기입니다(없으면 `ZIGO015`). 짝 자체를 만드는 것은 아래의 `.constructs`/`.destroys`입니다.

```zig
.{
    .path = "EventQueue.clone",
    .params = .{ "observer", "userdata" },
    .param_meta = .{ .observer = .{ .retention = .retained } },
    .returns = .caller,
},
```

### Receiver가 소유하는 borrowed handle 반환

메서드가 receiver 내부의 opaque 객체를 가리키는 `*T`, `?*T`, `!*T`, `!?*T`를 반환하면
`.returns = .borrowed`를 명시할 수 있습니다. `T`는 opaque 타입으로 등록되어야 하며,
반환된 Go 값은 projection 전용 `*TRef`가 아니라 T의 일반 handle인 `*T`입니다.

```zig
pub fn screen(self: *Terminal) ?*Screen { return self.active_screen; }

.{ .path = "Terminal.screen", .returns = .borrowed },
```

optional 반환은 `(*Screen, bool, error)`가 됩니다. false이면 handle은 nil입니다. borrowed
handle은 native 자원을 소유하지 않으므로 `Close()`가 destructor를 호출하지 않고 view만
분리합니다. `Close()`를 생략해도 native 자원을 누수시키지 않습니다. 부모 `Close()`는 진행
중인 view 호출이 있으면 `ErrHandleInUse`를 반환하고, 그렇지 않으면 부모를 닫습니다. 그 뒤
모든 view 호출은 `ErrInvalidHandle`을 감싼 `*HandleError`로 실패합니다. view를 통과한 native
panic은 부모도 poison합니다.

borrowed view가 다시 borrowed view를 반환해도 owner 사슬은 최종 owning handle까지 이어집니다.
그 view를 receiver로 `.child_of_receiver = true` 자식을 만들면 자식 예약과 `Close`의 해제가
모두 그 최종 owner에 적용됩니다. 따라서 열린 자식 하나는 최종 owner의 `Close`에서 정확히
`Children == 1`로 보이고, 자식을 닫은 뒤에는 owner도 닫힙니다. view를 보관하거나 닫는 것만으로는
자식 수가 변하지 않습니다.

`.returns`의 기본 enum 값은 역사적으로 `.borrowed`이므로, 명시 여부는 별도 계약입니다.
`semantic.json`에는 명시한 함수에만 `borrowed_return: true`가 나타납니다. receiver 없는
함수, 등록 opaque pointer가 아닌 반환에 붙인 opt-in은 각각 `ZIGO033`, `ZIGO034`이고,
constructor가 아닌 메서드가 opaque pointer ownership을 생략하면 `ZIGO035`가 `.borrowed`와
`.caller` 중 하나를 고르라고 안내합니다. borrowed와 caller 사이 변경은 `abi-check`에서
breaking입니다.

### 다른 handle의 메서드인 생성자

생성 함수가 새 타입 안에 있을 필요는 없습니다. 주입 파라미터를 건너뛴 첫 handle 파라미터는
평소처럼 receiver가 되고, `.constructs`는 반환값을 어느 타입의 생성자로 소유할지 정합니다.

```zig
pub fn newStream(gpa: std.mem.Allocator, terminal: *Terminal) !*Stream { ... }

.{
    .path = "Terminal.newStream",
    .constructs = "Stream",
    .child_of_receiver = true,
},
.{ .path = "root.freeStream", .destroys = "Stream" },
```

Go에는 `func (t *Terminal) NewStream() (*Stream, error)`가 생깁니다. 호출 중에는 `Terminal`을
다른 메서드와 똑같이 acquire/release하고 native panic이면 그 receiver를 poison합니다. 반환된
`Stream`은 별개의 caller-owned handle이며 cleanup과 멱등 `Close()`를 등록하고 `freeStream`으로
해제됩니다. `.child_of_receiver = true`이면 생성된 `Stream`은 부모 `Terminal` 참조를 보관하고,
열린 자식 수를 부모에 등록합니다. 자식을 닫기 전에 부모를 닫으면 `Close`가
`*HandleInUseError`를 반환하며 `errors.Is(err, ErrHandleInUse)`로 분류할 수 있습니다. 자동으로
자식을 닫지는 않습니다. 자식 `Close`가 native destructor를 끝낸 뒤 카운트를 내리므로, 그 뒤
부모 `Close`를 다시 부르면 정상적으로 해제됩니다. 부모가 native panic으로 poison되면 자식의
호출도 같은 `*NativePanicError`로 거부됩니다.

이 메타는 receiver를 가진 constructor에만 쓸 수 있습니다. 자유 함수나 constructor가 아닌
함수에 붙이면 `ZIGO030`입니다. `semantic.json`은 opt-in한 생성자에만
`child_of_receiver: true`를 기록하고, 두 관계를 섞지 않고 `receiver: "Terminal"`,
`go_owner: "Stream"`으로도 기록합니다. 이 필드의 추가·삭제는 C ABI를 바꾸지 않지만
`abi-diff`가 Go surface의 ABI-compatible 변경으로 보고합니다.

### 타입 밖에 선언된 생성자와 소멸자

이름 규칙과 `.returns = .caller`는 모두 **타입 안에 선언된** 짝을 전제합니다. 남의
라이브러리처럼 선언을 더할 수 없는 코드에서는 생성자와 소멸자가 타입 옆의 자유 함수로
있기 마련이고, 그때는 어느 타입의 짝인지를 직접 적습니다.

```zig
// mylib: 타입 안에는 아무것도 없고, 옆에 free 함수만 있는 형태
pub const Ticker = struct { interval: u32 };
pub fn newTicker(interval: u32) !*Ticker { ... }
pub fn freeTicker(ticker: *Ticker) void { ... }

// bindings.zig
.{ .path = "root.newTicker", .params = .{"interval"}, .constructs = "Ticker" },
.{ .path = "root.freeTicker", .destroys = "Ticker" },
```

Go에는 `NewTicker(interval uint32) (*Ticker, error)`와 `(*Ticker).Close()`가 생기고,
shim은 선언이 있는 자리 그대로 `target.newTicker(...)`를 부릅니다. 즉 Go에서의 소속과
Zig에서의 호출 경로는 서로 다른 축이며, `semantic.json`은 전자를 `go_owner`, 후자를
`zig_path`로 적습니다(둘 다 기본값과 다를 때만 나타납니다).

생성자 함수에도 `.name`을 지정할 수 있습니다. 예를 들어
`.constructs = "AudioBuffer", .name = "extractAudio"`는 기본 이름
`NewAudioBuffer` 대신 `ExtractAudio`(그리고 opt-in 시 `MustExtractAudio`)를 생성합니다.
`.name`을 생략한 생성자는 이전과 같이 항상 `New<Type>`을 사용합니다.

- `.constructs`와 `.destroys`는 `.types`에 등록된 opaque 타입 이름을 받습니다.
- `.constructs`를 붙인 함수는 그 타입의 pointer(또는 `!*T`)를 반환해야 하고,
  `.destroys`를 붙인 함수는 그 타입의 pointer를 첫 파라미터로 받고 아무것도 반환하지
  않아야 합니다. 주입 파라미터(`std.mem.Allocator`, `std.Io`)는 세지 않으므로
  `fn freeTerminal(gpa: Allocator, self: *Terminal) void`도 됩니다. 이는 메서드 판정
  일반에 적용되는 규칙입니다: 주입 파라미터를 건너뛴 첫 파라미터가 handle이면 receiver이고,
  shim은 `self`를 Zig가 선언한 자리에 넣어 부릅니다.
- 한 타입에 대해 둘 다 있어야 짝이 됩니다. 한쪽만 있거나, 같은 타입에 둘이 겹치거나,
  시그니처가 위 조건에 맞지 않으면 `ZIGO028`입니다.
- 메타를 적지 않은 함수에는 `init`/`create`/`new`/`open` + `deinit`/`destroy`/`close`
  이름 규칙이 그대로 fallback으로 남습니다. 메타가 있으면 이름은 보지 않습니다.

`.allocator`가 설정되어 있으면 값으로 반환하는 생성자를 상자에 담는 규칙도 `.constructs`를
따릅니다 — 이름이 `init`이 아니어도 됩니다.

감쌀 handle이 없는 `.returns = .caller`는 `ZIGO015`로 거부됩니다(slice 반환은
[별도의 해제 규칙](bindings-buffers.md#호출자-소유-slice-반환)을 따릅니다). 반환 타입이 opaque
pointer가 아니거나, 그 타입에 constructor와 deinitializer가 등록되어 있지 않은
경우입니다.

## 값으로 반환하는 `init`

`pub fn init(gpa: Allocator, options: Options) !Terminal`처럼 값을 반환하는 생성자는 C로
표현할 수 없습니다. `.allocator`가 설정되어 있고 반환 타입이 `.repr = .@"opaque"`로 등록된
struct라면, zigo가 그 값을 상자에 담습니다: shim이 `alloc.create(T)`로 저장 공간을 만들고
`T.init(...)`의 결과를 거기에 넣어 포인터를 돌려주며, 짝이 되는 `deinit` 래퍼가 Zig
`deinit`을 부른 뒤 `alloc.destroy`까지 합니다. Go에서는 다른 생성자와 똑같이
`NewTerminal(...) (*Terminal, error)`와 `Close()`입니다.

`Options`가 C layout이 아니거나 slice 같은 내부 설정을 담아 struct 자체를 Go에 노출할 수
없다면 [`param_meta.options.flatten`](bindings-functions.md#함수-메타데이터)을 함께 사용하세요. Go 생성자는 선택한 field를
개별 인자로 받고, shim은 선택한 field만 적은 `Options{ .cols = ..., ... }`를 만듭니다. 따라서
나머지는 Zig 선언의 default로 채워집니다. 선택 field를 추가하면 C와 Go 함수 시그니처가
늘어나므로 `abi-diff`는 breaking으로 보고합니다.

상자에 담는 데 필요한 할당은 zigo 자신의 것이므로, 실패는 Zig 함수가 선언하지 않은 error를
지어내는 대신 panic으로 보고합니다 — 생성자는 언제나 `error`를 반환하므로 Go에는
`*NativePanicError`로 도착합니다.

`.allocator`가 없으면 이 변환은 일어나지 않고, 반환 struct는 지금까지처럼 값 struct로
판정되어 그 자리에서 거부됩니다. 저장 공간의 수명을 정하는 것은 바인딩 작성자의 몫입니다.

## 필드 접근자

`.repr = .@"opaque"`로 등록한 struct에는 `.fields`를 붙여 Zig 함수를 따로 작성하지 않고
Go 메서드를 만들 수 있습니다.

```zig
.types = .{
    .{ .type = mylib.Terminal, .repr = .@"opaque", .fields = .{
        .{ .path = "cols" },
        .{ .path = "screen.cursor.x", .name = "cursorX" },
        .{ .path = "screen.cursor.style", .name = "cursorStyle", .set = true,
           .doc = "CursorStyle reports the current cursor style." },
    } },
    .{ .type = mylib.CursorStyle, .repr = .enumeration },
},
```

각 항목은 getter를 만들고, `.set = true`이면 같은 타입을 받는 setter도 만듭니다. 마지막
segment가 기본 이름이므로 위 선언은 `Cols()`, `CursorX()`, `CursorStyle()`,
`SetCursorStyle(v)`가 됩니다. `.name`은 getter stem을 바꾸며 setter에는 `Set`이 붙습니다.
생성된 Go 문서에는 원래 Zig 필드 경로가 항상 남고, `.doc`이 있으면 그 설명도 함께 씁니다.

경로의 각 중간 segment는 struct 값이거나 non-optional single pointer가 가리키는 struct여야
합니다. 마지막 필드는 bool, 정수, 실수 또는 `.enumeration`으로 등록한 enum만 지원합니다.
알 수 없는 경로, optional·slice·union 같은 중간 값, 지원하지 않는 leaf 타입은 `ZIGO037`로
거부합니다. getter/setter는 reflection에서 일반 메서드로 합성되므로 cgo와 purego에 같은 Go
API를 만들고 `abi-check` 및 `abi-diff`에도 일반 함수처럼 나타납니다. 접근자를 추가하는 것은
compatible append이며, 함수와 이름이 겹치면 기존 `ZIGO024`/`ZIGO036` 진단을 사용합니다.

## 호출과 Close의 수명 규칙

| 상황 | 생성된 API의 동작 |
|---|---|
| nil·닫힌 handle 호출 | native에 진입하기 전에 `*HandleError` 반환 |
| 일반 handle의 `Close` | 닫힘으로 표시하고, 진행 중 호출이 모두 끝나면 해제 |
| 열린 자식이 있는 부모의 `Close` | `ErrHandleInUse`; 자식을 먼저 닫아야 함 |
| borrowed view 호출 중 부모의 `Close` | `ErrHandleInUse`; 호출 후 다시 시도 |
| Zig panic에 참여한 handle | poison 상태로 바뀌고 재사용 불가 |
| GC cleanup | 정리 안전망이며 실행 시점은 보장하지 않음 |

진행 중 호출이 native 메모리를 붙잡고 있어도 객체의 모든 동작을 직렬화하지는 않습니다.
원래 Zig 타입이 동시 호출을 허용하지 않으면 Go 호출자가 잠금을 제공해야 합니다.

retained 콜백과 포인터는 소유 객체가 닫힐 때까지 유효해야 합니다. 콜백 교체와 native 자원
해제의 내부 순서는 [생성 runtime](generated-runtime.md#handle의-수명-관리)에 있습니다.
Zig panic 후에는 native 소멸자도 실행하지 않으므로 [panic 처리 조건](limitations.md#오류와-panic)을
확인하고 해당 작업을 중단하세요.

## 인터페이스

등록한 opaque handle 여러 개가 같은 메서드를 같은 Go 시그니처로 제공하면, `.interfaces`로
그 메서드 집합에 이름을 붙여 하나의 Go 인터페이스로 내보낼 수 있습니다. 같은 generic에서
나온 구체 타입(`Batch(i32)`, `Batch(f64)`)이나 같은 vtable을 채우는 구현체가 전형적인
경우입니다.

```zig
pub const bindings = zigo.define(.{
    .root = library,
    .types = .{
        .{ .name = "IntBatch", .type = library.IntBatch, .repr = .@"opaque" },
        .{ .name = "FloatBatch", .type = library.FloatBatch, .repr = .@"opaque" },
    },
    .interfaces = .{
        .{
            .name = "Batch",                                   // Go 인터페이스 이름
            .methods = .{"len"},                               // Zig 메서드 이름
            .types = .{ library.IntBatch, library.FloatBatch }, // 등록된 opaque 타입
            .closer = true,                                    // 기본값. io.Closer 포함
            .doc = "Batch is any staged batch, whatever its element type.",
        },
    },
    ...
});
```

- `.types`의 각 항목은 `.repr = .@"opaque"`로 등록된 타입이어야 하며, `.methods`는 그 타입
  모두가 receiver 메서드로 노출하는 Zig 선언 이름입니다. 소멸자는 메서드로 치지 않습니다.
- `.closer`는 모든 타입이 생성자 짝을 가질 때만 참일 수 있습니다. 생성자 짝이 없는 타입을
  묶으려면 `.closer = false`를 적습니다.
- 하위 패키지를 쓰면 인터페이스는 첫 타입의 패키지에 들어가고, 모든 타입이 같은 패키지에
  있어야 합니다.

생성기는 각 메서드의 공개 Go 시그니처를 타입마다 렌더링해 비교합니다. 파라미터 이름은
비교하지 않지만 타입, 반환값, `Must` 변형 여부는 같아야 합니다. 원소 타입이 시그니처에
들어가는 메서드(`push(value: T)`)는 묶을 수 없고 `ZIGO049`로 거부됩니다. 이름 충돌은
등록 타입과 같은 규칙으로 `ZIGO024`입니다.

생성물은 `<package>_interfaces_gen.go` 한 파일입니다.

```go
// Batch is any staged batch, whatever its element type.
// Batch is implemented by *IntBatch and *FloatBatch.
type Batch interface {
	// Len calls the Zig method len of the implementing handle.
	Len() (uint, error)
	MustLen() uint
	io.Closer
}

var _ Batch = (*IntBatch)(nil)
var _ Batch = (*FloatBatch)(nil)
```

메서드 doc은 첫 타입 메서드의 doc을 씁니다. 단언 두 줄은 시그니처 비교가 놓친 것을
`go build`가 잡게 하는 안전망입니다. `abi-diff`는 인터페이스 추가를 호환으로, 제거와 메서드
집합·구현 타입·`io.Closer` 변경을 breaking으로 보고합니다.

`anytype`을 받는 Zig 함수는 인터페이스로 노출하지 않습니다. instantiation은 호출로만 생기므로
구체 타입별 wrapper 함수를 Zig에 쓰고 그것을 등록하세요.
