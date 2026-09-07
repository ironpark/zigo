# SCOPE

`src/reflect/walk.zig`, `src/reflect/coverage.zig`, `examples/08-telemetry-hub` 생성물, `CHANGELOG.md`, `docs/`.

# CONTEXT

## Current implementation and bottlenecks

`discoverContainer`가 함수마다 comptime 색인을 조회하고, 매칭된 항목을 `appendDiscoveredEntry`로 넘긴다.

## Target structure and invariants

`checkDeclaredPaths`가 listed/excluded 집합을 돌려주고, discovery는 그 집합으로 건너뛸지만 결정한다. 목록 항목은 `appendSelectedEntry`로 반영된다. 존재하지 않는 경로는 comptime 검증이, 중복·충돌은 ZIGO054가 이미 막으므로 두 패스의 합집합은 이전과 같다.
