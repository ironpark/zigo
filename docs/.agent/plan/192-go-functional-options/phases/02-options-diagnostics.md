---
depends_on:
- "192-go-functional-options#1"
perf_phase: false
status: planned
---
> DONE-WHEN: 세 규칙이 각각 오류 진단을 내고 hint가 고치는 방법을 말한다.
> NEXT: none

# 옵션 계약 진단

## Planned Work

- `src/gen/validate/functions.zig`의 flatten 검증 옆에 옵션 규칙을 추가한다.
  기본값이 없는 필드를 옵션으로 지정하면 오류이며, 메시지는 그 필드에 Zig 기본값을
  주거나 위치 인자로 두라고 안내한다.
- 옵션 매개변수가 하나의 함수에 둘 이상 오는 경우를 거절한다. Go 가변 인자는 하나뿐이다.
- 옵션 필드가 하나도 없는 선언(선택 필드 전부가 기본값 없음)을 거절한다.
- 새 진단 코드를 `docs/reference/diagnostics.md`에 등록한다.
- 각 규칙의 단위 테스트를 추가한다.

## Done When

- 세 규칙이 각각 오류 진단을 내고 hint가 고치는 방법을 말한다.
- 유효한 선언은 진단 없이 통과한다.
- 새 코드가 진단 문서에 있다.
