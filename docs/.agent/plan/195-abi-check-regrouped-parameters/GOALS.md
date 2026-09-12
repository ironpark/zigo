# GOALS

## Problem and the end result from the user's point of view

옵션 구조체의 필드를 구조체 밖 매개변수로 옮기면 C 선언은 타입·순서·개수가 그대로인데도
`abi-check`가 다음을 한꺼번에 보고했습니다.

```text
BREAKING: Terminal.init: parameter written hint changed (C signature)
BREAKING: Terminal.init: parameter retention changed
BREAKING: Terminal.init: Go adapter changed
BREAKING: Terminal.init: callback Go error surface changed
ABI COMPATIBLE: Terminal.init: callback failure result changed
ABI COMPATIBLE: Terminal.init: stream staging buffer resized
```

여섯 줄 모두 실제로 일어나지 않은 일입니다. 파라미터별 검사가 semantic 파라미터 목록을
위치로 짝지어 비교하는데, flatten/options 파라미터는 하나이면서 lowered 토큰은 여럿이라
목록이 재구성되면 짝이 어긋나 모든 주석이 동시에 바뀐 것처럼 보입니다. 정작 소비자가 겪는
변화(Go 호출부가 인자를 하나 더 적어야 함)는 어디에도 적히지 않았습니다.

이 계획이 끝나면 같은 변경이 한 줄로 보고됩니다.

```text
BREAKING: Terminal.init: Go parameter surface changed
```

C 선언까지 그대로이고 Go 표면만 바뀌는 변경은 그렇게 말하고, 재구성이 Go 표면도 바꾸지
않으면 아무것도 보고하지 않습니다.

## Measurable goals

- 옵션 구조체의 필드가 구조체 밖 매개변수로 나가는 변경에 대해 보고가 정확히 한 줄이고,
  그 내용이 `Go parameter surface changed`다.
- flattened 필드가 위치와 타입을 유지한 채 개별 매개변수로 나가는 변경은 보고가 0줄이다.
  (C 선언도 Go가 보는 매개변수 목록도 그대로이므로 소비자가 바꿀 것이 없습니다.)
- 기존 진단 어휘와 스냅샷은 그대로다. `signature changed`, `parameter written hint changed
  (C signature)`, `parameter retention changed`, `Go adapter changed`, `callback Go error
  surface changed`, `callback failure result changed`, `stream staging buffer resized`가
  각각의 실제 변경에서 계속 나온다.

## Supported scope and non-goals

지원 범위는 `src/gen/abi_diff.zig`의 파라미터 비교와 그 테스트입니다.

non-goal:

- lowering, emitter, semantic IR의 변경. 어떤 문서가 어떤 C 선언을 만드는지는 그대로입니다.
- 진단 어휘의 개편. 새 메시지 하나(`Go parameter surface changed`)만 추가합니다.
- C 선언이 같고 Go 표면만 다른 **모든** 경우를 잡는 것. 여기서 다루는 것은 파라미터 목록의
  재구성이며, 그 밖의 Go 표면 변경은 기존 검사가 맡습니다.

## Reference source / commit / license

외부 소스를 가져오지 않습니다. 저장소 안의 기존 구현을 참조합니다.

- `src/gen/abi_diff.zig` -- `exposedParamsMatch`(위치 기반 zip), `signatureEqual`(C와 Go를
  함께 보던 비교), `goSurfaceEqual`
- `src/gen/ir/abi.zig` -- `AbiParam.Role`(C가 보는 선언의 역할)
- `examples/07-event-queue` -- 실제로 이 재구성을 한 예제

## Completion criteria for the whole plan

phase가 done이고, `zig build test`와 예제의 `go-check`/`abi-check`가 통과하며, 위 Measurable
goals의 세 경우가 테스트로 고정되어 있습니다.
