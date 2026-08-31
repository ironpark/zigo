---
completed_at: "2026-08-31T10:11:04Z"
depends_on:
- "41-extern-struct-value-params#0"
perf_phase: false
status: done
---
> DONE-WHEN: generator case 골든 트리에 헤더·shim 산출물이 고정된다.
> NEXT: none

# Lowering and native emitters

## Planned Work

- `value_struct` 파라미터를 `const T*`로, 반환·out을 `T*`로 내리는 규칙을 lower에 넣는다.
  분해는 전부 lower에서 끝내고 emitter는 `AbiFn`만 읽는다.
- C 헤더에 extern struct 미러와 필드를 낸다. Zig shim이 포인터를 역참조해 원래 함수를 호출하고
  기존 null guard와 panic 경계 계약을 지킨다.

## Done When

- generator case 골든 트리에 헤더·shim 산출물이 고정된다.
- null 포인터와 Zig panic이 기존 상태 코드로 보고된다.
