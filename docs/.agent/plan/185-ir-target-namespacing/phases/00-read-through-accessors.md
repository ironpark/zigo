---
completed_at: "2026-09-09T09:44:56Z"
perf_phase: false
status: done
---
> DONE-WHEN: Grepping `src` for `go_adapter`, `go_error`, `go_name`, `go_owner`,
> NEXT: none

# Route Go field reads through accessors

## Planned Work

- Add accessors on `semantic.Parameter`, `semantic.SemanticFn` and
  `semantic.TypeDecl` for the Go-specific fields that lack one: `goAdapter()`
  on `Parameter` and `TypeDecl`, and `goName()`, `returnGoAdapter()`,
  `goIterator()` and `goImplements()` on `SemanticFn`. The `go` prefix is not
  decoration: Zig puts a struct's fields and its declarations in one namespace,
  so a method called `iterator()` cannot sit beside the field `iterator`.
  `goOwner()` and `goError()` already exist and stay as they are.
- Add `goOwnerOverride()` for the raw `go_owner` field. `goOwner()` falls back
  to `namespace`, and the constructor scan in `src/gen/validate/functions.zig`
  reads the override alone; giving it the fallback would change behaviour, which
  this phase must not do.
- Replace every direct read of those fields in `src/gen/**` and `src/plugin.zig`
  with the accessor, including `publicFunctionNameAlloc` inside `semantic.zig`
  and the comparisons in `src/gen/abi_diff.zig`.
- Leave the field declarations, the writer sites and the wire format alone.

## Done When

- Grepping `src` for `go_adapter`, `go_error`, `go_name`, `go_owner`,
  `return_go_adapter`, `.iterator` and `.implements` finds no remaining read.
  What is left is `src/gen/ir/semantic.zig`, the five writer sites
  (`src/reflect/walk.zig`, `src/reflect/pairing.zig`, `src/normalize.zig`,
  `src/plugin/rename.zig` and the plugin hooks in `src/gen/validate/validate.zig`),
  the author-facing DSL in `src/declare.zig` and `src/author.zig`,
  `src/features.zig` declaration keys, diagnostic and doc text naming the
  binding spellings, the plugin API's own unrelated `FunctionInfo.go_name`,
  and test literals.
- `zig build test --summary all` passes.
- `git status --short tests examples` is clean: no snapshot moved, because no
  serialized shape changed.
