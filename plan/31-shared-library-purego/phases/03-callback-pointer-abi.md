---
depends_on:
- "31-shared-library-purego#2"
perf_phase: false
status: planned
---
> DONE-WHEN: Header, Zig shim, symbol-table, ABI snapshot, and negative signature tests prove the callback ABI is
> NEXT: none

# Callback Function-Pointer ABI

## Planned Work

- Introduce purego-specific callback lowering with an explicit C function pointer plus userdata,
  generated C typedefs, and Zig conversion to the target callback type. Ensure the shared library has
  no unresolved dependency on a Go `//export` symbol.
- Extend semantic/ABI reports and diff rules so switching callback ABI/backend is explicit and a
  same-symbol signature drift cannot be misclassified as compatible.
- Preserve the existing cgo callback ABI and source compatibility, or add versioned symbols if shared
  lowering proves necessary; record the chosen compatibility strategy in design documentation.

## Done When

- Header, Zig shim, symbol-table, ABI snapshot, and negative signature tests prove the callback ABI is
  explicit, correctly typed, backend-identified, and loadable without cgo while legacy cgo examples
  remain green.
