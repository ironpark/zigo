---
perf_phase: false
status: planned
---
> DONE-WHEN: 테스트·골든 통과, 전 예제 녹색, 커밋.
> NEXT: none

# 타입 identity

## Planned Work

- `typeNode`와 callback 매칭을 comptime 타입 동일성 기반으로 바꾸고, `zig_path` 충돌 시 semantic.json 유일성을 보장한다.
- 같은 `@typeName`을 가진 두 comptime enum을 등록·사용하는 walk 테스트와 골든 추가. 기존 예제 `go-check` 무변화 확인.

## Done When

- 테스트·골든 통과, 전 예제 녹색, 커밋.
