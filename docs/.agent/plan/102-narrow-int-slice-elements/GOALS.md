# GOALS

## Problem and the end result from the user's point of view

`[]const u21` is common in Unicode-handling Zig (ghostty `selectWord`, `graphemeWidth`, `printSlice`), but ZIGO018 rejects narrow integers inside slices ("zigo widens a narrow integer only as a whole parameter"), so every such function needs a wrapper that takes `[]const u32` and converts with an allocation. End result: input slices of narrow integers cross as the promoted width (`[]const u32` for `u21`) and the shim converts element-wise into a temporary buffer; output/return slices of narrow integers are widened into the caller-owned Go slice; out-of-range values on the way in raise the same range panic the whole-parameter path uses.

## Measurable goals

- Input `[]const uN`/`[]const iN` for N not in {8,16,32,64} bind with Go `[]uint32`-style promoted element types; the shim allocates the temporary through the binding's `.allocator` when present, otherwise through a bounded stack buffer with a documented limit and a fallback diagnostic (decide and document; prefer requiring `.allocator` and diagnosing its absence with a clear hint).
- Return and out slices of narrow elements widen into the Go slice during the copy that caller-owned slices already perform; borrowed narrow slices stay rejected (no stable widened memory) with an updated ZIGO018 hint.
- Value-struct fields and union payloads keep the current rule (documented).
- Generator case, example (11 or 01) Go tests on both backends, `docs/bindings.md` "정수 폭", `limitations.md`, CHANGELOG `### Added`.

## Supported scope and non-goals

In scope: `validate.zig` ZIGO018 paths, `lower.zig` slice element promotion, `emit.zig` shim conversion, docs.
Non-goals: narrow ints inside extern structs in slices, sentinel-terminated narrow slices.

## Reference source / commit / license

Current main; `abi.promotedIntBits`; whole-parameter promotion with range guard in the shim.

## Completion criteria for the whole plan

Phase done; verification loop green; tree clean.
