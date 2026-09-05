# 함수 선택, 이름과 패키지

노출할 함수를 고른 뒤 Go 이름과 패키지를 정하는 문서입니다. 선언의 기본 형태는 [`bindings.zig` 선언](bindings.md)을 참고하세요.

[자동 발견](#명시-목록과-자동-발견) → [함수 메타데이터](#함수-메타데이터) →
[하위 패키지](#공개-go-하위-패키지) 순서로 필요한 설정만 적용하세요.

## 경로와 이름

경로는 임의 깊이의 namespace struct를 따라갑니다. 루트에 `pub fn` 없이 API를 struct로
묶는 module은 Zig 호출자가 쓰는 것과 같은 철자를 그대로 씁니다.

```zig
.functions = .{
    .{ .path = "root.unicode.codepointWidth", .params = .{"cp"} },
    .{ .path = "root.osc.parser.parse" },
},
```

마지막 segment 앞의 모든 segment는 공개 container 타입(struct, union, enum, opaque)이어야
합니다. 첫 segment만 `root` 또는 등록된 `.types` 항목 이름으로 해석되고, 나머지는 그 안의
공개 선언입니다. namespace는 `semantic.json`에 점으로 이어진 경로(`"unicode"`,
`"osc.parser"`)로 기록되며 여기서 나머지 이름이 모두 파생됩니다.

| 경로 | C 심볼 | raw Go | ABI identity |
|---|---|---|---|
| `root.version` | `zg_version` | `Version` | `version` |
| `Context.create` | `zg_context_create` | `ContextCreate` | `Context.create` |
| `root.unicode.codepointWidth` | `zg_unicode_codepoint_width` | `UnicodeCodepointWidth` | `unicode.codepointWidth` |
| `root.osc.parser.parse` | `zg_osc_parser_parse` | `OscParserParse` | `osc.parser.parse` |

공개 Go 함수 이름은 namespace를 붙이지 않고 함수 이름만 씁니다(`CodepointWidth`). 서로 다른
namespace에 같은 이름의 함수가 있다면 `.name`으로 하나를 바꿉니다.

### 공개 Go 이름 충돌

receiver가 없는 함수(namespace 함수와 최상위 함수)는 모두 같은 이름 공간을 나눠 쓰고, 등록된
타입 이름도 여기 포함됩니다. 메서드는 receiver별로 별도의 이름 공간을 가지므로 다른 receiver의
같은 메서드 이름은 충돌이 아닙니다(`Counter.reset`과 `Timer.reset`은 둘 다 `Reset` 메서드가
됩니다). 같은 enum의 두 tag가 PascalCase로 변환했을 때 같은 이름이 되는 경우도 같은 검사를
받습니다.

생성기는 이런 충돌을 생성 시점에 `ZIGO024`로 거부하며, 메시지에 충돌하는 두 Zig 경로를 모두
적습니다. 함수는 `.name`으로, 타입은 `.types`의 `.name`으로 한쪽 이름을 바꿔 충돌을 없앱니다.

C 헤더의 이름 공간도 별도로 검사합니다. 함수 심볼뿐 아니라 handle·enum·`extern struct`·
snapshot typedef, enum 상수, tagged-union projection, last-error 함수까지 실제 lowering된
식별자를 한 공간에 모읍니다. 예를 들어 타입 `SearchSelect`와 `Search.select`가 둘 다
`zg_search_select`가 되면 `ZIGO036`이 두 선언을 함께 지목합니다. 한 선언의 `.name`을
바꾸거나 바인딩 `.prefix`를 달리해 해결합니다. cgo와 purego에서 실제로 내보내는 이름을 각각
검사하므로 callback dispatcher suffix도 포함됩니다.

## 명시 목록과 자동 발견

안정적인 공개 API가 중요하다면 `functions`에 함수를 명시하세요. 목록에 없는 함수는 노출되지
않으므로 Zig의 새 `pub fn`이 의도치 않게 Go ABI에 들어오지 않습니다.

Zig 공개 API 전체가 바인딩 API인 큰 module은 자동 발견을 선택할 수 있습니다.

```zig
pub const bindings = zigo.define(.{
    .root = mylib,
    .discover = .public,
    .types = .{
        .{ .type = mylib.Context, .repr = .@"opaque" },
    },
    .functions = .{
        // 자동 발견된 함수에 메타데이터를 보강합니다.
        .{ .path = "Context.name", .semantic = .utf8_string },
    },
    .exclude = .{"Context.debugState"},
});
```

`.discover = .public`은 한 단계만 봅니다. namespace struct 안까지 내려가려면
`.discover = .recursive`를 씁니다. 기본값을 바꾸지 않는 이유는 기존 바인딩의 노출 표면이
조용히 넓어지지 않게 하기 위해서입니다. 재귀 발견은 container 안에 **작성된** 선언만
따라가므로 `@This()` alias나 다시 내보낸 import를 건너뜁니다. 중첩 경로도 `exclude`에
같은 철자로 적습니다(`"root.osc.internalHelper"`).

자동 발견은 등록한 타입의 공개 함수, 이어서 `root` module의 공개 함수를 찾습니다.
`functions`는 발견 대상을 제한하지 않고 메타데이터를 붙이며, `exclude`가 제외 대상을
지정합니다. 존재하지 않거나 중복된 경로, `functions`와 `exclude`의 충돌은 compile
error입니다.

자동 발견에서는 새 `pub fn`이 C/Go API에도 추가됩니다. 생성물 `go-check`와 독립 배포
계약이 있다면 `abi-check`를 함께 사용하세요.

## 함수 메타데이터

| 필드 | 역할 |
|---|---|
| `path` | `root.<name>` 또는 `<Type>.<name>` 선언 경로 |
| `covers` | 이 함수가 대신 노출하는 상류 선언 경로 하나 또는 목록 (`go-coverage` 전용) |
| `name` | 공개 Go 함수 이름 override |
| `receiver` | 자유 함수를 method로 붙일 등록 opaque 타입 이름 |
| `strip_prefix` | 함수 group에서 기본 Go 이름을 만들 때 제거할 공통 접두사 |
| `functions` | `receiver`/`strip_prefix`를 공유하는 함수 경로 또는 메타데이터 항목 목록 |
| `params` | Go가 넘기는 파라미터의 이름 목록 |
| `constructs` | 이 함수가 만드는 opaque 타입 이름 |
| `destroys` | 이 함수가 없애는 opaque 타입 이름 |
| `child_of_receiver` | 생성된 handle이 receiver보다 먼저 닫혀야 하는지 여부 |
| `param_meta` | 문자열·버퍼·콜백 등 파라미터별 추가 계약 |
| `semantic` | 반환값 의미. 예: `.utf8_string` |
| `returns` | 반환 pointer의 ownership |
| `release` | caller-owned 반환 버퍼를 해제할 함수 경로 |

`param_meta`에서는 필요한 계약만 지정합니다. 문자열·`direction`·`written`은
[버퍼 가이드](bindings-buffers.md), `retention`·`go_error`·`on_callback_failure`와
스레드 계약은 [콜백 가이드](bindings-callbacks.md), `buffer`는
[스트림 가이드](bindings-streams.md)를 참고하세요. `flatten`은 아래에서 설명합니다.

문자열 의미, 반환 pointer ownership, retained pointer와 callback 수명은 타입만으로 결정할 수
없으므로 명시해야 합니다.

### 자유 함수를 메서드로 등록하기

등록 타입을 선언한 외부 모듈을 고칠 수 없을 때는 자유 함수의 첫 번째 비주입
파라미터를 receiver로 지정할 수 있습니다. `.receiver = "Screen"`이면
`std.mem.Allocator`나 `std.Io` 뒤의 첫 파라미터가 `*Screen` 또는 `*const Screen`인지
reflection이 확인하고, 이후 단계는 타입 안에 선언된 method와 똑같이 처리합니다.

```zig
.functions = .{
    .{ .path = "root.searchMatchCount", .receiver = "Search" },
    .{
        .receiver = "Screen",
        .strip_prefix = "screen",
        .functions = .{
            "root.screenSelectAll",
            .{ .path = "root.screenClearSelection", .name = "clear" },
        },
    },
},
```

group은 Zig 함수 이름에서 `strip_prefix`를 제거하고 남은 첫 글자를 소문자로 바꾼 뒤 기존
Go casing 규칙을 적용합니다(`screenSelectAll` → `selectAll` → `SelectAll`). nested 항목의
`.name`은 이 기본값을 덮어씁니다. group 자체에는 `params`나 `param_meta`를 둘 수 없고 각
nested 항목에 둡니다. receiver 타입이나 첫 파라미터가 맞지 않거나 함수 이름에 접두사가
없으면 `ZIGO038`입니다.

```zig
.{
    .path = "Context.create",
    .params = .{ "name", "callback", "userdata" },
    .param_meta = .{
        .name = .{ .semantic = .utf8_string },
        .callback = .{ .retention = .retained },
    },
}
```

`params`에는 receiver와 주입 파라미터를 제외한 이름을 적습니다. receiver(`self`)는
생성된 Go 메서드의 수신자가 되고, 주입 파라미터(`std.mem.Allocator`, `std.Io`)는
공개 인자에서 빠집니다. `fn freeString(gpa: Allocator, str: []const u8) void`의 `params`는
`.{"str"}` 하나입니다. 개수가 맞지 않으면 reflection 단계에서 `ZIGO027`로 거부됩니다.

`param_meta`의 field는 파라미터 이름과 일치해야 합니다. 해당 이름을 reflection 단계에서
확실히 식별하려면 같은 항목에 `params`도 적으세요. 이름은 명시적 `params`, 대상 source AST,
`p0` fallback 순으로 결정됩니다.

### 설정 struct의 일부 필드만 인자로 받기

일반 struct 파라미터에서 일부 scalar 필드만 Go 인자로 받고 싶으면 `flatten`에 필드 이름을
순서대로 적습니다. `params`는 flatten 뒤의 인자 수가 아니라 원래 struct 파라미터 하나를
셉니다. field 이름이 다른 파라미터나 다른 flattened field와 겹치지 않으면 그대로 Go 이름이
되고, 겹치면 `<파라미터>_<field>`가 됩니다.

```zig
.{
    .path = "Terminal.init",
    .params = .{"options"},
    .param_meta = .{
        .options = .{ .flatten = .{ "cols", "rows", "max_scrollback_bytes" } },
    },
}
```

허용되는 leaf는 bool, 정수, 실수, 등록 enum과 그 optional입니다. optional scalar는 일반
optional 파라미터처럼 Go에서 `*T`이며 `nil`이 Zig의 `null`입니다. nested struct, slice,
string은 flatten할 수 없습니다. 목록에 없는 field는 모두 Zig default를 가져야 하며, 그렇지
않으면 reflection이 그 field 이름과 함께 `ZIGO040`을 냅니다. 목록에 없는 field는 default만
확인하고 타입은 걷지 않으므로, C로 표현할 수 없는 nested struct나 optional struct가 섞인
options struct도 선택한 field만으로 바인딩됩니다. 이 기능은 생성자뿐 아니라 모든 함수
파라미터에 적용됩니다.

## Allocator와 Io 주입

`std.mem.Allocator`와 `std.Io`는 C로 표현할 수 없습니다. 바인딩이 값을 한 번 정하면
그 파라미터는 C와 Go 시그니처에서 빠지고 shim이 채웁니다.

```zig
pub const bindings = zigo.define(.{
    .root = library,
    .allocator = .smp_allocator, // 또는 .c_allocator, .page_allocator, 또는 "gpa" 같은 선언 경로
    .io = "io", // 선언 경로만 받습니다. std에는 기본 Io가 없습니다
    // ...
});
```

`fn open(gpa: Allocator, name: []const u8) !*Store`는 C에서
`int32_t zg_store_open(const uint8_t *name_ptr, size_t name_len, zg_store **out_result)`,
Go에서 `NewStore(name string) (*Store, error)`가 됩니다. 문자열 값(`"gpa"`)은 바인딩된
루트 모듈 기준으로 해석되며, `.functions`의 경로와 같은 기준입니다.

주입 파라미터는 `.params`에도, `param_meta`에도 나오지 않습니다. release 함수도
마찬가지입니다: `fn freeString(gpa: Allocator, str: []const u8) void`는 slice 하나만 받는
release 함수로 취급되고, shim이 호출할 때 allocator를 채웁니다.

기본값은 없습니다. 설정 없이 그런 파라미터를 만나면 `ZIGO022`로 거부합니다 — 어떤 메모리를
쓸지는 zigo가 대신 정할 문제가 아닙니다. 주입 파라미터는 `semantic.json`에
`"injected": "allocator"`로 남지만 ABI 비교에서는 제외됩니다. 주입 인자만 추가하거나
옮기는 변경은 공개 시그니처를 바꾸지 않습니다. 반면 일반 인자를 주입 인자로 바꾸면
공개 인자가 사라지므로 breaking 변경입니다.

## 공개 Go 하위 패키지

`.packages`는 기본 공개 패키지 아래에 타입·namespace·함수를 나눕니다. 선택되지 않은 선언은
기본 패키지에 남습니다.

```zig
.packages = .{
    .{
        .path = "types",
        .name = "types", // 생략하면 path의 마지막 요소를 snake_case로 변환
        .doc = "Package types contains shared values and handles.",
        .types = .{ "Ticker", "Key*" },
        .namespaces = .{"text.*"},
        .functions = .{"root.liveTickers"},
        .closure = true,
    },
},
```

`path`는 `go_package_path` 기준 상대 경로입니다. 함수 배정은 명시적인 `functions`, receiver나
`go_owner`인 타입, 가장 긴 `namespaces` 접두사, 기본 패키지 순서로 결정됩니다. 타입의 메서드,
constructor, destructor, tagged-union projection은 언제나 그 타입과 같은 패키지에 있어야 하며
명시적인 함수 배정으로 떼어 놓으면 `ZIGO031`입니다.

`types`와 `namespaces` selector의 마지막 `*`는 prefix pattern입니다. 예를 들어 `"Key*"`는
`Key`, `Keyboard`, `KeyEvent`를 선택하고, `"text.*"`는 그 prefix로 시작하는 namespace를
선택합니다. 정확한 이름은 모든 package에서 pattern보다 먼저 적용되고, 같은 종류 안에서는 더
긴 prefix가 우선합니다. 어떤 선언도 찾지 못한 pattern은 오타나 낡은 설정으로 보고
`ZIGO041`로 거부합니다.

`.closure = true`는 그 package에 배정된 함수와 타입에서 도달할 수 있는 등록 타입을 전이적으로
같은 package에 넣습니다. 함수의 parameter와 return, optional/error-union payload, callback
이름·parameter·return, tagged-union과 value-struct field, `.constructs`/`.destroys` 대상,
opaque `.fields` accessor가 사용하는 타입을 모두 따라갑니다. 정확한 이름이나 pattern으로 다른
package에 먼저 배정된 타입은 이동하지 않습니다. 아직 배정되지 않은 한 타입을 두 closure
package가 요구하면 둘의 이름을 포함한 `ZIGO042`가 발생하므로, 그 타입을 한 package에
명시적으로 배정해 경계를 정합니다. 이 순서는 declaration 순서와 무관합니다.

다른 공개 패키지의 타입을 쓰는 시그니처는 `<go_module>/<go_package_path>/<path>`를 import하고
한정 이름으로 적습니다. 이 의존 그래프는 DAG여야 하며 순환은 관련 선언과 경로를 적은
`ZIGO032` 진단입니다. `ZIGO024` 이름 충돌 검사도 패키지별로 적용되므로 서로 다른 공개
패키지는 같은 Go 이름을 사용할 수 있습니다. 패키지 배정을 바꾸면 import path와 Go 표면이
움직이므로 `abi-diff`는 breaking으로 보고합니다.

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
동사로 시작할 때만 한 줄로 이어 붙이고, 그 밖의 대문자로 시작하는 문장은 자기 줄을
가집니다.

```go
// Len reports how many events are queued.

// SelectionSilent
// The selection flag bits shared by the setters below.
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
