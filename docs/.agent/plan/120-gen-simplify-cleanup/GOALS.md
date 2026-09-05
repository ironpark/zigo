# GOALS

## Problem and the end result from the user's point of view

A four-angle `/simplify` review of `src/gen` found duplicated helpers, dead code left by the
lowering/emitter split, repeated Go snippet variants in `emit/handles.zig`, and a few wasteful
allocations. Apply the small, behaviour-preserving fixes so generated output stays byte-identical.

## Measurable goals

- `zig build check` and `zig build test` pass with unchanged snapshot output.
- Dead functions and duplicated lookups named in the review are removed.

## Supported scope and non-goals

In scope: in-place cleanups inside `src/gen`. Non-goals: moving lifecycle decisions onto `AbiOpaque`,
replacing the fixed-point helper render, or changing generated Go/Zig text.

## Reference source / commit / license

Review of HEAD a4f38a7; no external source.

## Completion criteria for the whole plan

All selected findings applied, tests green, remaining large findings recorded for follow-up.
