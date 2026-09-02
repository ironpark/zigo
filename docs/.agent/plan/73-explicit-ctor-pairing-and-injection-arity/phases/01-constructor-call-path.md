---
completed_at: "2026-09-02T12:55:02Z"
perf_phase: false
status: done
---
> DONE-WHEN: root 함수 생성자 케이스의 shim이 컴파일되고 Go 테스트가 통과, 골든 갱신, 커밋.
> NEXT: none

# 생성자 Zig 호출 경로 분리

## Planned Work

- `SemanticFn`에서 Go 소유자(`namespace`)와 Zig 호출 경로를 분리한다. `emit.zig:694`의 shim 호출식이 선언 위치 기반 경로를 쓰게 한다.
- root 레벨 `fn new(...) !*Terminal`이 이름 규칙으로 짝지어지는 회귀 테스트(shim이 `target.new(` 생성) 추가.
- semantic.json 스키마 변경 시 abi_diff·모든 예제 semantic.json 재생성.

## Done When

- root 함수 생성자 케이스의 shim이 컴파일되고 Go 테스트가 통과, 골든 갱신, 커밋.
