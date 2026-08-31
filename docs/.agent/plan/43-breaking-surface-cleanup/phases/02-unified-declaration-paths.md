---
perf_phase: false
status: planned
---
> DONE-WHEN: `bindings.zig`가 선언을 지칭하는 방법이 하나다.
> NEXT: none

# One way to name a declaration

## Planned Work

- 명시 목록과 자동 발견이 같은 경로 문법을 쓰도록 통일한다. `overrides`가 곧 명시 목록이 되며
  "override는 discover 전용" 규칙이 사라진다.
- `specializations`를 `types`로 흡수한다 (`.name`을 선택 필드로).
- `walk.zig`의 중복 순회를 하나로 줄인다.

## Done When

- `bindings.zig`가 선언을 지칭하는 방법이 하나다.
- 예제와 문서가 갱신되고 컴파일 오류 메시지가 새 문법을 안내한다.
