# SCOPE

declare/author/normalize DSL, reflect walk·names, shim emitter, docs, tests.

# CONTEXT

## Current implementation and bottlenecks

- `HandleField`(declare.zig:255)에 ext 없음; `appendFieldAccessors`(walk.zig:254)가 ext를 싣지 않음.
- `supportedFieldLeaf`(walk.zig:379)가 scalar만 허용; `writeFieldAccess`(shim.zig:321)가 scalar 반환만 씀.
- `scanMembers`(names.zig:481)가 컨테이너 init인 var decl만 따라감; field_access init(alias)은 건너뜀.
- `functionSymbolAlloc`(walk.zig:986)이 `receiver orelse discovered_owner` + Go 이름으로 심볼을 만들어 `.named("keyFromASCII")` 시 중복.
- `scanSource` 미방문 fn proto fallback이 이름+arity만 검사(names.zig:444, 575-584).

## Target structure and invariants

플러그인 옵션은 SemanticFn.ext 하나로 흐른다. 필드 getter는 ownership borrowed, 반환 규약은 함수와 동일.
alias는 파일 간 지속되는 맵으로 해석. `.symbol`은 opt-in. fallback 게이트는 reflection이 기록한 `owner_generic`.
