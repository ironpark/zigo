---
perf_phase: false
status: in-progress
---
> DONE-WHEN: 모든 골든 shim.zig가 `std_options` 줄을 담고 `zig build test`가 통과한다.
> NEXT: none

# std_options passthrough

## Planned Work

- `renderShim`이 panic 선언 뒤에 `pub const std_options`를 타겟에서 조건부로 전달한다.
- 타겟에 선언이 없으면 `.{}`로 두어 기존 동작과 같게 한다.
- generator case 골든의 shim.zig를 전부 갱신한다.
- `zig build test`와 examples 빌드로 실제 컴파일을 확인한다.

## Done When

- 모든 골든 shim.zig가 `std_options` 줄을 담고 `zig build test`가 통과한다.
- 타겟 root에 `std_options`를 선언한 예제에서 `logFn`이 실제로 호출된다.
