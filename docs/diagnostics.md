# 생성기 진단

생성 오류를 해결할 때 진단 코드로 검색하는 참조 문서입니다. 지원 범위를 먼저 판단하려면
[제한사항](limitations.md), 선언을 고치려면 [`bindings.zig` 선언](bindings.md)을 참고하세요.

생성기 진단은 `error[ZIGOnnn]` 형식으로 코드와 원인을 알려줍니다. 문제가 된 선언
(`Owner.fn`이나 `namespace.fn`)과 파라미터 이름을 먼저 확인하세요.
이름이나 수명 계약을 고칠 수 있는 구체적인 대안이 있으면 `hint:` 다음의 `note:`가
그 선언에 적용할 수 있는 `.name`이나 release 함수 철자를 제안합니다.

```text
error[ZIGO018]: unsupported integer width `u128` in parameter `cp`
  --> semantic.json (unicode.codepointWidth)
  hint: use an integer of 64 bits or fewer
```

작성 단계의 잘못된 source 참조·중복 선언·원본 인자 인덱스·서로 맞지 않는 contract·
플러그인 대상은 `zigo.define()` 또는 helper 호출에서 Zig 컴파일 오류로 먼저 거부됩니다.
아래 코드는 reflection 이후의 진단이며, 일부는 직접 작성한 semantic 문서에서만 나타납니다.

## 어디부터 확인하나요?

1. `-->`에서 문제가 된 선언·인자를 확인합니다.
2. `hint:`의 수정 방법을 읽고, `note:`가 있으면 해당 선언에 맞는 제안을 확인합니다.
3. 아래 코드 설명에서 연결된 가이드로 이동합니다.

| 문제 | 관련 코드 |
|---|---|
| 타입·정수·enum | [002](#zigo002), [018](#zigo018), [019](#zigo019), [029](#zigo029), [043](#zigo043), [044](#zigo044) |
| 이름·패키지 | [021](#zigo021), [024](#zigo024), [031](#zigo031), [032](#zigo032), [036](#zigo036) |
| 인자·주입·메서드 | [022](#zigo022), [027](#zigo027), [037](#zigo037), [038](#zigo038) |
| 소유권·생성자 | [028](#zigo028), [030](#zigo030), [033](#zigo033), [034](#zigo034), [035](#zigo035) |
| 콜백·스트림·취소 | [023](#zigo023), [025](#zigo025), [026](#zigo026), [046](#zigo046), [055](#zigo055) |
| 메타데이터·변환 | [020](#zigo020), [045](#zigo045), [048](#zigo048), [049](#zigo049) |

## 코드별 해결 방법

아래는 자주 확인하는 진단입니다. 목록에 없는 코드는 진단의 `hint`·`note`와 해당 기능의
바인딩 가이드를 함께 확인하세요.

### ZIGO002

non-exhaustive enum을 명시적 허용 없이 노출했습니다.

Zig enum을 exhaustive로 만들거나 `api.enumType("T", .{ .exhaustive = false })`로 등록하세요.
tagged union의 non-exhaustive tag에는 이 설정을 적용할 수 없습니다.

### ZIGO018

지원하지 않는 정수·실수 폭입니다. 진단에는 중첩된 필드나 slice 원소의 경로도 표시됩니다.

정수는 64비트 이하, 실수는 `f32`·`f64`를 사용하세요. 비표준 폭 정수는 위치별 제약이
있으므로 [정수 폭](bindings-types.md#정수-폭)을 확인하세요.

### ZIGO019

지원하지 않는 타입이거나, 지원하는 타입을 허용되지 않는 위치에 사용했습니다.

진단에 표시된 매개변수·필드·반환 위치를 먼저 확인하세요. 예를 들어 optional은 함수 인자와
반환값에서 지원하지만 일반 struct 필드나 중첩 optional에는 사용할 수 없습니다.
[타입별 제한](limitations.md#zig-타입과-abi)을 참고하세요.

### ZIGO020

`semantic.json`의 IR 버전이 현재 zigo와 맞지 않습니다.

같은 zigo 버전으로 메타데이터와 Go 코드를 다시 생성하세요.

### ZIGO021

생성할 이름이 비어 있거나 유효한 Go 식별자가 아닙니다.

타입·함수에 유효한 `.name`을 지정하세요. 타입 이름은 등록한 철자를 사용하고,
필드·함수·enum 상수는 Go 이름으로 변환한 뒤 검사합니다. comptime으로 만든 타입의
`@typeName`이 식별자가 아니어도 명시적 이름으로 해결할 수 있습니다.
[이름 규칙](bindings-functions.md#경로와-이름)을 참고하세요.

파라미터 이름은 C 헤더에 그대로 선언되므로, `double`·`int`·`register` 같은 C 키워드와
`<stdint.h>`·`<stddef.h>`의 typedef 이름(`uint8_t`, `size_t` 등)도 같은 코드로 거부합니다.
공개 헤더의 일부라 맹글링하지 않으니, `.params`나 Zig 시그니처에서 이름을 바꾸세요. 주입
파라미터(`std.mem.Allocator`, `std.Io`)는 C 선언이 없어 검사하지 않습니다.

### ZIGO022

`std.mem.Allocator` 또는 `std.Io` 인자가 있지만 주입할 값이 없습니다.

바인딩에 `.allocator` 또는 `.io`를 지정하세요. 이 두 타입 이외의 Zig 전용 타입은
자동 주입되지 않습니다. [주입 설정](bindings-functions.md#allocator와-io-주입)을 참고하세요.

### ZIGO023

스트림의 위치·수명·버퍼 설정이 잘못되었습니다.

`Param.contract.stream.buffer`가 4096~16777216바이트인지 확인하세요. 스트림은 호출 동안만
사용할 수 있고, 스트림이 아닌 인자에 stream contract를 붙이면 컴파일 오류입니다. 인자와 반환 위치의 조건은
[스트림 가이드](bindings-streams.md)에 있습니다.

### ZIGO024

같은 공개 Go 패키지에서 생성할 이름이 겹칩니다.

진단에 나온 두 선언 중 하나의 `.name`을 바꾸세요. 서로 다른 Zig namespace의 자유 함수도
Go에서는 충돌할 수 있고, enum tag도 Go 상수 이름으로 변환한 뒤 충돌을 검사합니다.
다른 receiver의 메서드나 서로 다른 공개 패키지는 별도 이름 공간입니다. 등록 enum을 receiver로
쓰는 메서드는 zigo가 그 enum에 생성하는 메서드(`String`, `.use(zigo.features.text, .{})`면 `MarshalText`와
`UnmarshalText`)와도 겹칠 수 없습니다.

### ZIGO025

`go_error`를 콜백이 아닌 인자에 지정했거나, 콜백의 Zig 반환 타입이 `i32`가 아닙니다.

콜백의 반환을 `i32`로 선언하세요. 이 반환값으로 Go 오류 상태를 전달합니다.
[콜백 오류 설정](bindings-callbacks.md#콜백이-돌려주는-go-error)을 참고하세요.

### ZIGO026

취소 플래그 선언과 cancel contract가 맞지 않습니다.

해당 `*const std.atomic.Value(u32)` 인자에 `.contract = .{ .cancel = .{} }`를 붙이고, error set에
`contract.cancel.canceled`가 지정한 오류 이름이 있는지 확인하세요. 기본 오류 이름은 `Canceled`입니다.
[취소 설정](bindings-streams.md#취소-cancel)을 참고하세요.

### ZIGO027

reflection에 전달된 내부 파라미터 메타데이터 수가 시그니처와 다릅니다.

새 작성 API의 sparse `params`는 이 목록으로 정규화됩니다. `Param.index`에는 receiver와
주입 인자를 포함한 원본 Zig 인덱스를 적으세요. 유효한 새 선언에서 이 진단이 나오면
정규화 문제이므로 최소 재현을 확인해야 합니다.

### ZIGO028

생성자·소멸자의 타입, 시그니처 또는 짝이 맞지 않습니다.

constructor의 `.type` 참조와 destructor의 타입 참조가 등록 handle을 가리키는지 확인하세요. 생성자는 해당 타입의
포인터를 반환하고, 소멸자는 주입 인자를 제외한 첫 인자로 포인터를 받아 `void`를 반환해야
합니다. 한쪽만 선언하거나 같은 타입의 짝을 중복 지정할 수 없습니다.
[명시적 짝 지정](bindings-handles.md#타입-밖에-선언된-생성자와-소멸자)을 참고하세요.

### ZIGO029

exhaustive enum에 `.exhaustive = false`를 지정했습니다.

설정을 제거하거나 Zig enum을 실제 non-exhaustive enum으로 바꾸세요.

### ZIGO030

`.role.constructor.parent = .receiver`를 receiver가 있는 생성자가 아닌 함수에 지정했습니다.

부모 객체의 메서드로 자식을 생성하는 경우에만 사용하세요.
[자식 생성자](bindings-handles.md#다른-handle의-메서드인-생성자)를 참고하세요.

### ZIGO031

`zigo.package()`의 경로·이름이 잘못되었거나, 소유 타입과 함수를 다른 패키지로 나눴습니다.

타입과 그 메서드·생성자·소멸자는 같은 공개 패키지에 배치하세요.
[하위 패키지 설정](bindings-functions.md#공개-go-하위-패키지)을 참고하세요.

### ZIGO032

공개 패키지 사이에 순환 import가 생겼습니다.

진단의 `a -> b -> a` 경로를 확인하고 공통 타입을 별도 패키지로 옮기는 등 의존 방향을
정리하세요.

### ZIGO033

receiver가 없는 함수에 `.returns.lifetime = .{ .borrowed = .receiver }`를 지정했습니다.

borrowed handle은 소유자를 receiver로 확인할 수 있어야 합니다. receiver 메서드로 노출하거나
실제 소유권에 맞는 반환 방식을 선택하세요.

### ZIGO034

`.returns.lifetime = .{ .borrowed = .receiver }`의 반환값이 지원하는 opaque 포인터 형태가 아닙니다.

등록 opaque 타입의 `*T`, `?*T`, `!*T`, `!?*T`인지 확인하세요.

### ZIGO035

생성자가 아닌 메서드가 opaque 포인터를 반환하지만 소유권을 명시하지 않았습니다.

receiver가 소유한 view라면 `.returns.lifetime = .{ .borrowed = .receiver }`, 소유권을 넘긴다면 `.returns.lifetime = .{ .owned = .{} }`와
생성자·소멸자 짝을 지정하세요.

### ZIGO036

하강 후 C 식별자가 충돌합니다. 함수·타입·enum 상수·projection·런타임 심볼을 함께 검사합니다.

진단에 나온 `.name` 또는 바인딩의 `.prefix`를 바꾸세요. `note:`에 구체적인 이름 제안이
있으면 먼저 확인하세요.

### ZIGO037

opaque `.fields`의 경로가 없거나 중간 값·마지막 필드의 타입을 지원하지 않습니다.

진단의 경로를 확인하세요. 중간 값은 struct 또는 non-optional 단일 포인터여야 합니다.
마지막 필드는 scalar, 그 optional, 또는 그 slice(getter만)입니다. slice 필드에 `.set = true`를
붙여도 같은 진단입니다. 자세한 조건은 [필드 접근자](bindings-handles.md#필드-접근자)를 참고하세요.

### ZIGO038

명시적 receiver와 첫 비주입 포인터 인자가 맞지 않거나, 그룹 함수의 이름에 `strip_prefix`가 없습니다.

등록 opaque 타입과 첫 인자의 타입, 그룹에 포함한 함수 이름을 확인하세요.

### ZIGO043

atomic 포인터의 폭 또는 retention을 지원하지 않습니다.

`u32`, `i32`, `u64`, `i64`를 사용하고 주소는 호출 중에만 빌리세요.
`.retention = .retained`는 사용할 수 없습니다.

### ZIGO044

packed 값 struct에 지원하지 않는 필드가 있습니다.

bool·정수·등록 enum·등록된 정수 기반 packed struct 필드로 바꾸세요.
[Packed struct 조건](bindings-types.md#packed-struct-값)을 참고하세요.

### ZIGO045

비표준 폭 정수 slice를 변환할 임시 버퍼의 allocator가 없습니다.

바인딩에 `.allocator = .c_allocator`, `.page_allocator`, `.smp_allocator` 또는 allocator
선언 경로를 지정하세요.

### ZIGO046

콜백의 `on_failure`를 잘못 지정했거나, 반환 타입이 `void`이거나,
지정한 `.result`가 콜백 반환 타입으로 표현되지 않습니다. 콜백에만 설정하고 반환 타입에
맞는 실패값을 선택하세요. [콜백 가이드](bindings-callbacks.md)를 참고하세요.

### ZIGO055

콜백의 userdata 규약이 깨졌습니다. 콜백에 `usize` userdata 자리가 없거나(기본은 마지막
파라미터), 등록 항목의 `.userdata`가 가리킨 자리가 `usize`가 아니거나, 콜백을 받는 함수에
토큰을 넘길 `usize` 파라미터가 없거나(기본은 콜백 바로 다음), callback `Param.userdata`가
이름한 파라미터가 없거나 `usize`가 아닙니다. 콜백이 아닌 파라미터에 `.userdata`를 두어도 같은
코드입니다. [콜백 시그니처 규약](bindings-callbacks.md#콜백-시그니처-규약)을 참고하세요.

### ZIGO048

materialized 결과의 필드나 소유권·해제 선언이 잘못되었습니다. 진단의 전체 필드 경로를
먼저 확인하고, 결과에 `.returns.lifetime = .{ .owned = .{} }`와 직렬화 버퍼 `[]u8`를 해제하는 `.returns.lifetime.owned.release`를
지정했는지 확인하세요. 해제 인자는 Go `[]byte`로 매핑되어야 하며, 문자열로 추론되는
인자는 `.semantic = .opaque_bytes`를 명시하세요. 필드 제약은 [Materialized 버퍼 ABI](abi.md)에 있습니다.

### ZIGO049

인터페이스의 타입·메서드 목록이나 생성 Go 시그니처가 맞지 않습니다. 등록 opaque 타입을
중복 없이 나열하고, 모든 타입이 지정한 메서드를 같은 Go 시그니처로 노출하는지 확인하세요.
`.closer = true`이면 생성자·소멸자 짝도 필요합니다. 인터페이스와 구현 타입은 같은 공개
패키지에 있어야 합니다. [객체 수명과 인터페이스](bindings-handles.md)를 참고하세요.

### ZIGO050

`features.iterator`를 붙인 함수가 receiver가 없거나, receiver 외의 파라미터를 받거나, `?T`·`!?T`가
아닌 값을 반환하거나, wrapper 이름이 exported Go 식별자가 아닙니다. 등록 opaque 타입의
메서드로 옮기고 인자는 생성자로 빼세요.
[Iterator wrapper](bindings-handles.md#iterator-wrapper)를 참고하세요.

### ZIGO052

`.go` 어댑터를 `extern struct` 값이나 enum이 아닌 타입에 붙였거나, tagged union의 tag enum에
붙였거나, plain scalar가 아닌 파라미터·반환값(optional, slice, flatten 필드, 좁은 정수)에
붙였거나, `.type`이 비어 있거나, `.to_raw`/`.from_raw`가 Go 식별자가 아닙니다.
[Go 타입 어댑터](bindings-types.md#go-타입-어댑터)를 참고하세요.

### ZIGO053

`.semantic = .codepoint`를 `u21`/`u32` 스칼라나 그 plain slice(`[]const T`, `[]T`)가 아닌
파라미터·반환값에 붙였거나, `.fields`로 extern struct의 `u32`가 아닌 필드에 붙였거나,
등록 callback의 `u32` 스칼라가 아닌 자리에 붙였거나, 손으로 쓴 `semantic.json`에 `.integer`
힌트가 남아 있습니다. 반환값은 `!`나 `?` 안의 스칼라, 또는 plain slice여야 하며,
optional 파라미터·sentinel slice·flatten 필드·주입 파라미터에는 붙일 수 없습니다.
[코드포인트](bindings-types.md#코드포인트)를 참고하세요.

### ZIGO051

`.use(zigo.features.text, .{})`를 enum이 아닌 타입에 지정했습니다. 텍스트 인코딩은 `.enumeration`
등록 항목에서만 켤 수 있습니다. [Enum 텍스트 인코딩](bindings-types.md#enum-텍스트-인코딩)을
참고하세요.

### ZIGO054

명시 선언과 discovery 제외 목록이 충돌했습니다. 제외할 함수를 명시 선언에도 넣지 마세요.
새 API의 중복 선언·중복 제외는 작성 단계에서 먼저 거부합니다. 내부 flat 선언을 직접
사용하는 reflection 테스트에서는 중복도 이 진단으로 나타납니다.

### ZIGO056

값 receiver가 handle에만 있는 것을 요구했습니다. 등록 enum의 메서드에는 닫을 handle도, 부모도,
빌려줄 수명도 없으므로 `.role.constructor`, `.role.constructor.parent`, `.returns.lifetime = .{ .borrowed = .receiver }`,
`features.iterator`, `std.Io` 스트림 파라미터를 쓸 수 없습니다. 또 `.go` 어댑터가 붙은 enum은 Go에서
남의 패키지 타입이라 메서드를 가질 수 없습니다. 함수를 패키지 레벨로 바인딩하거나, 상태가
있는 타입이라면 `.handle`로 등록하세요.
[자유 함수를 메서드로 등록하기](bindings-functions.md#자유-함수를-메서드로-등록하기)를
참고하세요.

### ZIGO057

콜백 시그니처에 C scalar로 건너갈 수 없는 타입이 있습니다. 콜백 파라미터는 bool, 정수,
부동소수, 등록 enum, 등록 packed 값, 등록 handle의 포인터, `[*:0]const u8` 문자열,
`[*]const u8` + `usize` 바이트 쌍만 될 수 있고, 결과는 scalar·enum·packed 값과 `void`입니다.
`[]const u8` slice(C 호출 규약이 받지 못함)·가변이나 비바이트 slice·extern struct·optional·
값으로 받는 handle은 콜백에 실을 수 없습니다. 문자열은 many pointer spelling으로 바꾸고,
그 밖의 payload는 콜백이 받는 handle의 메서드로 읽게 하세요.
[콜백 값 타입](bindings-callbacks.md#콜백-값-타입)을 참고하세요.

### ZIGO058

`features.implements`를 붙인 메서드가 인터페이스에서 한 걸음 떨어진 모양이 아닙니다. receiver가 없거나,
`features.iterator`·`.cancel`이 함께 있거나, 결과가 `void`·정수가 아니거나, 파라미터가 인터페이스가
넘기는 하나(`.writer`는 문자열 힌트 없는 `[]const u8`, `.reader`는 `.written = .result`인 `.out`
`[]u8`, `.writer_to`는 `*std.Io.Writer`, `.reader_from`은 `*std.Io.Reader`)가 아닙니다. wrapper는
그 인자만 넘겨 메서드를 호출하므로 다른 인자는 생성자로 빼고, 문자열 힌트는 지우세요.
wrapper 이름이 같은 타입의 다른 메서드와 겹치면 `ZIGO024`입니다.
[handle이 io 인터페이스를 구현하기](bindings-streams.md#handle이-io-인터페이스를-구현하기)를
참고하세요.

### ZIGO059

출력 파일 경로가 유효하지 않거나 다른 emitter와 겹칩니다. 경로는 출력 디렉터리 안의
상대 경로여야 하며, `./file.go`와 `dir/../file.go`도 같은 경로로 취급합니다. 플러그인의
`pathAlloc`에서 `plugin.publicFilePathAlloc`을 사용하고 파일명을 고유하게 정하세요.
진단은 충돌한 emitter와 패키지를 표시하며, 이 오류가 나면 기존 출력은 변경하지 않습니다.

## 리플렉션 단계의 오류

`ZIGO027`, `ZIGO028`, `ZIGO037`, `ZIGO038`, `ZIGO054`는 reflection이 문서를 만들기 전에 걸리므로 `semantic.json` 자리가
아니라 선언 경로를 가리키며, 생성기는 이 진단을 출력하고 종료합니다.

리플렉션 단계의 거부는 `bindings.zig`를 빌드할 때의 `@compileError`로 나오며, 제약과 함께
문제가 된 선언·파라미터를 표시합니다(`... , at \`Terminal.write\` parameter \`bytes\``).

## 플러그인 진단

플러그인이 내는 진단은 `ZIGO` 코드를 쓰지 않고 플러그인 이름을 접두어로 씁니다
(`SATIS001`). 어느 플러그인이 거부했는지 코드만 보고 알 수 있어야 하기 때문입니다.
플러그인 규칙은 항상 생성기의 핵심 규칙 뒤에 돌므로, 플러그인이 문서 자체의 결함을
가리는 일은 없습니다.

`<NAME>001`은 모든 플러그인이 공통으로 가지는 코드입니다. `semantic.json`의 `ext`에
그 대상에 맞지 않거나 대상별 옵션 타입으로 읽을 수 없는 값이 들어 있다는 뜻입니다. 손으로 고친
문서가 아니라면 나오지 않습니다. `bindings.zig`에서 `use`로 붙인 옵션은 선언
자리에서 Zig 컴파일 오류로 걸리기 때문입니다.

`validateAll`을 구현한 플러그인은 여러 독립적인 진단을 한 번에 반환할 수 있습니다.
핵심 구조 오류는 먼저 해결해야 하며, 옵션 파싱이 실패한 플러그인의 후속 validator는
실행하지 않습니다. 자세한 계약은 [플러그인 문서](plugins.md#여러-진단-반환)를 참고하세요.
