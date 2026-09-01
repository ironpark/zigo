---
depends_on:
- "61-slice-ownership-and-struct-elements#2"
perf_phase: false
status: in-progress
---
> DONE-WHEN: The three declared element forms lower to `[]string` and round-trip on both
> NEXT: none

# String slice parameters

## Planned Work

- validate: exempt from `ZIGO005` a slice whose element is `[*:0]const u8`,
  `[:0]const u8`, or `[]const u8` with `param_meta.semantic = .utf8_string` on
  the parameter; keep rejecting every other pointer-bearing element with the
  existing hint.
- lower: a new role set for string slices — `p_data` (`const uint8_t*`),
  `p_data_len`, `p_lens` (`const size_t*`), `p_count` — all scalar, so Go
  memory carries no pointers. Record the layout (NUL after each string, `lens`
  excludes the NUL) in `03-lowering-rules.md` §3.
- emit (Zig shim): rebuild `[]const [:0]const u8` (or `[]const [*:0]const u8` /
  `[]const []const u8` per the declared element) from the flattened buffer.
  Use a fixed stack array for small counts and a fallback allocator for larger
  ones; decide the allocator (`std.heap.c_allocator` vs page allocator) and the
  failure mapping (an `OutOfMemory` error code or panic status) and document it.
- emit (cgo and purego raw + public): flatten `[]string` once per call into a
  `[]byte` and `[]uintptr`/`[]C.size_t`, pass pointers, no per-string malloc.
- Generator case and an `extractPaths`-shaped example function on both
  backends, including empty slice and empty-string elements.
- Docs: `bindings.md` string section, `limitations.md` slice rule, §3 table.

## Done When

- The three declared element forms lower to `[]string` and round-trip on both
  backends including empty slices and empty strings; `ZIGO005` unchanged for
  other pointer elements; shim allocation policy documented; goldens updated;
  committed.
