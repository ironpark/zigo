# SCOPE

Changed: `src/gen/ir/semantic.zig` (the namespace types, accessors and the
version-1 migration), its readers in `src/gen/lower.zig`, `src/gen/abi_diff.zig`,
`src/gen/emit/**`, `src/gen/validate/**` and `src/plugin.zig`, and its writers in
`src/reflect/walk.zig`, `src/normalize.zig`, `src/reflect/pairing.zig` and
`src/plugin/rename.zig`.

Regenerated: the 104 `semantic.json` snapshots under `tests/` and `examples/`.

Untouched: `src/declare.zig`, `src/author.zig`, `src/root.zig`, `src/gen/naming.zig`,
the C shim and header emitters, and every generated Go source file.

# CONTEXT

## Current implementation and bottlenecks

`Semantic` is serialized by `std.json.Stringify` straight off the Zig field names
with `emit_null_optional_fields = false`, so the Zig struct shape *is* the wire
format. Renaming or nesting a field changes `semantic.json`, and there are 104 of
those snapshots plus 74 generator cases whose expected trees include them.

Two levers already exist. `Semantic.ir_version: u32 = 1` is declared but never
read, so nothing consumes it yet and it is free to bump. `Extensions` shows the
shape a namespace takes here: one object per owner, absent when empty, so a
document that never uses it serializes exactly as before.

The Go fields are read in many places but written in only five:
`src/reflect/walk.zig` (comptime reflection of the binding), `src/normalize.zig`
(the normalized declaration path), `src/reflect/pairing.zig` (`go_owner` for a
paired constructor), `src/plugin/rename.zig` (rewriting `go_owner`) and
`src/gen/validate/validate.zig`, where the `map_type` and rename plugin hooks
write an adapter or a name back onto the document. Narrowing readers to
accessors first therefore leaves a small, known set of assignment sites to move.

`src/gen/abi_diff.zig` compares `go_name`, `return_go_adapter`, per-parameter
adapters and `iterator` between two documents. It is the one reader whose
behaviour is a contract in its own right, so it is verified separately.

## Target structure and invariants

`semantic.zig` gains three namespace structs holding what only the Go backend
reads:

- `ParamGo { adapter, callback_error }` on `Parameter.go`
- `FnGo { name, owner, return_adapter, iterator, implements }` on `SemanticFn.go`
- `TypeGo { adapter }` on `TypeDecl.go`

Invariants:

- Each `go` field is optional and omitted when every member is absent, so a
  binding that uses no Go-specific knob produces a document with no `go` object
  at all.
- Every read goes through an accessor on the owning declaration
  (`goAdapter()`, `goName()`, `returnGoAdapter()`, and the existing `goOwner()`
  and `goError()`), so a later target can add a sibling namespace without
  touching readers again.
- `Semantic.parse` accepts `ir_version` 1 and 2. A version-1 document is lifted
  into the nested shape while parsing; `serialize` only ever writes version 2.
- The C ABI is not involved. No shim, header, symbol or generated Go source
  changes, which is what makes byte-identical generator-case output the check.
