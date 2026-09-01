---
perf_phase: false
status: planned
---
> DONE-WHEN: `[*:0]const u8` parameters and returns generate and pass on cgo and purego;
> NEXT: none

# Sentinel byte pointers

## Planned Work

- reflect: accept `.many` pointers whose child is `u8` and whose sentinel is
  `0`, in const form (`[*:0]const u8`), producing a type node that lowers to
  `const char*`. Decide between a dedicated node (e.g. `.c_string`) and a slice
  node tagged with the existing `c_string` semantic hint; record the choice in
  `02-ir-spec.md`. Any other many-pointer stays a `@compileError` with the
  current message extended to name the supported form.
- lower/emit: parameter → `const char*` (cgo `C.CString` + free after call;
  purego NUL-terminated `[]byte` copy pinned for the call), Go public `string`.
  Return → `const char*`, copied with `C.GoString` / `strlen`+copy into a Go
  `string`. Reject non-const or mutable `[*:0]u8` with a diagnostic.
- abi_diff: signature equality covers the new node.
- Generator case and example coverage on both backends; implement the
  `[*:0]const u8` row of `03-lowering-rules.md` §3 as written.

## Done When

- `[*:0]const u8` parameters and returns generate and pass on cgo and purego;
  other many-pointers still fail reflection with a clear message; IR spec, docs,
  and goldens updated; committed.
