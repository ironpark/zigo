# SCOPE

- 파라미터 목록이 어긋났을 때 무엇을 보고할지의 판정.
- C 선언 비교에서 값 매개변수와 flattened 필드를 같은 선언으로 보는 규칙.
- Go 표면 비교를 Go가 실제로 받는 매개변수 단위로 바꾸는 것.
- 위 세 가지의 회귀 테스트.

# CONTEXT

## Current implementation and bottlenecks

- `exposedParamsMatch`는 semantic `Parameter` 목록을 위치로 짝짓습니다. flatten 파라미터
  하나는 lowered C 매개변수 여럿이고 Go 매개변수 여럿이며, options 파라미터 하나는 C
  매개변수 여럿에 Go 가변 인자 하나입니다. 그래서 목록이 재구성되면 짝이 밀립니다.
- `signatureEqual`은 lowered C 비교와 `goSurfaceEqual`을 함께 봤고, written hint 검사가
  `else if`로 그 C 비교를 가로챘습니다. C 선언이 그대로여도 "(C signature)"를 주장했습니다.
- lowered 비교는 `role`과 `field_index`까지 봅니다. 둘 다 "이 값이 어떻게 여기 왔는가"를
  적는 provenance이고, C 선언 자체(`uint16_t` 대 `uint16_t`)는 같습니다.
- Go 표면 비교도 semantic 파라미터 단위였습니다. 그래서 flatten 필드가 위치를 지키며
  개별 매개변수로 나가는 변경에서 Go 시그니처가 그대로인데도 바뀌었다고 봤습니다.

## Target structure and invariants

- 판정 순서: C 선언 → (어긋난 목록이면) Go 표면 → (목록이 정렬돼 있으면) 주석별 검사.
- 불변: C가 보는 선언이 같으면 C 변경이라고 말하지 않는다. 값은 자기 매개변수로 오든
  flattened 필드로 오든 같은 선언이다.
- 불변: Go 표면 비교는 Go 호출자가 실제로 적는 단위를 센다. flatten은 필드마다 하나,
  options는 가변 인자 하나.
- 불변: 목록이 정렬돼 있으면 기존 주석별 검사가 그대로 동작한다.
