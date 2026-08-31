---
depends_on:
- "43-breaking-surface-cleanup#2"
perf_phase: false
status: in-progress
---
> DONE-WHEN: 두 union 표현이 같은 축의 값으로 표현된다.
> NEXT: none

# Separate type kind from access strategy

## Planned Work

- `repr`을 타입 종류로 두고 접근 전략을 별도 필드로 분리한다
  (union은 projection 또는 snapshot).
- semantic IR의 `union_repr`을 새 축에 맞춘다. ABI diff의 repr 판정도 따라간다.
- 앞으로 접근 전략이 늘어도 이름이 곱해지지 않음을 문서로 못박는다.

## Done When

- 두 union 표현이 같은 축의 값으로 표현된다.
- 기존 생성물의 심볼과 Go API가 바뀌지 않는다.
