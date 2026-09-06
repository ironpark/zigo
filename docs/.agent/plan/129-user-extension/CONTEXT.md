# SCOPE

- `src/gen/emit/*.zig` (names, spelling, imports, struct helpers), `src/reflect/walk.zig`, `src/gen/ir/semantic.zig`, `src/gen/validate/types.zig`, `src/gen/abi_diff.zig`, `src/gen/lower.zig` (castable), cases, examples, docs.

# CONTEXT

## Current implementation and bottlenecks

Helper names are literal strings in emitters; `PublicScope.writeTypeName` spells every type by name; struct mirrors and `zigoTToRaw/FromRaw` are emitted per record; `_gen.go` imports are predicate-based while other files derive imports from the body.

## Target structure and invariants

Generated unexported identifiers: `zigo` prefix always. Adapter: `TypeDecl.go_adapter`, no mirror struct, `zigoTToRaw/FromRaw` delegate to user functions, castable forced false, adapter import added wherever the type is referenced.
