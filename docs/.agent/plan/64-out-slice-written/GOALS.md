# GOALS

## Problem and the end result from the user's point of view

`.direction = .out`인 `[]ExternStruct` 파라미터는 지금 공개 계층(`[]T` → `[]TData`)과 cgo raw 계층(`[]TData` → `[]C.x`)에서 두 번 들어가는 복사를 하고, 호출 뒤 같은 경로로 두 번 돌아온다. out 전용이므로 들어가는 복사는 결과에 영향이 없다. shim은 `output_written.* = output_len`으로 고정해 native가 실제로 몇 개를 썼든 전부 되돌아오고, 공개 계층은 반환 타입이 `usize`일 때만 `int(result)`로 다시 자르는 암묵 규칙(`isCountReturn`)을 가진다. 그 결과 "written 이후 원소의 상태"가 계약으로 정의되지 않아 사용자 Zig 코드가 `@memset`으로 무마한다.

작업 후: 스칼라 전용 extern struct 슬라이스는 cgo에서도 purego처럼 캐스트 한 번으로 넘어가고, `.written = .return`을 붙인 out 슬라이스는 native가 반환한 개수만 채워지며 그 뒤 원소는 호출 전 값 그대로임이 문서화된 계약이 된다. 큰 결과를 복사 한 번으로 받는 `…Into(dst)` 패턴이 예제와 문서로 제공된다.

## Measurable goals

- 스칼라 전용 extern struct 슬라이스 파라미터(in/out)의 cgo raw 계층에서 필드별 복사 루프가 사라진다.
- 공개 값 struct의 Go 쪽 레이아웃 단정(크기·필드 오프셋)이 생성되어 캐스트의 근거가 된다.
- `.written = .return` fixture의 shim 골든에 `output_written.* = result`, 공개 골든에 `written`만큼만 되돌리는 처리가 나타난다.
- `.direction = .out` 슬라이스의 공개 계층에 들어가는 복사가 없다.
- `abi_diff`가 `written` `.all` → `.return` 을 non-breaking으로 보고한다.

## Supported scope and non-goals

지원: `.direction = .out`/`.in` `[]ExternStruct` 및 스칼라 슬라이스 파라미터, cgo·purego 양 백엔드, `.written` param_meta, 예제 하나의 `…Into(dst)` 패턴.
비목표: `[]string`·포인터 원소 슬라이스, borrowed 슬라이스 반환의 복사 계약 변경, bool 필드가 있는 struct의 캐스트, 뷰 반환(`.retention = .view` 류) 도입.

## Reference source / commit / license

- 제안 원문: Ultrasync(`native/sync`, `native/extract`) 사용 중 관찰. 본 저장소 내부 작업이며 외부 코드 도입 없음.
- 관련 선행 계획: `61-slice-ownership-and-struct-elements`, `63-error-union-slice-payloads`.

## Completion criteria for the whole plan

- 위 측정 목표를 검증하는 테스트가 모두 있고 통과한다.
- `zig build test`, 예제 10개의 cgo·purego `go test`, 모든 `go-check`·`abi-check` 통과.
- `docs/bindings.md`, `docs/limitations.md`, `docs/generated-code.md` 갱신.
