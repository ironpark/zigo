# SCOPE

`src/reflect/walk.zig`, `src/gen/emit.zig`, `tests/generator_cases/root_constructor`, `docs/bindings.md`, `CHANGELOG.md`.

# CONTEXT

## Current implementation and bottlenecks

`receiverName`은 `info.params[0]`만 검사하고 `first_param`은 receiver가 0번일 때만 1이다. emit은 `self`를 항상 첫 인자로 쓴다.

## Target structure and invariants

receiver = 주입 파라미터를 건너뛴 첫 파라미터. shim 호출은 Zig 선언 순서대로 주입값·self·나머지를 섞어 낸다.
