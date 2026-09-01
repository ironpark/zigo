---
perf_phase: false
status: planned
---
> DONE-WHEN: A non-`u8` slice return compiles and round-trips on cgo and purego; goldens
> NEXT: none

# Fix slice-return copies

## Planned Work

- cgo raw: replace the unconditional `C.GoBytes` with an element-typed copy
  (keep `GoBytes` for `u8`; for other scalars build a Go slice of the raw
  element type and copy from `unsafe.Slice` over the C pointer). Do the same
  for the tagged-union numeric-slice projections if they share the path.
- purego raw: copy `unsafe.Slice(ptr, len)` into a fresh Go slice before
  returning, so no public value aliases native memory.
- Add a non-`u8` slice return (`[]const f32` or `[]const i16`) to a generator
  case and to one example with both backends; verify the Go test observes a
  copy (mutating the returned slice does not affect a second call).
- Document the lifetime contract in `bindings.md` and `03-lowering-rules.md`
  §3: slice returns are Go-owned copies made at call time.

## Done When

- A non-`u8` slice return compiles and round-trips on cgo and purego; goldens
  updated via the case runner and `zig build snapshot --update-snapshots`;
  `zig build test` and the touched example's `go-check`/Go tests are green;
  committed.
