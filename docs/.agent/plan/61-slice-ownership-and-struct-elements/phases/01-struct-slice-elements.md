---
completed_at: "2026-09-01T22:04:38Z"
perf_phase: false
status: done
---
> DONE-WHEN: `[]const T` in, `[]T` out (with `written`), and `[]const T` return with an
> NEXT: none

# Extern struct slice elements

## Planned Work

- validate: let `nestedValueStruct` accept `value_struct` as a slice element
  (parameter and return positions); keep optional and callback rejections and
  update the `ZIGO013` hint text accordingly.
- lower: confirm `lowerValue` on a `value_struct` element yields the mirrored C
  struct pointer; add `AbiScalar` support if the element path currently assumes
  scalars.
- emit (Zig shim): reinterpret `[*]const T`/`[*]T` + len as the Zig slice; the
  existing `@sizeOf`/`@offsetOf` guards already pin `T`.
- emit (cgo raw): for in slices build a temporary `[]C.zg_t` filled with
  `writeCgoStructConversion` per element and pass `&tmp[0]`; for out slices
  pass a `[]C.zg_t` buffer sized `len(p)` and read back `written` elements with
  `writeCgoStructRead` into the caller's `[]T`. Slice returns of struct elements
  copy element-wise.
- emit (purego raw): pass the `<T>Data` mirror slice directly; the public layer
  converts between `[]T` and `[]TData` in both directions.
- Add a generator case (`value_struct` or a new `value_struct_slice`) and extend
  example `07-event-queue` with an `estimate`-shaped function using
  `.direction = .out` and `!usize`; cover cgo and purego.
- Docs: `03-lowering-rules.md` §6.1, `limitations.md`, `bindings.md` — struct
  slice elements are allowed; optional/callback positions remain `ZIGO013`.
  Note that out direction still requires `param_meta.direction = .out`.

## Done When

- `[]const T` in, `[]T` out (with `written`), and `[]const T` return with an
  all-scalar extern struct element generate, compile, and round-trip on both
  backends; `ZIGO013` still fires for optional and callback positions with the
  updated hint; goldens and docs updated; committed.
