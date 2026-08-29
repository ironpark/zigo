---
description: Generate Go bindings from Zig libraries via comptime reflection, wired as a build.zig dependency
plan_status: in-progress
registered_at: "2026-08-29T03:54:30Z"
---
> NEXT: Rewrite `build.zig` as zigo's public API and stand up `examples/01-scalar` as its first ([Phase 0](phases/00-build-api-skeleton.md))

# Phases

- [x] [Phase 00: Build API skeleton and test harness](phases/00-build-api-skeleton.md)
- [x] [Phase 01: Semantic IR types and error lock](phases/01-ir-types.md)
- [x] [Phase 02: Reflector over scalar declarations](phases/02-reflector-scalars.md)
- [x] [Phase 03: Generator emitting scalar bindings](phases/03-generator-scalars.md)
- [x] [Phase 04: Vertical slice: Go calls Zig](phases/04-vertical-slice.md)
- [x] [Phase 05: Error unions and slices](phases/05-errors-and-slices.md)
- [x] [Phase 06: Opaque handles and lifetimes](phases/06-opaque-lifecycle.md)
- [x] [Phase 07: Parameter names and semantic metadata](phases/07-names-and-metadata.md)
- [x] [Phase 08: Diagnostics completed](phases/08-diagnostics.md)
- [ ] [Phase 09: Source sync check and ABI diff](phases/09-sync-and-abi-diff.md)
- [ ] [Phase 10: Generic specialization and callbacks](phases/10-generics-and-callbacks.md)
- [ ] [Phase 11: Hardening and release readiness](phases/11-hardening.md)

# Shared Verification

Layer by layer:

- Reflector: golden JSON. This doubles as the detector for `@typeInfo` shape changes
  across Zig versions.
- Validate and lower: IR fixture in, IR golden out, plus a snapshot per rejection.
- Emitters: golden output files.
- Build API: the four examples consume zigo as a real dependency, which is the only way
  to test `addGoBindings` honestly.
- Integration: `go test` in each example.
- Memory: a counting allocator asserts zero live bytes after create/destroy loops.
- Performance: a cgo call-overhead benchmark recorded in CI.

Because `zigo-gen` is a pure function from IR to files, the first three layers run
without a Zig project, which keeps the majority of the test suite fast and hermetic.

# Decisions That Constrain Ordering

Phases 0 through 4 are strictly sequential and form the vertical slice: nothing is
proven until Go actually calls Zig, so this path is kept as thin as possible and no
feature work happens before phase 4 lands.

Phase 0 pairs the public build API with a real example consumer rather than designing
the API in isolation, because the signature cannot be corrected later without breaking
every consumer.

Phases 5, 6 and 7 widen type coverage and each depend on the previous one only through
shared lowering code; they are ordered by how much later work depends on them — error
handling first because every fallible function needs it, then handles, then naming.

Phase 8 collects diagnostics after the features exist, since a rejection cannot be
written before the path it rejects.

Phase 9 requires stable serialization from phase 1 and the full feature set, because a
diff over an unstable document reports noise.

Phase 10 comes late: generics need naming from phase 7, and callbacks need the handle
lifetime rules from phase 6.

Phase 11 closes out cross-cutting work that only makes sense once every artifact exists.

# Next Implementation Target

Rewrite `build.zig` as zigo's public API and stand up `examples/01-scalar` as its first
