---
perf_phase: false
status: in-progress
---
> DONE-WHEN: fixture가 거부되고 `.name` 부여 fixture는 통과한다.
> NEXT: none

# 공개 Go 이름 충돌 진단

## Planned Work

- `validate.zig`: 공개 함수·메서드·타입·enum tag·callback 타입 이름 집합 검사, 새 진단 코드. fixture: 두 네임스페이스의 같은 이름 함수, 타입과 함수의 같은 이름, `.name`으로 해결되는 케이스.
- `docs/bindings.md` 이름 규칙 절, `limitations.md` 진단 목록.

## Done When

- fixture가 거부되고 `.name` 부여 fixture는 통과한다.
