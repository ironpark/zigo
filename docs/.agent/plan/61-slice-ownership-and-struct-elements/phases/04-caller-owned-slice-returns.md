---
depends_on:
- "61-slice-ownership-and-struct-elements#0"
perf_phase: false
status: in-progress
---
> DONE-WHEN: `.returns = .caller` with `release` on a slice generates copy-then-free Go on
> NEXT: none

# Caller-owned slice returns with release

## Planned Work

- bindings DSL: accept `.release = "path.to.fn"` on a `functions` entry (or
  `.returns = .{ .caller = .{ .release = ... } }` if that reads better; pick
  one, document in `bindings.md`). The release target must be a function taking
  exactly the returned slice type (`fn([]T) void` or `fn([]const T) void`).
- reflect/semantic: carry `release` on `SemanticFn`; the release function is
  reflected and exported as its own C symbol (`<prefix>_<fn>_release` or the
  release function's own symbol if it is already in `functions`).
- validate: extend `ZIGO015` (or add `ZIGO016`) — `.returns = .caller` on a
  slice requires `release`; a `release` whose parameter type does not match the
  returned slice, or that names a missing declaration, is rejected with a hint.
- lower: for `caller` slice returns keep `out_result_ptr`/`out_result_len` and
  attach the release `AbiFn`.
- emit: after the phase-0 copy, call the release symbol with `(ptr, len)` on
  both backends before returning; on error status no release is called since
  the payload is not written. Element types: scalars, enums, and (after phase 1)
  extern structs.
- abi_diff: release symbol added/removed/changed is breaking for that function.
- Generator case and an example function shaped like `extractSamples() ![]f32`
  with `freeSamples(samples: []f32) void` using a library-side allocator; Go test
  asserts the returned slice survives after a second call and that a leak
  counter in the fixture returns to zero.
- Docs: `bindings.md` ownership table gains the slice row; `limitations.md` and
  `03-lowering-rules.md` §3/§8 describe copy-then-release.

## Done When

- `.returns = .caller` with `release` on a slice generates copy-then-free Go on
  cgo and purego; missing/mismatched release is a diagnostic with a snapshot
  test; `abi-check` reports release changes as breaking; goldens, examples, and
  docs updated; committed.
