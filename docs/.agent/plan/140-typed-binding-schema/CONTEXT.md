# SCOPE

`src/root.zig`(define), 새 `src/declare.zig`(스키마), `src/reflect/walk.zig`, `coverage.zig`, `packages.zig`와 그 테스트, `tests/generator_cases`, `examples/*/src/bindings.zig`, `docs/`, `CHANGELOG.md`.

# CONTEXT

## Current implementation and bottlenecks

카탈로그 §1–§7. 읽기는 `walk.zig`의 `@hasField(@TypeOf(metadata|entry|declaration), ...)` 약 40곳, `packages.zig`, `coverage.zig`.

## Target structure and invariants

스키마(점검 확정):
- `Binding{ root: type, allocator: ?Injection, io: ?Injection, discover: ?enum{public,recursive}, exclude: []const []const u8, codepoints, strings, string_release: ?[]const u8, types: []const Type, functions: []const Function, methods: []const Methods, packages: []const Package, interfaces: []const Interface }`. `Injection = union(enum){ c_allocator, page_allocator, smp_allocator, path: []const u8 }`로 allocator·io가 같은 형식.
- `Type = union(enum){ handle: Handle, value: Value, materialized: Value, enumeration: Enum, tagged_union: TaggedUnion, callback: Callback }`. variant가 `.repr`을 대체하고 repr별 키는 그 payload에만 있다. `Handle{ type, name, doc, fields: []const HandleField }`, `Value{ type, name, doc, go: ?GoAdapter, fields: []const ValueField{ name, semantic } }`, `Enum{ type, name, doc, text, exhaustive, go, covers }`, `TaggedUnion{ type, name, doc, access, omit: []const []const u8 }`, `Callback{ type, name(필수), doc, params: []const Param, returns: Returns, userdata: union(enum){ first, last, index: usize }, retention, reentrancy, thread, on_callback_failure }`.
- `Function{ path, name, doc, params: []const Param, returns: Returns, receiver: ?type, constructs: ?type, destroys: ?type, child_of_receiver, iterator: ?Iterator, cancel: ?Cancel, covers: []const []const u8 }`. `Returns{ ownership: ?Ownership, semantic, release, go }` (단축형 없음). `Methods{ receiver: type, strip_prefix: []const u8 = "", functions: []const Function }`.
- `Param{ name: ?[]const u8, semantic, direction, written: ?enum{all, result}, buffer, flatten, retention, go_error, on_callback_failure, reentrancy, thread, userdata: ?struct{ param }, go }`. 이름이 없으면 소스 보강·`p<n>` fallback. 위치 기반이라 고아 키가 생길 수 없고 ZIGO057은 제거된다.
- Zig 쪽 참조는 값(`receiver`, `constructs`, `destroys`, `interfaces.types`), Go 이름과 선언 경로만 문자열. `.name`은 어디서나 "Go 이름".
- `.doc`은 Type·Function에서 실제로 읽어 생성 GoDoc을 덮어쓴다.
- 모르는 키·잘못된 자리의 키는 Zig의 네이티브 컴파일 에러. 별도 안내 메시지는 두지 않는다.
