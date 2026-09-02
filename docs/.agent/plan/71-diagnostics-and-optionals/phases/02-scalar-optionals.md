---
perf_phase: false
status: planned
---
> DONE-WHEN: fixture 골든과 예제 테스트가 cgo·purego에서 통과.
> NEXT: none

# 스칼라·enum·extern struct optional

## Planned Work

- `walk.zig`: optional child를 스칼라·bool·enum·승격 정수·extern struct로 확장. `validate.zig`: 위치 규칙(필드·callback·슬라이스 원소는 거부). `lower.zig`: presence + 값. `emit.zig`: shim(`if (has) x else null`), C 선언, raw cgo·purego, public(`*T` 파라미터, `(T, bool)` 반환, error union 조합).
- 골든 `tests/generator_cases/optional`, 예제(02-errors 또는 09-type-relations)에 사용과 Go 테스트. `abi_diff` breaking 테스트.
- 문서.

## Done When

- fixture 골든과 예제 테스트가 cgo·purego에서 통과.
