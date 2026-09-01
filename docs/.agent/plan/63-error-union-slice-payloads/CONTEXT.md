# SCOPE

- `src/gen/lower.zig`: error-union branch (around the `payload_out` role) gains
  a slice case emitting `return_slice_pointer`/`return_slice_length` alongside
  the error code; `lowerValue` no longer needs to see the slice.
- `src/gen/emit.zig`: shim error-union epilogue (write ptr/len on success only),
  `writeCgoSliceReturn` and the purego equivalent reused for the error path,
  public wrapper return shape `([]T, error)`, release call gated on success.
- `src/gen/validate.zig`: `ownedReturnIsWrappable` / ZIGO016 release matching
  must accept an error-union slice payload; the release parameter type must
  match the payload slice type.
- `src/gen/abi_diff.zig`: no new node kinds expected; confirm signature equality
  covers the payload slice.
- `tests/generator_cases/complex` (or `value_struct`), `examples/07-event-queue`
  (`extractSamples` already exists; add a fallible variant), `docs/bindings.md`,
  `docs/limitations.md`, `docs/.agent/design/03-lowering-rules.md` §3 and §5.

# CONTEXT

## Current implementation and bottlenecks

- `lower.zig` error-union branch: `function_errors = codesFor(...)`, then if the
  payload is not void it creates a single `payload_out` parameter via
  `lowerValue(payload)`. `lowerValue` on a `.slice` returns
  `error.UnsupportedType` (`lower.zig:677` area).
- Plain slice returns already use roles `return_slice_pointer` /
  `return_slice_length` and the shim writes `out_result_ptr.* = result.ptr;
  out_result_len.* = result.len;`. The raw emitters copy via
  `writeCgoSliceReturn` (cgo, byte special case with `C.GoBytes`) and an
  equivalent `make`+`copy` on purego, then call `release_symbol` when set.
- Release plumbing: `SemanticFn.release` (name), `AbiFn.release_symbol`
  resolved in `lower.zig:236`, validated as ZIGO016 in `validate.zig:141`,
  hidden from the public API in `emit.zig:2315`. The example fixture is
  `EventQueue.extractSamples` / `EventQueue.freeSamples` with `root.liveSamples`.
- Error-path contract (03 §5): on error the payload out is not written and the
  Go wrapper returns the zero value.

## Target structure and invariants

- One error-union shape: `int32 code` + optional payload outs. For a slice
  payload the outs are `T** out_result_ptr, size_t* out_result_len`, mirroring
  the plain-slice return names so the raw emitters can share code.
- Shim: `const result = call catch |err| return codeFor(err); out_result_ptr.* =
  result.ptr; out_result_len.* = result.len; return 0;`.
- Raw Go: on `code != 0` return `nil, code` without touching the outs and
  without calling release. On success copy, then release if configured.
- Public Go: `([]T, error)`; the same handle checks and locking as other
  methods.
