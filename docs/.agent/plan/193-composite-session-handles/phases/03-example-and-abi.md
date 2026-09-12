---
depends_on:
- "193-composite-session-handles#2"
perf_phase: false
status: planned
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

## Done When

- `zig build go-check abi-check`가 예제에서 통과하고 abi-check가 차이를 보고하지 않는다.
- `go test ./...`가 예제에서 통과하고, 대조 경로가 `ErrHandleInUse`를 실제로 관측한다.
- 생성 트리가 커밋되어 stale 검사가 깨끗하다.
