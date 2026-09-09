# 진단 참조

zigo는 생성 전에 source reflection, semantic contract와 최종 output을 검증합니다. 오류는
`error[ZIGO...]`, 발생한 선언과 가능한 해결 방법을 함께 출력합니다.

## 확인 순서

1. 첫 번째 진단의 `-->` declaration을 찾습니다.
2. `hint:`가 요구하는 Zig signature 또는 binding entry를 수정합니다.
3. `zig build go-report`로 최종 이름·수명 결정을 확인합니다.
4. `zig build go`로 다시 생성하고 diff를 검토합니다.

여러 오류가 하나의 잘못된 type이나 ownership에서 시작될 수 있으므로 첫 오류부터
해결하세요. 생성 실패 시 기존 output은 유지됩니다.

## core 진단

| 코드 | 의미와 해결 방향 |
|---|---|
| `ZIGO001` | `anyerror` result입니다. 명시적 error set을 사용합니다. |
| `ZIGO002` | non-exhaustive enum을 opt-in 없이 공개했습니다. `.exhaustive = false`를 지정합니다. |
| `ZIGO003` | non-extern struct를 값으로 전달합니다. extern value, handle 또는 materialized를 선택합니다. |
| `ZIGO004` | callback이 C calling convention이 아닙니다. `callconv(.c)`를 사용합니다. |
| `ZIGO005` | slice element가 pointer를 포함합니다. scalar/value element 또는 handle API로 바꿉니다. |
| `ZIGO006` | tagged union value payload가 지원 범위를 벗어납니다. variant를 omit하거나 accessor를 만듭니다. |
| `ZIGO007` | 생성 tagged-union accessor 이름이 다른 선언과 충돌합니다. 선언이나 variant 이름을 바꿉니다. |
| `ZIGO008` | comptime/generic function을 직접 공개했습니다. concrete specialization wrapper를 만듭니다. |
| `ZIGO009` | retained pointer를 해제할 함수가 없습니다. release/clear/close 경로를 함께 공개합니다. |
| `ZIGO010` | semantic document의 type/function reference가 맞지 않습니다. 같은 source와 zigo로 재생성합니다. |
| `ZIGO011` | union snapshot으로 표현할 수 없는 variant입니다. projection을 사용하거나 payload를 단순화합니다. |
| `ZIGO012` | extern struct field가 C ABI에 적합하지 않습니다. 지원 field만 남기거나 handle로 바꿉니다. |
| `ZIGO013` | extern struct를 optional/callback 등 지원하지 않는 위치에 사용했습니다. whole value 위치로 옮깁니다. |
| `ZIGO014` | purego callback result가 지원되지 않습니다. `void`, `bool`, `i32`를 사용합니다. |
| `ZIGO015` | caller-owned handle result와 constructor/destructor가 연결되지 않았습니다. 역할과 쌍을 확인합니다. |
| `ZIGO016` | caller-owned buffer의 release function이 없습니다. `result.releasedBy(ref)`를 사용합니다. |
| `ZIGO017` | `written`을 output slice가 아닌 곳에 지정했습니다. output/inout contract로 바꿉니다. |
| `ZIGO018` | integer 또는 float 폭이 지원되지 않습니다. integer ≤64 bit, `f32`/`f64`를 사용합니다. |
| `ZIGO019` | type을 허용되지 않는 위치에 사용했습니다. [타입 대응](type-mapping.md)을 확인합니다. |
| `ZIGO020` | semantic IR version이 generator와 다릅니다. 같은 zigo version으로 다시 생성합니다. |
| `ZIGO021` | package/type/function 이름이 유효한 Go identifier가 아닙니다. 명시적 이름을 지정합니다. |
| `ZIGO022` | allocator 또는 `std.Io` injection이 없습니다. binding 최상위 값을 지정합니다. |
| `ZIGO023` | stream 위치, lifetime 또는 buffer가 잘못되었습니다. call-scoped stream으로 구성합니다. |
| `ZIGO024` | public Go 이름이 충돌합니다. `.name` 또는 package 배치를 바꿉니다. |
| `ZIGO025` | `go_error`가 callback이 아니거나 callback result가 `i32`가 아닙니다. signature를 수정합니다. |
| `ZIGO026` | cancel flag, parameter 이름 또는 error set이 맞지 않습니다. cancel contract 세 요소를 확인합니다. |
| `ZIGO027` | parameter metadata와 원래 Zig signature index가 다릅니다. receiver와 injection을 포함해 셉니다. |
| `ZIGO028` | constructor/destructor의 type, signature 또는 짝이 맞지 않습니다. 명시적 role을 확인합니다. |
| `ZIGO029` | exhaustive enum에 open-enum opt-in을 붙였습니다. option을 제거합니다. |
| `ZIGO030` | parented constructor에 receiver가 없습니다. receiver constructor에서만 parent를 지정합니다. |
| `ZIGO031` | public package path/이름/소유 declaration 배치가 잘못되었습니다. owner와 method를 함께 둡니다. |
| `ZIGO032` | public package 사이에 import cycle이 있습니다. 공통 type을 상위 package로 옮깁니다. |
| `ZIGO033` | borrowed result를 소유할 receiver가 없습니다. method로 바꾸거나 owned lifetime을 사용합니다. |
| `ZIGO034` | borrowed result가 등록 handle pointer가 아닙니다. 지원 pointer shape를 반환합니다. |
| `ZIGO035` | opaque result ownership이 모호합니다. owned 또는 borrowed를 명시합니다. |
| `ZIGO036` | 낮춘 C identifier가 충돌합니다. `.name` 또는 binding `prefix`를 바꿉니다. |
| `ZIGO037` | handle field path나 leaf type이 유효하지 않습니다. plain struct path와 scalar leaf를 사용합니다. |
| `ZIGO038` | 명시 receiver와 첫 non-injected parameter가 맞지 않습니다. type과 prefix를 확인합니다. |
| `ZIGO039` | `.omit`의 union variant가 없거나 중복되었습니다. source spelling으로 한 번만 적습니다. |
| `ZIGO040` | flatten field가 없거나 지원되지 않고, 생략 field에 default가 없습니다. struct contract를 수정합니다. |
| `ZIGO041` | package selector pattern이 declaration을 찾지 못합니다. 현재 선언 경로를 사용합니다. |
| `ZIGO042` | type이 둘 이상의 closure package에 속합니다. package ownership을 하나로 정합니다. |
| `ZIGO043` | atomic pointer 폭 또는 retention이 잘못되었습니다. 32/64 bit integer를 call-scoped로 사용합니다. |
| `ZIGO044` | packed value field가 지원되지 않습니다. integer-backed 지원 field만 사용합니다. |
| `ZIGO045` | narrow integer slice 변환용 allocator가 없습니다. binding allocator를 지정합니다. |
| `ZIGO046` | callback failure fallback이 result type과 맞지 않습니다. 표현 가능한 값을 지정합니다. |
| `ZIGO048` | materialized field tree, ownership 또는 release contract가 잘못되었습니다. 전체 field path를 확인합니다. |
| `ZIGO049` | interface type/method/signature가 일치하지 않습니다. 모든 구현의 생성 signature를 맞춥니다. |
| `ZIGO050` | iterator 대상 method 모양이나 이름이 잘못되었습니다. receiver-only optional result를 사용합니다. |
| `ZIGO051` | enum text feature를 enum이 아닌 type에 붙였습니다. enum entry로 옮깁니다. |
| `ZIGO052` | Go adapter 대상 또는 함수 이름이 잘못되었습니다. plain scalar, enum, extern value에만 사용합니다. |
| `ZIGO053` | semantic hint가 type/위치와 맞지 않습니다. codepoint와 opaque byte 대상만 지정합니다. |
| `ZIGO054` | explicit selection과 discovery exclusion이 충돌합니다. function path를 한 번만 선택합니다. |
| `ZIGO055` | callback userdata slot 또는 call-site token이 맞지 않습니다. `usize` 위치를 확인합니다. |
| `ZIGO056` | value receiver에 handle lifetime 기능을 사용했습니다. package function 또는 handle로 바꿉니다. |
| `ZIGO057` | callback이 ABI로 전달할 수 없는 type을 사용합니다. payload를 scalar/handle/accessor로 바꿉니다. |
| `ZIGO058` | 표준 I/O interface wrapper가 요구하는 method shape가 아닙니다. parameter/result를 맞춥니다. |
| `ZIGO059` | plugin output path가 잘못되었거나 다른 emitter와 충돌합니다. context path helper를 사용합니다. |
| `ZIGO060` | plugin transform의 native parameter order가 순열이 아닙니다. `reorderParameters`를 사용합니다. |

`ZIGO047`은 현재 할당되지 않았습니다. 진단 번호가 연속적이라고 가정하지 마세요.

## reflection 단계 오류

일부 작성 오류는 semantic JSON을 만들기 전에 Zig compile error와 함께 출력됩니다. 존재하지
않는 `scope` path, 중복 selector, 잘못된 plugin target과 option field가 여기에 해당합니다.
문자열만 고치기보다 compiler가 가리킨 entry의 type identity와 option type을 확인하세요.

## plugin 진단

외부 plugin은 자신의 prefix를 가진 code를 정의할 수 있습니다. 예를 들어 `ENUMKIT002`는
enumkit 자체의 validation입니다. core `ZIGO...` validation이 먼저 통과한 뒤 plugin 진단이
실행됩니다. 해결 방법은 해당 [plugin 문서](../plugins/README.md)를 확인하세요.
