---
completed_at: "2026-09-12T05:06:53Z"
perf_phase: false
status: done
---
> DONE-WHEN: `zig build test`가 통과하고, 옵션 검증 테스트가 새 hint 문구를 확인한다.
> NEXT: none

# 혼합 시그니처 관용구와 hint 정정

## Planned Work

- `src/gen/validate/functions.zig:212`의 `ZIGO061` hint를 실행 가능한 해법으로 고칩니다.
  기본값을 주거나, 그 값을 옵션 구조체가 아니라 함수의 별도 매개변수로 옮기라고 안내하고,
  `.options` 안에서 할 수 없는 "positional parameter" 표현을 지웁니다.
- 그 hint와 진단 문구를 단언하는 `src/gen/validate/functions.zig`의 옵션 검증 테스트를 새
  문구로 갱신합니다.
- `docs/authoring/values-and-data.md`의 옵션 절에 규칙을 명시합니다: 옵션 구조체의 모든
  필드는 기본값을 가져야 하고, 필수 값은 구조체가 아니라 함수 매개변수로 둡니다. 혼합 예
  (`init(gpa, initial_cols: u16, options: TerminalOptions)` →
  `NewTerminal(initialCols uint16, opts ...Option)`)와, 구조체 안의 기본값 없는 필드가 왜
  거절되는지(shim이 flattened 필드만으로 구조체를 재조립한다)를 함께 적습니다.
- `docs/reference/diagnostics.md`의 `ZIGO061` 행을 새 hint와 맞춥니다.
- `docs/reference/generated-go-api.md`의 functional options 절에 위치 인자와 함께 나오는
  시그니처 형태를 추가합니다.
- `examples/07-event-queue/src/root.zig`의 `TerminalOptions`에서 `cols`를 빼고
  `init(gpa, initial_cols: u16, options: TerminalOptions)`로 되돌립니다. 필수 값을 다시
  함수 매개변수로 올려 GOALS(`192`)가 그린 모양을 실제로 만듭니다.
- `examples/07-event-queue/src/bindings.zig`를 인덱스와 필드 목록에 맞게 고치고 트리를
  재생성합니다.
- `examples/07-event-queue/go{,/-purego}/event_queue/value_struct_test.go`를 새 시그니처로
  갱신하고, 옵션을 생략한 호출에서 `rows` 24와 1 MiB 기본값이 그대로 적용되는지 유지합니다.
- C 표면 변화의 성격을 측정해 기록합니다. flatten은 구조체 필드를 각각 ABI 매개변수로
  내리므로 필수 필드를 매개변수로 옮겨도 타입·순서·개수는 그대로이고 C 매개변수 이름만
  `cols` → `initial_cols`로 바뀝니다(`Terminal.cols`와의 Zig 이름 충돌 때문에 이름은 바뀔
  수밖에 없습니다). 헤더·shim·panic.c diff를 근거로 남깁니다.

## Done When

- `zig build test`가 통과하고, 옵션 검증 테스트가 새 hint 문구를 확인한다.
- 07 예제에서 `zig build go-check`와 `go test ./...`(cgo·purego)가 통과한다.
- 생성 시그니처가 `func NewTerminal(initialCols uint16, opts ...Option) (*Terminal, error)`이고
  옵션 타입에 `cols` 필드가 없다.
- C 표면은 심볼·매개변수 타입·순서·개수가 그대로이고 매개변수 이름만 바뀐다. 헤더·shim·
  panic.c diff가 그 사실을 보여준다.
- 옵션을 주지 않은 호출이 `initial_cols` 위치 인자와 Zig 기본값(`rows` 24,
  `max_scrollback_bytes` 1 MiB)을 그대로 네이티브로 보낸다.
- 커밋 뒤 `zig build abi-check`가 기준선(`abi_base = "HEAD"`)과 비교해 차이를 보고하지 않는다.
  작업 트리 상태에서 이 단계가 breaking을 보고하는 것은 커밋된 계약과 비교하기 때문이며,
  허용된 계약 변경을 커밋으로 확정하는 것이 이 예제의 기준선 규칙입니다.
- 문서 세 곳의 선언 조각과 생성 Go가 실제 결과와 일치하고 링크 검사가 깨끗하다.
