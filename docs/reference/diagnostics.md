# 진단 참조

zigo는 생성 전에 소스 reflection, semantic 계약과 최종 출력을 검증합니다. 오류는
`error[ZIGO...]`, 발생한 선언과 가능한 해결 방법을 함께 출력합니다.

생성 이외의 도구·링크·로드 오류는 [문제 해결](../troubleshooting.md)에서 확인하세요.

## 확인 순서

1. 첫 번째 진단의 `-->` 선언을 찾습니다.
2. `hint:`가 요구하는 Zig 시그니처 또는 바인딩 entry를 수정합니다.
3. `zig build go-report`로 최종 이름·수명 결정을 확인합니다.
4. `zig build go`로 다시 생성하고 diff를 검토합니다.

여러 오류가 하나의 잘못된 타입이나 소유권에서 시작될 수 있으므로 첫 오류부터
해결하세요. 생성 실패 시 기존 출력은 유지됩니다.

## core 진단

| 코드 | 의미와 해결 방향 |
|---|---|
| `ZIGO001` | `anyerror` 결과입니다. 명시적 오류 집합을 사용합니다. |
| `ZIGO002` | non-exhaustive 열거형을 opt-in 없이 공개했습니다. `.exhaustive = false`를 지정합니다. |
| `ZIGO003` | non-extern 구조체를 값으로 전달합니다. extern value, 핸들 또는 materialized를 선택합니다. |
| `ZIGO004` | 콜백이 C 호출 규약이 아닙니다. `callconv(.c)`를 사용합니다. |
| `ZIGO005` | 슬라이스 원소가 포인터를 포함합니다. 스칼라/value 원소 또는 핸들 API로 바꿉니다. |
| `ZIGO006` | tagged union value 페이로드가 지원 범위를 벗어납니다. variant를 omit하거나 접근자를 만듭니다. |
| `ZIGO007` | 생성 tagged-union 접근자 이름이 다른 선언과 충돌합니다. 선언이나 variant 이름을 바꿉니다. |
| `ZIGO008` | comptime/generic 함수를 직접 공개했습니다. 구체적인 타입으로 특수화한 래퍼를 만듭니다. |
| `ZIGO009` | retained 포인터를 해제할 함수가 없습니다. release/clear/close 경로를 함께 공개합니다. |
| `ZIGO010` | semantic document의 타입/function reference가 맞지 않습니다. 같은 소스와 zigo로 재생성합니다. |
| `ZIGO011` | union 스냅샷으로 표현할 수 없는 variant입니다. projection을 사용하거나 페이로드를 단순화합니다. |
| `ZIGO012` | extern 구조체 필드가 C ABI에 적합하지 않습니다. 지원 필드만 남기거나 핸들로 바꿉니다. |
| `ZIGO013` | extern 구조체를 콜백 또는 optional 슬라이스 원소 등 지원하지 않는 위치에 사용했습니다. 전체 인자·결과 또는 직접 슬라이스 원소로 옮깁니다. |
| `ZIGO014` | purego 콜백 결과가 지원되지 않습니다. `void`, `bool`, `i32`를 사용합니다. |
| `ZIGO015` | caller-owned 핸들 결과와 생성자/소멸자가 연결되지 않았습니다. 역할과 쌍을 확인합니다. |
| `ZIGO016` | caller-owned 버퍼의 해제 함수가 없습니다. `result.releasedBy(ref)`를 사용합니다. |
| `ZIGO017` | `written`을 출력 슬라이스가 아닌 곳에 지정했습니다. output/inout 계약로 바꿉니다. |
| `ZIGO018` | 정수 또는 float 폭이 지원되지 않습니다. 정수 ≤64 bit, `f32`/`f64`를 사용합니다. |
| `ZIGO019` | 타입을 허용되지 않는 위치에 사용했습니다. [타입 대응](type-mapping.md)을 확인합니다. |
| `ZIGO020` | semantic IR version이 generator와 다릅니다. 같은 zigo version으로 다시 생성합니다. |
| `ZIGO021` | 패키지/타입/function 이름이 유효한 Go identifier가 아닙니다. 명시적 이름을 지정합니다. |
| `ZIGO022` | allocator 또는 `std.Io` 주입이 없습니다. 바인딩 최상위 값을 지정합니다. |
| `ZIGO023` | 스트림 위치, 수명 또는 버퍼가 잘못되었습니다. call-scoped 스트림으로 구성합니다. |
| `ZIGO024` | 공개 Go 이름이 충돌합니다. `.name` 또는 패키지 배치를 바꿉니다. |
| `ZIGO025` | `go_error`가 콜백이 아니거나 콜백 결과가 `i32`가 아닙니다. 시그니처를 수정합니다. |
| `ZIGO026` | cancel flag, 매개변수 이름 또는 오류 집합이 맞지 않습니다. cancel 계약 세 요소를 확인합니다. |
| `ZIGO027` | 매개변수 메타데이터와 원래 Zig 시그니처 index가 다릅니다. receiver와 주입을 포함해 셉니다. |
| `ZIGO028` | 생성자/소멸자의 타입, 시그니처 또는 짝이 맞지 않습니다. 명시적 role을 확인합니다. |
| `ZIGO029` | exhaustive 열거형에 open-enum opt-in을 붙였습니다. 옵션을 제거합니다. |
| `ZIGO030` | parented 생성자에 receiver가 없습니다. receiver 생성자에서만 parent를 지정합니다. |
| `ZIGO031` | 공개 패키지 path/이름/소유 선언 배치가 잘못되었습니다. owner와 메서드를 함께 둡니다. |
| `ZIGO032` | 공개 패키지 사이에 import cycle이 있습니다. 공통 타입을 상위 패키지로 옮깁니다. |
| `ZIGO033` | borrowed 결과를 소유할 receiver가 없습니다. 메서드로 바꾸거나 owned 수명을 사용합니다. |
| `ZIGO034` | borrowed 결과가 등록 핸들 포인터가 아닙니다. 지원 포인터 shape를 반환합니다. |
| `ZIGO035` | opaque 결과 소유권이 모호합니다. owned 또는 borrowed를 명시합니다. |
| `ZIGO036` | 낮춘 C identifier가 충돌합니다. `.name` 또는 바인딩 `prefix`를 바꿉니다. |
| `ZIGO037` | 핸들 필드 경로나 leaf 타입이 유효하지 않습니다. plain 구조체 경로와 스칼라 leaf를 사용합니다. |
| `ZIGO038` | 명시 receiver와 첫 non-injected 매개변수가 맞지 않습니다. 타입과 접두사를 확인합니다. |
| `ZIGO039` | `.omit`의 union variant가 없거나 중복되었습니다. 소스 spelling으로 한 번만 적습니다. |
| `ZIGO040` | flatten 필드가 없거나 지원되지 않고, 생략 필드에 기본값이 없습니다. 구조체 계약을 수정합니다. |
| `ZIGO041` | 패키지 선택자 패턴이 선언을 찾지 못합니다. 현재 선언 경로를 사용합니다. |
| `ZIGO042` | 타입이 둘 이상의 closure 패키지에 속합니다. 패키지 소유권을 하나로 정합니다. |
| `ZIGO043` | atomic 포인터 폭 또는 retention이 잘못되었습니다. 32/64 bit 정수를 call-scoped로 사용합니다. |
| `ZIGO044` | packed value 필드가 지원되지 않습니다. integer-backed 지원 필드만 사용합니다. |
| `ZIGO045` | narrow 정수 슬라이스 변환용 allocator가 없습니다. 바인딩 allocator를 지정합니다. |
| `ZIGO046` | 콜백 failure fallback이 결과 타입과 맞지 않습니다. 표현 가능한 값을 지정합니다. |
| `ZIGO048` | materialized 필드 tree, 소유권 또는 해제 계약이 잘못되었습니다. 전체 필드 경로를 확인합니다. |
| `ZIGO049` | 인터페이스 타입/메서드/시그니처가 일치하지 않습니다. 모든 구현의 생성 시그니처를 맞춥니다. |
| `ZIGO050` | iterator 대상 메서드 모양이나 이름이 잘못되었습니다. receiver-only optional 결과를 사용합니다. |
| `ZIGO051` | 열거형 text feature를 열거형이 아닌 타입에 붙였습니다. 열거형 entry로 옮깁니다. |
| `ZIGO052` | Go 어댑터 대상 또는 함수 이름이 잘못되었습니다. plain 스칼라, 열거형, extern value에만 사용합니다. |
| `ZIGO053` | semantic hint가 타입/위치와 맞지 않습니다. codepoint와 문자열·바이트 의미를 지원하는 대상인지 확인합니다. |
| `ZIGO054` | explicit selection과 discovery exclusion이 충돌합니다. 함수 경로를 한 번만 선택합니다. |
| `ZIGO055` | 콜백 userdata slot 또는 call-site token이 맞지 않습니다. `usize` 위치를 확인합니다. |
| `ZIGO056` | value receiver에 핸들 수명 기능을 사용했습니다. 패키지 함수 또는 핸들로 바꿉니다. |
| `ZIGO057` | 콜백이 ABI로 전달할 수 없는 타입을 사용합니다. 페이로드를 스칼라/핸들/accessor로 바꿉니다. |
| `ZIGO058` | 표준 I/O 인터페이스 래퍼가 요구하는 메서드 shape가 아닙니다. 매개변수/result를 맞춥니다. |
| `ZIGO059` | 플러그인 출력 경로가 잘못되었거나 다른 emitter와 충돌합니다. context 경로 도우미를 사용합니다. |
| `ZIGO060` | 플러그인 transform의 네이티브 매개변수 order가 순열이 아닙니다. `reorderParameters`를 사용합니다. |
| `ZIGO061` | functional options 계약이 잘못되었습니다(복수 옵션 매개변수, 옵션 필드 부재). 나열한 필드 중 적어도 하나에 Zig 기본값을 주거나, 전부 위치 인자로 낼 것이면 `.options` 대신 `.flatten`을 씁니다. 기본값이 없는 필드는 오류가 아니라 Go 위치 인자가 됩니다. |
| `ZIGO062` | session 계약이 잘못되었습니다(자식 없음, 중복, primary를 자식으로 나열, dependent child가 아님, `Close` 없음, 멤버의 패키지 불일치). `.children`을 고치거나 그 핸들을 세션에서 빼냅니다. |

`ZIGO047`은 현재 할당되지 않았습니다. 진단 번호가 연속적이라고 가정하지 마세요.

## reflection 단계 오류

일부 작성 오류는 semantic JSON을 만들기 전에 Zig 컴파일 error와 함께 출력됩니다. 존재하지
않는 `scope` 경로, 중복 선택자, 잘못된 플러그인 대상과 옵션 필드가 여기에 해당합니다.
문자열만 고치기보다 컴파일러가 가리킨 entry의 타입 식별 정보와 옵션 타입을 확인하세요.

## 플러그인 진단

외부 플러그인은 자신의 접두사를 가진 code를 정의할 수 있습니다. 예를 들어 `ENUMKIT002`는
enumkit 자체의 검증입니다. core `ZIGO...` 검증이 먼저 통과한 뒤 플러그인 진단이
실행됩니다. 해결 방법은 해당 [플러그인 문서](../plugins/README.md)를 확인하세요.
