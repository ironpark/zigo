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
| 콜백·스트림·취소 | [023](#zigo023), [025](#zigo025), [026](#zigo026), [046](#zigo046) |
| 메타데이터·변환 | [020](#zigo020), [045](#zigo045), [048](#zigo048), [049](#zigo049) |

## 코드별 해결 방법

아래는 자주 확인하는 진단입니다. 목록에 없는 코드는 진단의 `hint`·`note`와 해당 기능의
바인딩 가이드를 함께 확인하세요.

### ZIGO002

non-exhaustive enum을 명시적 허용 없이 노출했습니다.

Zig enum을 exhaustive로 만들거나 `.repr = .enumeration, .exhaustive = false`로 등록하세요.
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

### ZIGO022

`std.mem.Allocator` 또는 `std.Io` 인자가 있지만 주입할 값이 없습니다.

바인딩에 `.allocator` 또는 `.io`를 지정하세요. 이 두 타입 이외의 Zig 전용 타입은
자동 주입되지 않습니다. [주입 설정](bindings-functions.md#allocator와-io-주입)을 참고하세요.

### ZIGO023

스트림의 위치·수명·버퍼 설정이 잘못되었습니다.

스트림에 `.retention = .retained`를 지정하지 않았는지, `buffer`가 4096~16777216바이트인지,
스트림이 아닌 인자에 `buffer`를 붙이지 않았는지 확인하세요. 인자와 반환 위치의 조건은
[스트림 가이드](bindings-streams.md)에 있습니다.

### ZIGO024

같은 공개 Go 패키지에서 생성할 이름이 겹칩니다.

진단에 나온 두 선언 중 하나의 `.name`을 바꾸세요. 서로 다른 Zig namespace의 자유 함수도
Go에서는 충돌할 수 있고, enum tag도 Go 상수 이름으로 변환한 뒤 충돌을 검사합니다.
다른 receiver의 메서드나 서로 다른 공개 패키지는 별도 이름 공간입니다.

### ZIGO025

`go_error`를 콜백이 아닌 인자에 지정했거나, 콜백의 Zig 반환 타입이 `i32`가 아닙니다.

콜백의 반환을 `i32`로 선언하세요. 이 반환값으로 Go 오류 상태를 전달합니다.
[콜백 오류 설정](bindings-callbacks.md#콜백이-돌려주는-go-error)을 참고하세요.

### ZIGO026

취소 플래그 선언과 `.cancel` 설정이 맞지 않습니다.

`.cancel.param`이 실제 `*const std.atomic.Value(u32)` 인자를 가리키는지, 함수의 error set에
설정한 취소 오류 이름이 있는지 확인하세요. 기본 오류 이름은 `Canceled`입니다.
[취소 설정](bindings-streams.md#취소-cancel)을 참고하세요.

### ZIGO027

`.params`에 지정한 이름 개수가 기대하는 인자 개수와 다릅니다.

receiver와 주입 인자(`std.mem.Allocator`, `std.Io`)를 목록에서 제외하세요.
진단에는 실제 개수·기대 개수와 선언 경로가 표시됩니다.

### ZIGO028

생성자·소멸자의 타입, 시그니처 또는 짝이 맞지 않습니다.

`.constructs`·`.destroys`가 등록한 타입을 가리키는지 확인하세요. 생성자는 해당 타입의
포인터를 반환하고, 소멸자는 주입 인자를 제외한 첫 인자로 포인터를 받아 `void`를 반환해야
합니다. 한쪽만 선언하거나 같은 타입의 짝을 중복 지정할 수 없습니다.
[명시적 짝 지정](bindings-handles.md#타입-밖에-선언된-생성자와-소멸자)을 참고하세요.

### ZIGO029

exhaustive enum에 `.exhaustive = false`를 지정했습니다.

설정을 제거하거나 Zig enum을 실제 non-exhaustive enum으로 바꾸세요.

### ZIGO030

`.child_of_receiver = true`를 receiver가 있는 생성자가 아닌 함수에 지정했습니다.

부모 객체의 메서드로 자식을 생성하는 경우에만 사용하세요.
[자식 생성자](bindings-handles.md#다른-handle의-메서드인-생성자)를 참고하세요.

### ZIGO031

`.packages`의 경로·이름·selector가 잘못되었거나 선언을 중복 선택했습니다.

타입과 그 메서드·생성자·소멸자는 같은 공개 패키지에 배치하세요.
[하위 패키지 설정](bindings-functions.md#공개-go-하위-패키지)을 참고하세요.

### ZIGO032

공개 패키지 사이에 순환 import가 생겼습니다.

진단의 `a -> b -> a` 경로를 확인하고 공통 타입을 별도 패키지로 옮기는 등 의존 방향을
정리하세요.

### ZIGO033

receiver가 없는 함수에 `.returns = .borrowed`를 지정했습니다.

borrowed handle은 소유자를 receiver로 확인할 수 있어야 합니다. receiver 메서드로 노출하거나
실제 소유권에 맞는 반환 방식을 선택하세요.

### ZIGO034

`.returns = .borrowed`의 반환값이 지원하는 opaque 포인터 형태가 아닙니다.

등록 opaque 타입의 `*T`, `?*T`, `!*T`, `!?*T`인지 확인하세요.

### ZIGO035

생성자가 아닌 메서드가 opaque 포인터를 반환하지만 소유권을 명시하지 않았습니다.

receiver가 소유한 view라면 `.returns = .borrowed`, 소유권을 넘긴다면 `.returns = .caller`와
생성자·소멸자 짝을 지정하세요.

### ZIGO036

하강 후 C 식별자가 충돌합니다. 함수·타입·enum 상수·projection·런타임 심볼을 함께 검사합니다.

진단에 나온 `.name` 또는 바인딩의 `.prefix`를 바꾸세요. `note:`에 구체적인 이름 제안이
있으면 먼저 확인하세요.

### ZIGO037

opaque `.fields`의 경로가 없거나 중간 값·마지막 필드의 타입을 지원하지 않습니다.

진단의 경로를 확인하세요. 중간 값은 struct 또는 non-optional 단일 포인터여야 합니다.
마지막 필드의 조건은 [필드 접근자](bindings-handles.md#필드-접근자)를 참고하세요.

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

`.on_callback_failure`를 콜백이 아닌 곳에 지정했거나, 반환 타입이 `void`이거나,
지정한 `.result`가 콜백 반환 타입으로 표현되지 않습니다. 콜백에만 설정하고 반환 타입에
맞는 실패값을 선택하세요. [콜백 가이드](bindings-callbacks.md)를 참고하세요.

### ZIGO048

materialized 결과의 필드나 소유권·해제 선언이 잘못되었습니다. 진단의 전체 필드 경로를
먼저 확인하고, 결과에 `.returns = .caller`와 직렬화 버퍼 `[]u8`를 해제하는 `.release`를
지정했는지 확인하세요. 필드 제약은 [Materialized 버퍼 ABI](abi.md)에 있습니다.

### ZIGO049

인터페이스의 타입·메서드 목록이나 생성 Go 시그니처가 맞지 않습니다. 등록 opaque 타입을
중복 없이 나열하고, 모든 타입이 지정한 메서드를 같은 Go 시그니처로 노출하는지 확인하세요.
`.closer = true`이면 생성자·소멸자 짝도 필요합니다. 인터페이스와 구현 타입은 같은 공개
패키지에 있어야 합니다. [객체 수명과 인터페이스](bindings-handles.md)를 참고하세요.

### ZIGO051

`.text = true`를 enum이 아닌 타입에 지정했습니다. 텍스트 인코딩은 `.repr = .enumeration`
등록 항목에서만 켤 수 있습니다. [Enum 텍스트 인코딩](bindings-types.md#enum-텍스트-인코딩)을
참고하세요.

## 리플렉션 단계의 오류

`ZIGO027`, `ZIGO028`, `ZIGO037`, `ZIGO038`은 reflection이 문서를 만들기 전에 걸리므로 `semantic.json` 자리가
아니라 선언 경로를 가리키며, 생성기는 이 진단을 출력하고 종료합니다.

리플렉션 단계의 거부는 `bindings.zig`를 빌드할 때의 `@compileError`로 나오며, 제약과 함께
문제가 된 선언·파라미터를 표시합니다(`... , at \`Terminal.write\` parameter \`bytes\``).
