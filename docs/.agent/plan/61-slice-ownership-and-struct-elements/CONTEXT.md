# SCOPE

- `src/reflect/walk.zig`: sentinel `u8` many-pointer reflection; `release`
  function metadata.
- `src/gen/ir/semantic.zig`: `release` on `SemanticFn`; string-pointer type node
  or semantic marking as decided in phase 2.
- `src/gen/validate.zig`: relax `nestedValueStruct` for slices; string-slice
  exemption from `ZIGO005`; release checks extending `ZIGO015`.
- `src/gen/lower.zig`, `src/gen/ir/abi.zig`: struct-element slices, flattened
  string-slice roles, release symbol.
- `src/gen/emit.zig`: Zig shim, C header, cgo raw, purego raw, public layer for
  each feature; fix `GoBytes` and `unsafe.Slice` slice returns.
- `src/gen/abi_diff.zig`: release symbol and string-slice signature equality.
- `tests/generator_cases/*`, examples `05-pipeline` / `07-event-queue` (or a new
  example if neither fits), `docs/`.

# CONTEXT

## Current implementation and bottlenecks

- `nestedValueStruct` (`src/gen/validate.zig:365`) rejects any `value_struct`
  reached through a slice, optional, or callback. Lowering already emits
  `p_ptr`/`p_len`/`p_written` for slices (`src/gen/lower.zig:54`), and the cgo
  emitter converts structs member-wise (`writeCgoStructConversion`) while purego
  passes the `<T>Data` mirror whose layout is the contract.
- Out direction for slices comes only from `param_meta.direction = .out`
  (`src/reflect/walk.zig:146`); a mutable slice is not inferred as out.
- `src/reflect/walk.zig:320` handles only `.slice` and `.one` pointers; any
  many-pointer including `[*:0]const u8` is a `@compileError`, so the
  `[*:0]const u8` row in `03-lowering-rules.md` §3 is unimplemented.
- `ZIGO005` (`validate.zig:96`) rejects every slice whose element contains a
  pointer, including string elements.
- Slice returns lower to `out_result_ptr`/`out_result_len` (borrowed view). The
  cgo raw layer always emits `C.GoBytes` (`emit.zig:1082`) regardless of element
  type; the purego raw layer emits `unsafe.Slice` over native memory
  (`emit.zig:1642`) and only the `string` public path copies.
- `.returns = .caller` is validated by `ownedReturnIsWrappable` and rejected for
  anything but an opaque pointer with constructor and destructor (`ZIGO015`).
  There is no release registration for slices; constructor/destructor mappings
  are per opaque type.

## Target structure and invariants

- No aggregate crosses the C boundary by value; a struct-element slice crosses as
  `const T* p, size_t p_len` (in) or `T* p, size_t p_len, size_t* p_written`
  (out) using the existing mirrored C struct, and the shim's comptime layout
  guards cover elements exactly as they cover whole structs.
- Go memory handed to native never contains Go pointers. String slices cross as a
  flattened buffer: `const uint8_t* data, size_t data_len, const size_t* lens,
  size_t count` with NUL terminators included in `data`; the shim rebuilds the
  `[]const [:0]const u8` view. This is backend-neutral and needs no per-string
  malloc/free. If shim-side allocation of the pointer array proves unacceptable,
  phase 3 may fall back to `const char* const*` on cgo only and must document
  the purego consequence.
- Every slice return the public API hands out is Go-owned. Borrowed returns are
  copied; caller-owned returns are copied then released through the registered
  release symbol before the call returns, on both backends.
- Diagnostics precede emission: every new rejection has a ZIGO code, a site, and
  a hint, and is covered by a validate snapshot test.
