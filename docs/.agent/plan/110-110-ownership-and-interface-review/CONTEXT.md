# SCOPE

- `docs/.agent/design/10-ownership-model.md` (new).
- `docs/.agent/design/11-comptime-interfaces.md` (new).
- `docs/.agent/design/README.md` index entries.
- Read-only survey of `src/gen/ir/semantic.zig`, `src/gen/lower.zig`,
  `src/gen/emit/{raw,purego,public,public_types,materialized}.zig`,
  `src/reflect/walk.zig`, and the examples.

# CONTEXT

## Current implementation and bottlenecks

- Ownership today: `SemanticFn.ownership` (borrowed | caller | library),
  `SemanticFn.release` (a function path), `Parameter.retention` (borrowed |
  retained), and `Parameter.injected`. Lowering turns these into
  `AbiFn.release_symbol`, `slice_return_element`, `ret_string`,
  `materialized_return`/`materialized_out`, and `boxed`; each of those is
  consumed by a separate emit path (`raw.writeCgoSliceReturn`,
  `purego.releaseFunction`, `materialized.writeMaterializedReturn`, the handle
  constructors with `runtime.AddCleanup` in `public_types.zig`).
- Validation of ownership is spread over `validate/ownership.zig`
  (`releaseTargetIssue`, `ownedReturnIsWrappable`) and
  `validate/materialized.zig` (`materializedReleaseTargetIssue`), with the
  same "find the release candidate" lookup and different element rules.
- Generics: `walk.zig` reflects a registered generic *instantiation* under a
  unique `.name`; a generic function has no signature and cannot be exposed.
  There is no notion of "these N concrete types share a method set". The
  closest existing feature is the tagged-union sealed interface
  (`ValueVariant`) generated in `public_types.zig`.

## Target structure and invariants

- Ownership: one `Ownership` record on the IR describing who frees what,
  how (release function, handle destructor, no-op copy), and when (after
  copy, on Close, on GC cleanup), so emit paths ask the record rather than
  pattern-match on return shape.
- Interfaces: a registration form that names a Go interface and its
  concrete registered handles, validated so every listed type exposes the
  method set with identical Go signatures.
