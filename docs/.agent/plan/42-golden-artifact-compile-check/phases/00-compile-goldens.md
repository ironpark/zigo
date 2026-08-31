---
completed_at: "2026-08-31T10:37:06Z"
perf_phase: false
status: done
---
> DONE-WHEN: `zig build test`가 네 케이스 모두에서 두 검사를 수행한다.
> NEXT: none

# Compile the goldens

## Planned Work

- `addGeneratorCases`가 케이스마다 골든 `panic.c`를 헤더 경로와 함께
  `zig cc -fsyntax-only`로 검사하는 스텝을 추가한다.
- 같은 방식으로 골든 `shim.zig`를 `zig ast-check`로 검사한다.
- 두 스텝을 `test` 스텝에 연결하고 `test-filter`가 그대로 적용되게 한다.

## Done When

- `zig build test`가 네 케이스 모두에서 두 검사를 수행한다.
- 골든 `panic.c`에서 헤더 include를 지우면 `zig build test`가 실패한다.
