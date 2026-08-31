# SCOPE

CI가 지목한 Zig source를 `zig fmt`로 정규화한다.

# CONTEXT

## Current implementation and bottlenecks

`src/gen/emit.zig`의 기존 lowering 정리 commit이 formatter 출력과 일치하지 않는다.

## Target structure and invariants

코드 의미는 유지하고 Zig formatter가 만드는 whitespace와 line wrapping만 반영한다.
