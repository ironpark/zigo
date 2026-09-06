# SCOPE

- `src/reflect/walk.zig`: receiver resolution, `receiver_by_value`, symbol
  naming, coverage pairing.
- `src/gen/ir/semantic.zig`: a receiver kind on the function record and in
  `semantic.json`.
- `src/gen/validate/`: `functions.zig` (ownership metadata, iterator, stream),
  `names.zig` (generated enum methods as reserved names), `types.zig` (`.go`
  adapter), `packages.zig` (co-location already holds).
- `src/gen/emit/public.zig`, `shim.zig`, `raw.zig`, `purego.zig`: value-receiver
  method emission.
- `src/gen/abi_diff.zig`, `src/gen/report.zig`, `src/reflect/coverage.zig`.
- `docs/bindings-functions.md`, `docs/bindings-types.md`, `docs/diagnostics.md`,
  `docs/cheatsheet.md`, `CHANGELOG.md`.
- `tests/generator_cases/`, `tests/fixtures/`.

Not touched: handle lifecycle, materialized layout, callback machinery.

# CONTEXT

## Current implementation and bottlenecks

`receiverNameAt` (`walk.zig:2028`) returns a name only for a pointer to a handle
repr or an `.@"opaque"` struct by value, so an enum first parameter is simply a
normal parameter and the function stays a package-level function.

Everything downstream reads `receiver != null` as "there is a handle":

- `emit/public.zig:408` prints `func (x *T)` unconditionally.
- `emit/public.zig:828` sets `needs_handle_check` from `receiver != null`.
- `emit/public.zig:1154` and `:1293` walk the receiver's retained callback slots.
- `validate/functions.zig:69` requires a receiver for a borrowed return, and the
  stream check at `:578` re-fetches the stream from the receiver.
- `emit/shim.zig:876` passes `self` or `self.*` depending on `receiver_by_value`,
  which today means "opaque struct taken by value", not "not a handle".

## Target structure and invariants

The function record grows a receiver *kind* (`handle` or `value`) instead of
inferring it. `receiver_by_value` keeps its current meaning (how the shim spells
the argument); the new field answers "is there a handle at all". Every site
listed above switches from `receiver != null` to `receiverIsHandle()`.

Invariants:

- A value receiver never participates in handle lifetime: no acquire/release, no
  parent, no `ErrInvalidHandle`, no callback slot sweep.
- A value receiver crosses the C ABI as the parameter it already was; the symbol
  name is `prefix_<Receiver>_<name>`, so moving an existing free function under a
  receiver is an ABI change and `abi-check` must report it.
- Methods live in their type's package, which the existing ZIGO031 rule already
  enforces.
