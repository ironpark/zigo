---
completed_at: "2026-09-02T11:03:38Z"
perf_phase: false
status: done
---
> DONE-WHEN: fixture·예제 테스트 통과, 기존 골든 불변.
> NEXT: none

# callback의 Go error 표면화

## Planned Work

- `param_meta.<cb>.go_error`, semantic.json 필드, 검증(Zig 반환 i32 필수). 트램폴린·dispatcher의 `-5`와 state 저장, 공개 래퍼의 `CallbackError`. retained callback의 지연 반환.
- 04-callback 예제에 사용과 Go 테스트(cgo·purego). 문서.

## Implementation Notes

`semantic.Parameter.go_error: ?bool`(기본 null이라 기존 `semantic.json`이 그대로다),
`ZIGO025`(콜백이 아닌 자리이거나 Zig 반환이 `i32`가 아니면 거부), 트램폴린·dispatcher의
`-5`, 공개 `*CallbackError`/`ErrCallbackFailed`, `zigoCallbackError` 헬퍼.

**`go_error`는 파라미터가 아니라 ABI 시그니처의 성질로 구현했다.** 한 바인딩 안에서 Go
콜백 타입은 시그니처마다 하나이고 purego dispatcher도 시그니처마다 하나다. dispatcher
하나가 `func(i32) i32`와 `func(i32) (i32, error)`를 동시에 단정할 수는 없으므로, 한
파라미터에 켜면 그 시그니처 전체가 켜진다(`callbackSignatureHasGoError`). 파라미터마다
따로 두면 같은 Go 타입 이름에 두 가지 시그니처가 생기는 모순이 나온다.

**저장 자리를 스트림과 공유했다.** 커밋 4678afb가 콜백 전용 레지스트리에서 스트림 error
필드를 뺐던 경계를 다시 그었다: 필드는 "스트림이 있거나 `go_error` 콜백이 있을 때" 나오고,
`recordErr`는 하나이며, 가져가는 함수만 `TakeStreamError`/`TakeCallbackError`로 갈린다.
purego의 `streamErr` 필드는 이제 두 쪽이 쓰므로 `goErr`로 바꿨다(스트림 골든의 raw 파일
주석·필드명만 바뀜, 생성 로직 불변).

`abi-diff`에 `callback Go error surface changed`를 breaking으로 추가했다. C 시그니처는
그대로지만 Go 콜백 타입이 바뀌어 호출자의 함수 리터럴이 컴파일되지 않기 때문이다.

생성자 경로에서 콜백 error로 조기 반환할 때 이미 등록한 retained handle을 해제한다 —
상태 코드 검사가 하던 것과 같다.

골든 fixture `tests/generator_cases/callback_error{,_purego}`(retained 생성자, 그 handle의
메서드, borrowed 자유 함수)를 추가했다. C 헤더·shim은 `go_error` 없는 경우와 동일하다.

## Done When

- fixture·예제 테스트 통과, 기존 골든 불변.
