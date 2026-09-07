# 함수 선택, 이름과 패키지

기본 작성 방식은 [`bindings.zig` 선언](bindings.md)을 참고하세요.
아래의 `api`는 `const api = zigo.scope(library);`로 만든 scope입니다.

## 경로와 이름

`api.function("name", options)`는 scope 안의 실제 공개 함수를 검사합니다.
중첩 namespace는 `in()`으로 선택합니다.

```zig
const unicode = api.in("unicode");
const parser = api.in("osc").in("parser");

const declarations = &[_]zigo.Entry{
    unicode.function("codepointWidth", .{}),
    parser.function("parse", .{}).named("parseOsc"),
};
```

`named()` 또는 함수 옵션 `.name`은 Go 이름만 바꿉니다. release·covers·discovery 제외에는
Go 이름 대신 `api.ref("name")`를 사용하므로 이름 변경으로 참조가 끊어지지 않습니다.
타입 참조는 `api.typeRef("T")`, 선언 항목에서 얻는 참조는 `.functionRef()`와 `.typeRef()`입니다.
없는 선언·함수가 아닌 선언·다른 루트의 참조는 컴파일 오류입니다.

공개 자유 함수는 namespace를 이름에 붙이지 않으므로 같은 패키지의 이름 충돌을
`.named()`로 해결해야 합니다. Go 식별자 충돌은 `ZIGO024`, lowering된 C 식별자 충돌은
`ZIGO036`으로 두 선언을 함께 보고합니다. 메서드는 receiver마다 이름 공간이 다릅니다.

## 명시 목록과 자동 발견

기본값은 `.discovery = .explicit`입니다. `declarations`에 없는 함수는 노출하지 않습니다.
고정 목록을 만들 때는 `.names` selector를 씁니다. 적은 순서가 유지되고, 없는 이름·중복 이름·
빈 결과는 컴파일 오류입니다.

```zig
const input = zigo.package(.{
    .path = "input",
    .declarations = api.functions(.{ .names = &.{ "encodeMouse", "encodeKey" } }),
});
```

공개 함수를 접두사로 고르는 selector는 별도 variant입니다. `.names`와 섞을 수 없습니다.

```zig
const queries = api.functions(.{ .public = .{
    .prefix = "query",
    .exclude = &.{"queryDebug"},
} });

const declarations = &[_]zigo.Entry{api.function("version", .{})} ++ queries;
```

`functions()`는 현재 scope의 공개 함수만 선택하고 결과를 실제 선언 항목으로 만듭니다.
제외 이름이 없거나 접두사 밖이면 컴파일 오류입니다. 개별 계약이 필요한 함수는
`function()`으로 따로 선언하세요. 배열 결합은 Zig의 `++`를 사용합니다.

모듈 전체를 자동 노출하려면 Binding의 discovery를 설정합니다.

```zig
pub const bindings = zigo.define(.{
    .root = library,
    .discovery = .{ .public = .{
        .exclude = &.{api.in("Context").ref("debugState")},
    } },
    .declarations = &.{
        api.handle("Context", .{}),
        api.in("Context").function("name", .{ .returns = .{ .semantic = .utf8_string } }),
    },
});
```

`.public`은 등록 타입과 루트의 공개 함수를, `.recursive`는 중첩 namespace까지 발견합니다.
재귀 발견은 다시 내보낸 import와 자기 자신을 가리키는 alias를 건너뜁니다. 명시 선언은
메타데이터를 보강하며 먼저 출력되고, 나머지는 발견 순서로 이어집니다.
자동 발견은 새 `pub fn`을 Go/C API에도 추가하므로 `go-check`로 생성물 변경을 확인하세요.
release 함수는 발견에만 맡기지 말고 `declarations`에 명시해야 합니다.

## 함수 메타데이터

| 옵션 | 역할 |
|---|---|
| `name`, `doc` | 공개 이름·GoDoc override |
| `role` | 자동 추론·자유 함수·메서드·생성자·소멸자 중 하나 |
| `params` | 원본 Zig 인덱스로 선택한 sparse 파라미터 계약 |
| `returns` | lifetime·semantic·Go adapter |
| `covers` | `go-coverage`에서 대신 노출한 것으로 셀 `FunctionRef` 목록 |

### 파라미터 인덱스

`Param.index`는 0부터 시작하는 **원본 Zig 시그니처의 인덱스**입니다. receiver, allocator,
Io, 콜백 userdata도 인덱스에 포함합니다. 필요한 인자만 적으며, 목록 순서는 중요하지 않습니다.
receiver와 주입 인자를 직접 annotate하거나 같은 인덱스를 두 번 적으면 컴파일 오류입니다.

```zig
// fn read(self: *Store, gpa: Allocator, offset: u32, dst: []u8) usize
api.in("Store").function("read", .{
    .params = &.{.{
        .index = 3,
        .go_name = "dst",
        .contract = .{ .buffer = .{ .output = .{ .written = .result } } },
    }},
})
```

위 선언은 `offset` 메타데이터를 반복하지 않습니다. 이름은 `go_name`, source AST,
`pN` fallback 순으로 결정됩니다. 이 이름은 C 파라미터에도 사용되므로 C 키워드와 표준 typedef
이름은 `ZIGO021`로 거부됩니다. Go 키워드는 `type_`처럼 자동으로 피합니다.
함수 인자의 이름으로 선택하는 API는 제공하지 않습니다. Zig comptime reflection에는
파라미터 이름 정보가 없고, source 이름 보강은 그 뒤에 실행되기 때문입니다.

`Param.contract`는 `.value` 기본값 또는 `.buffer`, `.stream`, `.callback`, `.cancel`,
`.flatten` 중 하나입니다. 의미 힌트와 Go adapter는 `semantic`, `go`에 별도로 적습니다.
콜백 **타입**의 `CallbackOptions.params`는 별도 규칙이며, userdata·pointer/length 쌍을
정리한 콜백 인자 순서입니다([콜백 문서](bindings-callbacks.md)).

### 자유 함수를 메서드로 등록하기

```zig
api.function("searchMatchCount", .{ .role = .{ .method = api.typeRef("Search") } })
```

첫 번째 비주입 인자가 등록 handle의 값·포인터 또는 등록 enum 값인지 검사합니다.
여러 함수가 같은 receiver를 공유하면 타입의 멤버로 묶을 수 있습니다.

```zig
api.handle("Screen", .{}).with(.{
    .members = &.{
        api.function("screenSelectAll", .{}).named("selectAll"),
        api.function("screenClearSelection", .{}).named("clear"),
    },
})
```

멤버의 첫 비주입 인자가 부모 타입과 맞으면 receiver로 추론합니다. 접두사는 자동 제거하지
않으며 `.named()`로 최종 이름을 정합니다. 기존 메서드 자동 추론도 유지됩니다. handle이 첫
인자여도 자유 함수로 두려면 `.role = .free`를 지정하세요. 생성자·소멸자는
[수명 문서](bindings-handles.md)의 `.role` 계약으로 지정합니다.

### 등록 enum의 메서드

등록 enum 안의 함수가 그 enum을 첫 비주입 인자로 받으면 Go 값 receiver가 됩니다.
루트 자유 함수는 `.role = .{ .method = api.typeRef("CursorStyle") }`로 지정합니다.
단순히 enum을 인자로 받는 자유 함수는 자동으로 메서드가 되지 않습니다.

값 receiver에는 handle 수명이 없습니다. child constructor, borrowed 결과, iterator,
Io 스트림 계약은 `ZIGO056`으로 거부됩니다. 외부 Go 타입 adapter가 있는 enum에 메서드를
붙일 수도 없습니다. `String`, text 기능의 `MarshalText`·`UnmarshalText`와의 충돌은
`ZIGO024`입니다. `*Enum` receiver는 지원하지 않습니다.

### 설정 struct의 일부 필드만 인자로 받기

```zig
// fn init(gpa: Allocator, options: Options) !Terminal
api.in("Terminal").function("init", .{
    .params = &.{.{
        .index = 1,
        .contract = .{ .flatten = &.{ "cols", "rows", "max_scrollback_bytes" } },
    }},
})
```

선택한 bool·정수·실수·등록 enum과 그 optional 필드만 Go 인자로 펼칩니다. 나머지 필드는
Zig default가 있어야 합니다. nested struct·slice·string 필드는 펼칠 수 없습니다.
빈 선택은 컴파일 오류, 부적합한 필드나 없는 default는 `ZIGO040`입니다. 이름 충돌 시
`<파라미터>_<필드>`로 구분하며, 인덱스는 펼치기 전 struct 인자를 가리킵니다.

### 옵션 교체

```zig
const original = api.function("take", .{
    .name = "takeOwned",
    .returns = .{ .lifetime = .{ .owned = .{ .release = api.ref("release") } } },
});
const reset = original.with(.{ .name = null, .returns = zigo.Returns{} });
```

`.with()`는 주어진 필드만 교체하고 다른 필드는 보존합니다. `null`은 제거이며 중첩 struct와
union은 전체 교체입니다. `reset`의 이름은 source 기본값, lifetime은 `.inferred`가 됩니다.
잘못된 필드 이름과 타입은 호출 위치에서 컴파일 오류입니다.

## Allocator와 Io 주입

```zig
pub const bindings = zigo.define(.{
    .root = library,
    .allocator = .smp_allocator, // .c_allocator, .page_allocator도 지원
    .io = .{ .path = "io" },
    .declarations = &.{api.function("run", .{})},
});
```

`std.mem.Allocator`와 `std.Io` 인자는 공개 시그니처에서 빠지고 shim이 채웁니다.
사용자 값은 `.path`로 라이브러리 루트의 선언을 지정합니다. 자동 기본값은 없으며 설정 없이
해당 인자를 만나면 `ZIGO022`입니다. release 함수에도 같은 주입 규칙이 적용됩니다.
주입 인자를 옮기면 새 원본 인덱스에 맞춰 `Param.index`도 갱신해야 합니다.

## 공개 Go 하위 패키지

```zig
const types = zigo.package(.{
    .path = "types",
    .doc = "Package types contains shared values and handles.",
    .defaults = .{ .strings = .infer_utf8 },
    .declarations = &.{
        api.handle("Ticker", .{}),
        api.function("newTicker", .{ .role = .{ .constructor = .{ .type = api.typeRef("Ticker") } } }),
        api.function("freeTicker", .{ .role = .{ .destructor = api.typeRef("Ticker") } }),
        api.function("liveTickers", .{}),
    },
});
```

`path`는 기본 공개 패키지 아래 상대 경로입니다. 중첩 package의 경로는 부모 경로와 합쳐집니다.
`name`을 생략하면 경로 마지막 요소를 snake_case로 바꿉니다. 선언을 두 번 배정하거나 타입과
소유 메서드를 다른 패키지로 나누면 오류입니다. 명시적으로 넣지 않은 자동 발견 메서드와
생성 접근자도 소유 타입의 패키지를 따릅니다.

이름 pattern·namespace selector·전이 closure는 작성 API에서 제거했습니다. 같은 declaration을
별도 경로 목록으로 관리하지 않고 원하는 package에 직접 넣으세요. Go 타입 이름은 내부
참조의 유일한 키이므로 현재 모든 패키지에서 고유해야 합니다. 함수 이름 충돌은 패키지별로
검사합니다. 패키지 간 import 의존은 DAG여야 하며 순환은 `ZIGO032`입니다.

`defaults`는 부모 값 중 생략한 필드를 상속합니다. package override는 그 아래 명시 함수의
인자·반환 추론에 적용됩니다. 등록 타입의 필드와 자동 발견된 함수에는 Binding의 기본값을
사용합니다. 이 범위를 넘어서는 변경은 개별 `semantic` 힌트로 적으세요.

## Doc 주석

Zig 쪽 doc은 그대로 생성된 Go doc이 됩니다. 본문을 다시 쓰지는 않고 형식만 맞춥니다.

수집 순서는 다음과 같습니다.

1. 선언 바로 앞의 `///` 블록.
2. `///`가 없으면, 선언 바로 위에 빈 줄 없이 붙은 평범한 `//` 줄들. `///`, `////`, `//!`로
   시작하는 줄은 여기에 포함되지 않습니다.
3. 자기 doc이 없고 앞 선언과 빈 줄 없이 이어지는 선언은 그 묶음이 시작할 때의 doc을
   물려받습니다. 빈 줄 하나가 묶음을 끊습니다.

```zig
// The selection flag bits shared by the setters below.
pub fn select(self: *Flags) void { ... }
pub fn selectSilent(self: *Flags) void { ... }  // 위 doc을 공유합니다

pub fn detached(self: *Flags) void { ... }      // 빈 줄이 묶음을 끊습니다
```

출력은 Go 관례대로 항상 식별자로 시작합니다. 본문이 선언 이름으로 시작하거나 소문자
동사로 시작할 때는 한 줄로 이어 붙이고, 그 밖의 대문자로 시작하는 문장은 콜론으로 잇습니다.
`go doc`이 요약으로 보여주는 첫 문장이 식별자로 시작하면서도 작성자의 문장을 그대로
유지합니다.

```go
// Len reports how many events are queued.

// SelectionSilent: The selection flag bits shared by the setters below.
```

doc이 없는 함수는 `// Name calls the Zig function Owner.name.` 한 문장을 받습니다.

패키지 doc은 공개 패키지마다 정확히 한 파일에 생성됩니다. 본문은 `go_package_doc` 빌드
옵션, `bindings.zig` 최상위의 `//!` 블록, 라이브러리 루트 모듈(`source_root`, 기본값은
`bindings.zig` 옆의 `root.zig`) 최상위의 `//!` 블록, 그리고 기본 문장
`// Package {name} provides Go bindings generated by zigo.` 순으로 결정됩니다. 본문이
`Package {name}`으로 시작하면 그대로 쓰고, 소문자 동사로 시작하면 `// Package {name}` 뒤에
이어 붙입니다. 그 밖의 본문(대문자로 시작하는 문장 등)은 기본 문장 뒤에 빈 `//` 줄을 두고
별도 문단으로 이어집니다. godoc은 연속된 주석 줄을 한 문단으로 합치므로, 이름만 적은 줄 뒤에
본문을 붙이면 `Package scalar Scalar arithmetic…`처럼 읽히기 때문입니다. raw 패키지는
지원 API가 아니라는 사실을 밝히는 자체 doc을 받습니다.

`bindings.zig`가 루트 모듈보다 먼저인 이유는, 남이 쓴 라이브러리를 바인딩할 때 루트 모듈의
`//!`가 Zig 사용자를 향해 쓰인 글이기 때문입니다. `bindings.zig`는 바인딩 작성자가 소유한
유일한 파일이므로, 그 머리 주석을 Go 독자가 읽을 문장으로 쓰는 것이 작성자의 몫입니다.
예제 `03-opaque`가 이 자리를 보여 주고, `01-scalar`는 루트 모듈 `//!`가 쓰이는 경우를,
`07-event-queue`는 `go_package_doc` 옵션을 보여 줍니다.
