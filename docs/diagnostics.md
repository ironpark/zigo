# 생성기 진단

생성 오류를 해결할 때 진단 코드로 검색하는 참조 문서입니다. 지원 범위를 먼저 판단하려면
[제한사항](limitations.md), 선언을 고치려면 [`bindings.zig` 선언](bindings.md)을 참고하세요.

생성기 진단은 `error[ZIGOnnn]` 형식으로 코드와 원인을 알려줍니다. 문제가 된 선언
(`Owner.fn`이나 `namespace.fn`)과 파라미터 이름을 먼저 확인하세요.
이름이나 수명 계약을 고칠 수 있는 구체적인 대안이 있으면 `hint:` 다음의 `note:`가
그 선언에 적용할 수 있는 `.name`이나 release 함수 철자를 제안한다. `note:`는 해결 방법만
설명하며 진단 결과 자체에는 영향을 주지 않는다.

```
error[ZIGO018]: unsupported integer width `u128` in parameter `cp`
  --> semantic.json (unicode.codepointWidth)
  hint: use an integer of 64 bits or fewer
```

## 코드별 해결 방법

아래는 자주 확인하는 진단입니다. 목록에 없는 코드는 진단의 `hint`·`note`와 해당 기능의
바인딩 가이드를 함께 확인하세요.

### ZIGO002

non-exhaustive enum을 opt-in 없이 노출했다. enum을 exhaustive로 만들거나
`.types`에 `.repr = .enumeration, .exhaustive = false`로 등록한다. tagged union의
non-exhaustive tag에는 이 opt-in을 적용할 수 없다.

### ZIGO018

C ABI가 이름 붙일 수 없는 정수·실수 폭이다. 중첩된 위치는 `the slice element
of parameter \`cps\``처럼 도달 경로까지 적는다.

### ZIGO019

지원하지 않는 타입이다. optional이 매개변수·반환·error payload가 아닌
자리에 있으면 실을 presence 자리가 없다는 힌트와 함께 이 코드로 거부된다.

### ZIGO020

`semantic.json`의 IR 버전이 이 zigo와 맞지 않는다. 다시 생성한다.

### ZIGO021

이름이 비어 있거나 Go 식별자가 아니다. package, prefix, 함수 이름의 공백과,
reflection이 유도했든 `.name`으로 준 것이든 생성될 Go 이름이 모두 여기서 검사된다.
등록된 타입 이름은 Go에 그대로 나가므로 쓰인 철자 그대로, 필드·함수 이름은 zigo가
PascalCase로 바꾼 뒤의 철자로 판단한다(Zig의 `type` 필드는 Go `Type`이라 통과한다).
enum tag는 실제 상수 철자 `<Type><Pascal(tag)>` 전체를 검사하므로 `80_cols`도
`DeccolmMode80Cols`처럼 유효한 이름이 되면 통과한다. Pascal 변환 결과가 비는 tag처럼 실제
생성 이름을 만들 수 없는 경우는 계속 거부한다.
`@typeName`이 식별자가 아닌 comptime 생성 타입(`lib.Enum(...)[0..4])`)은 `.types`에
`.name`과 함께 등록해 이름을 준다. 메시지는 Zig 타입 경로를 함께 적는다.

### ZIGO022

`std.mem.Allocator`나 `std.Io` 파라미터를 만났는데 바인딩이 `.allocator`나
`.io`를 정하지 않았다. 이 두 타입만 주입 대상이며, 그 밖의 Zig 전용 타입은 여전히
`ZIGO019`다.

### ZIGO023

`*std.Io.Writer`/`*std.Io.Reader`를 쓸 수 없는 자리에 썼거나, 스트림에
`.retention = .retained`를 달았거나, `buffer`가 4096..16777216 밖이거나 스트림이 아닌
파라미터에 붙었다. 메시지가 넷을 구분한다.

### ZIGO024

공개 Go 이름이 충돌한다. receiver가 없는 함수는 namespace가 아니라 마지막
세그먼트(또는 `.name`)만으로 이름이 정해지므로, 서로 다른 namespace의 같은 이름 함수나
namespace 함수와 등록된 타입이 이름을 나눠 가질 수 있다. 메서드는 receiver별로 이름
공간이 나뉘므로 다른 receiver의 같은 메서드 이름은 충돌이 아니다. 같은 enum 안에서
두 tag가 PascalCase로 같은 이름이 되는 경우도 여기서 잡는다. 메시지는 충돌하는 두 Zig
경로를 모두 적으며, `.name`으로 한쪽 이름을 바꾸면 통과한다. 충돌 범위는 공개 패키지
하나이므로 서로 다른 `.packages` 항목에서는 같은 이름을 쓸 수 있다.

### ZIGO025

`param_meta.<이름>.go_error`를 콜백이 아닌 파라미터에 달았거나, 콜백의 Zig
반환 타입이 `i32`가 아니다. Go error는 결과 자리에 `-5`로 실려 건너가므로 `i32` 결과가
없는 콜백은 그것을 알릴 방법이 없다.

### ZIGO026

`.cancel`이 존재하지 않는 파라미터를 가리키거나, 그 파라미터 타입이
`*const std.atomic.Value(u32)`가 아니거나, 함수의 error set에 설정한 취소 오류
(`.cancel.canceled`, 기본 `Canceled`)가 없거나,
취소 플래그 파라미터가 있는데 `.cancel`이 그것을 가리키지 않는다.


### ZIGO027

`.params`가 적은 이름 개수가 Go에 보이는 파라미터 개수와 다르다. receiver와
주입 파라미터(`std.mem.Allocator`, `std.Io`)는 C에도 Go에도 나타나지 않으므로 `.params`에
적지 않는다. 메시지는 적은 개수와 기대 개수, 그리고 선언 경로를 적는다.

### ZIGO028

`.constructs`/`.destroys`가 등록되지 않은 타입을 가리키거나, `.constructs`를
단 함수가 그 타입의 pointer를 반환하지 않거나, `.destroys`를 단 함수가 그 타입의
pointer를 (주입 파라미터를 제외한) 첫 파라미터로 받지 않거나 void를 반환하지 않거나, 한 타입에 대해 한쪽만
선언했거나, 같은 타입을 둘이 겹쳐 선언했다. 메시지가 이들을 구분한다.

### ZIGO029

실제로는 exhaustive인 enum 등록에 `.exhaustive = false`를 붙였다. opt-in을
제거하거나 Zig enum을 non-exhaustive로 바꾼다.

### ZIGO030

`.child_of_receiver = true`를 receiver constructor가 아닌 함수에 붙였다.

### ZIGO031

`.packages`의 경로·이름·selector가 잘못됐거나, 같은 선언을 중복 선택했거나,
타입과 그 메서드·constructor·destructor를 서로 다른 패키지로 나누려 했다.

### ZIGO032

공개 패키지 타입 참조 그래프에 import cycle이 있다. 메시지는 순환을 만든
선언과 `a -> b -> a` 형태의 패키지 경로를 함께 적는다.

### ZIGO033

`.returns = .borrowed`를 receiver 없는 함수에 붙였다.

### ZIGO034

`.returns = .borrowed` 반환이 등록 opaque 타입의 `*T`, `?*T`, `!*T`, `!?*T`가
아니다.

### ZIGO035

constructor가 아닌 메서드가 opaque pointer를 반환하면서 `.returns`를
생략했다. receiver-owned view면 `.borrowed`, ownership transfer면 constructor/destructor와
`.caller`를 명시한다.

### ZIGO036

lowering 뒤 C 식별자가 충돌한다. 함수 심볼, handle·enum·struct·snapshot
typedef, enum 상수, projection, runtime helper를 함께 검사하며 진단이 두 선언을 지목한다.
`.name`이나 바인딩 `.prefix`를 바꿔 구분한다. `note:`는 constructor 이름 변경을 제안하지
않고, 타입과 함수가 충돌하면 타입 쪽의 구체적인 `.name`을 우선 제안한다.

### ZIGO037

opaque 타입의 `.fields` 경로가 없거나, struct 값 또는 non-optional single
pointer 이외의 값을 가로지르거나, bool·정수·실수·등록 enum 이외의 타입에서 끝난다.
메시지는 경로와, 경로가 해석된 경우 지원하지 않는 필드 타입을 함께 적는다.

### ZIGO038

명시한 함수 receiver가 등록 opaque 타입의 첫 비주입 pointer 파라미터와
일치하지 않거나, receiver group의 함수 이름이 `strip_prefix`로 시작하지 않는다.

### ZIGO043

atomic 포인터 파라미터의 scalar가 `u32`, `i32`, `u64`, `i64` 중 하나가
아니거나 `.retention = .retained`를 지정했다. 지원하는 `sync/atomic` 폭을 사용하고 주소는
호출 범위에서만 빌린다.

### ZIGO044

`.repr = .value`인 packed struct에 bool, 정수, 등록 enum, 등록 integer-backed
packed struct 이외의 필드가 있다. 진단에 표시된 필드를 지원하는 값 타입으로 바꾼다.

### ZIGO045

narrow integer를 직접 원소로 둔 입력·out slice의 임시 변환 버퍼에 쓸 allocator가
없다. 바인딩에 `.allocator = .c_allocator`, `.page_allocator`, `.smp_allocator` 또는 선언 경로를
지정한다.

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

## 리플렉션 단계의 오류

`ZIGO027`, `ZIGO028`, `ZIGO037`, `ZIGO038`은 reflection이 문서를 만들기 전에 걸리므로 `semantic.json` 자리가
아니라 선언 경로를 가리키며, 생성기는 이 진단을 출력하고 종료한다.

리플렉션 단계의 거부는 `bindings.zig`를 빌드할 때의 `@compileError`로 나오며, 제약과 함께
그것이 걸린 선언·파라미터를 적는다(`... , at \`Terminal.write\` parameter \`bytes\``).
