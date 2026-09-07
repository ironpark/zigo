# SCOPE

- `src/gen/emit/public_writers.zig`: `callbackNeedsAdapter`, `writeCallbackAdapter`.
- `src/gen/emit/public_runtime.zig`: the two adapter call sites.
- `src/gen/lower/ownership.zig`: `typeCanBeBorrowed` also counts callback parameters.
- `tests/generator_cases/callback_enum_handle{,_purego}/expected`: goldens.
- `examples/04-callback`: Zig API, bindings, Go tests.
- `docs/bindings-callbacks.md`, `CHANGELOG.md`.

# CONTEXT

## Current implementation and bottlenecks

`callbackNeedsAdapter` only reports packed values, `bool`, and codepoints. When it is
false the constructor converts the user's function to the public spelling and stores it,
so any position whose public and raw spellings differ (enum, handle pointer) mismatches
the raw layer's type assertion. `writeCallbackAdapter` writes `p{n}` verbatim for enums
and pointers. `zigoNewBorrowed<T>` is only emitted when `lifecycle.can_be_borrowed`,
which today is set only by borrowed-view returns.

## Target structure and invariants

- The adapter is the single place where public and raw spellings are reconciled; any
  position whose raw Go type differs from its public Go type forces an adapter.
- Enums cross through `writeEnumFromRaw`/`writeEnumToRaw`, so `.go` adapters keep working.
- A handle parameter becomes `zigoNewBorrowed<T>(p, nil)`; a nullable one maps `nil` to a
  nil `*T`. The type's lifecycle marks it `can_be_borrowed` so the helper exists.
