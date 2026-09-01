---
perf_phase: false
status: planned
---
> DONE-WHEN: `![]T` generates, compiles, and round-trips on both backends including the
> NEXT: none

# Lower and emit error-union slice payloads

## Planned Work

- lower: in the error-union branch, when `payload == .slice`, append
  `out_result_ptr` (`return_slice_pointer`) and `out_result_len`
  (`return_slice_length`) instead of `payload_out`; reuse the plain-slice code
  path (extract a helper if the two sites diverge only by name).
- emit shim: error-union epilogue writes ptr/len only after the call succeeds.
- emit C header: `T** out_result_ptr, size_t* out_result_len` after the
  ordinary parameters, before nothing else (matching plain slice returns).
- emit cgo/purego raw: return `([]T, int32)`; on nonzero code return `nil, code`;
  on success copy exactly as `writeCgoSliceReturn` / purego copy does.
- emit public: `([]T, error)` via the existing error mapping; zero value on
  error.
- validate: any check that walks error-union payloads (`nestedValueStruct`,
  `containsPointer` users) treats a slice payload like a slice return; struct
  elements allowed per plan 61 phase 1.
- Generator case with `![]const f32` and `![]Point` (extern struct element) and
  an example function `EventQueue.sampleValuesChecked() ![]const f32` that
  fails on a flag; Go tests cover success copy semantics and the error path
  returning nil.
- Docs: 03 §3 table row for `![]T`, §5 note; remove the gap sentences from
  `bindings.md` and `limitations.md`.

## Done When

- `![]T` generates, compiles, and round-trips on both backends including the
  error path; goldens updated via the case runner and `zig build snapshot
  --update-snapshots`; `zig build test` and example checks green; committed.
