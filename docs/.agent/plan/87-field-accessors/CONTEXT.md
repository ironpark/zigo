# SCOPE

- Metadata: `.fields` on a `.repr = .@"opaque"` entry. Entry fields: `path` (required), `name` (optional), `set` (default false), `doc` (optional).
- Reflect: resolve the path at comptime; each hop must be a struct field; the final type must be bool, int (widths already supported by `abi.promotedIntBits`), float, or an enum registered in `.types`. Synthesize semantic functions `<Type>.<name>` (getter) and `<Type>.set<Name>` (setter) with receiver `*const T` / `*T`, marked so emit generates shim bodies that read/write via the path instead of calling a Zig function.
- Shim: `pub export fn zg_<type>_<name>(self: *const T) C { return self.<path>; }` and the setter equivalent, with enum/bool conversion consistent with existing scalar lowering.
- Go: methods on the handle with the usual lifecycle guard (closed/poisoned checks) like any other method.

# CONTEXT

## Current implementation and bottlenecks

- `walk.zig` builds `semantic.SemanticFn` only from declared functions found via `.functions` or discovery; there is no field concept.
- `emit.zig` `renderShim` writes a call into the user function for each semantic function; a field accessor needs an alternate body.
- `bindings.zig` comments in downstream projects say "zigo binds functions, not fields".

## Target structure and invariants

- Field accessors are ordinary functions after reflection except for how the shim body is written, so every later stage (validation, naming, packages, lifecycle) treats them uniformly.
- A getter never fails, so it returns the scalar directly (no status out-parameter) on the C side while keeping the Go signature consistent with other scalar-returning methods in this generator (follow whatever plain scalar methods do today).
