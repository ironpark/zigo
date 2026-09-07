# SCOPE

`src/reflect/walk.zig`, `src/gen/naming.zig`, `src/gen/validate/names.zig`, `docs/diagnostics.md`, `docs/cheatsheet.md`.

# CONTEXT

## Current implementation and bottlenecks

`walk.zig`는 파라미터마다 `@hasField(param_meta, name)`으로 한 방향만 조회한다. `naming.zig`에는 Go 키워드 목록만 있고 C 목록이 없다.

## Target structure and invariants

`param_meta`의 모든 키는 `params`의 원소여야 한다. C로 나가는 파라미터 이름은 C 키워드가 아니어야 한다.
