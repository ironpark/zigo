# SCOPE

- Keep the semantic.json contract untouched; all new facts live in the lowered `abi.Program` which is in-memory only, unless `abi_diff` already serialises `abi.Program` (check first and keep its JSON stable by marking new fields as non-serialised or by deriving them on load).

# CONTEXT

## Current implementation and bottlenecks

- `lower.zig` builds `abi.Program` from `semantic.Semantic`; `emit.zig` consumes it and re-derives the facts above.
- Slot ordering rule today: for a given owner type, iterate functions in program order, then retained callback params in parameter order.

## Target structure and invariants

- Every ABI fact is computed once in lowering; the emitter is a pure renderer of `abi.Program`.
- The slot ordering rule is preserved exactly so generated code does not change.
