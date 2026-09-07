# SCOPE

`src/reflect/walk.zig`, `src/reflect/coverage.zig`.

# CONTEXT

## Current implementation and bottlenecks

`selectorContains(declaration, "exclude", path)`와 discovery 루프의 `functionEntryContainsPath` 순회.

## Target structure and invariants

경로 색인은 바인딩당 한 번 comptime에 만들어지고(메모이즈), 조회는 길이 버킷 탐색이다. 중복 경로는 그 전에 ZIGO054로 거부되므로 첫 매칭만 쓴다.
