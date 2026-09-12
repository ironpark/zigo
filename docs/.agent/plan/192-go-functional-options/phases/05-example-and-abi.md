---
depends_on:
- "192-go-functional-options#4"
perf_phase: false
status: in-progress
---
> DONE-WHEN: `zig build go-check abi-check`가 예제에서 통과하고 abi-check가 차이를 보고하지 않는다.
> NEXT: none

# 예제와 ABI 불변 확인

## Planned Work

- `examples/07-event-queue/src/bindings.zig`의 `Terminal.init`을
  `zigo.param.options`로 바꾸고 트리를 재생성한다.
- Go 테스트에 옵션을 생략한 호출, 일부만 준 호출, 전부 준 호출을 추가하고 기본값
  24와 1 MiB가 실제로 적용되는지 확인한다.
- 변경 전후로 `zig build abi-check`를 실행해 C 표면이 그대로임을 확인하고,
  그 결과를 phase 기록에 남긴다.
- `.prefix = ""`를 쓰는 선언을 예제나 테스트 중 한 곳에서 실행한다.

## Done When

- `zig build go-check abi-check`가 예제에서 통과하고 abi-check가 차이를 보고하지 않는다.
- `go test ./...`가 예제에서 통과한다.
- 생성 트리가 커밋되어 stale 검사가 깨끗하다.
