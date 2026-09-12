---
depends_on:
- "193-composite-session-handles#2"
perf_phase: false
status: in-progress
---
> DONE-WHEN: `zig build go-check abi-check`가 예제에서 통과하고 abi-check가 차이를 보고하지 않는다.
> NEXT: none

# 예제와 ABI 불변 확인

## Planned Work

- `examples/07-event-queue/src/bindings.zig`에 `EventQueue`와 `Stream`을 묶는 세션
  선언을 추가하고 트리를 재생성한다.
- Go 테스트를 추가한다: 세션으로 닫기가 성공하는 경로, 같은 핸들을 순서를 어겨 직접
  닫으면 `ErrHandleInUse`가 나는 대조 경로, 두 번 닫기, 자식이 `nil`인 세션.
- 변경 전후로 `zig build abi-check`를 실행해 C 표면이 그대로임을 확인하고 그 결과를
  phase 기록에 남긴다.
- `staticcheck -checks U1000`이 생성 접근자에 대해 깨끗한지 확인한다.

## Recorded evidence

- 예제 트리에서 바뀐 것은 `src/bindings.zig`, `zigo/semantic.json`(sessions 추가),
  `.zigo-outputs.json`(새 파일 등록), 그리고 새로 생긴 `*_sessions_gen.go`와 Go 테스트뿐입니다.
  헤더(`zigo_event_queue.h`), `shim.zig`, `panic.c`, raw 생성물, handles 생성물은 그대로입니다.
- `zig build abi-check`가 차이를 보고하지 않습니다. `sessions`는 abi-diff가 비교하는 표면이
  아니며, 그 사실 자체가 C 표면이 움직이지 않았다는 증거입니다.
- `staticcheck -checks U1000`이 cgo·purego 두 모듈에서 깨끗합니다.
- `go test -count=1 ./...`가 cgo·purego 두 트리에서 통과하고, 네 개의 세션 테스트가
  순서·멱등성(동시 호출 포함)·`nil` 멤버·`io.Closer` 계약을 실제 핸들로 확인합니다.

## Done When

- `zig build go-check abi-check`가 예제에서 통과하고 abi-check가 차이를 보고하지 않는다.
- `go test ./...`가 예제에서 통과하고, 대조 경로가 `ErrHandleInUse`를 실제로 관측한다.
- 생성 트리가 커밋되어 stale 검사가 깨끗하다.
