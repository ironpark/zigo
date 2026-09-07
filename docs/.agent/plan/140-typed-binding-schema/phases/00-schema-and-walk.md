---
perf_phase: false
status: in-progress
---
> DONE-WHEN: `zig build test -Dtest-filter=walk` 통과, `walk.zig`에 선언 대상 `@hasField`가 남지 않는다.
> NEXT: none

# Schema and reflection

## Planned Work

- `src/declare.zig`에 위 스키마를 doc comment와 함께 정의하고 `zigo.define(comptime Binding)`로 바꾼다. 스키마 타입은 `zigo.Binding` 등으로 재수출한다.
- `walk.zig`가 타입 구조체를 직접 읽도록 바꾼다: `.repr` 스위치를 union 스위치로, `param_meta` 블록을 `Param` 필드 대입으로, 이름 참조 해석(`receiver`/`constructs`/`destroys`)을 타입 값→등록 이름 조회로, `.returns` struct, `.methods` 반영(항목 뒤), `.doc` 반영.
- `validateSelectors`·`checkDeclaredPaths`·discovery를 새 필드로 옮긴다. ZIGO057과 `orphanParamMetaKey`를 제거하고 ZIGO027(개수 불일치)은 유지한다.
- `walk.zig`의 테스트 74개를 새 문법으로 옮긴다.

## Done When

- `zig build test -Dtest-filter=walk` 통과, `walk.zig`에 선언 대상 `@hasField`가 남지 않는다.
