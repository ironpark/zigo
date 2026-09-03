# SCOPE

- Only registered `.repr = .@"opaque"` types qualify; plain structs keep ZIGO003.

# CONTEXT

## Current implementation and bottlenecks

- `receiverNameAt` returns null unless the parameter is a single pointer to a registered handle; `typeNode`'s struct branch turns the by-value struct into an unregistered value struct and validation rejects it.

## Target structure and invariants

- The semantic parameter type stays `opaque_ptr` with a `by_value: bool` marker (or equivalent) so every later stage treats it as a handle; only the shim call differs.
