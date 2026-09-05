# GOALS

## Problem and the end result from the user's point of view

Two extension ideas need a decision before any implementation: (1) making
ownership a first-class IR concept instead of the `.returns = .caller` +
`.release` pair that materialized trees, narrow slices, C strings and handles
each interpret on their own path, and (2) exporting Zig comptime interface
patterns (vtable structs, `anytype` duck typing) as Go interfaces over a
registered set of concrete types. The result of this plan is two design
documents under `docs/.agent/design/` with a go/no-go recommendation each,
the proposed `semantic.json` shape, and a golden-case sketch. No generator
code changes.

## Measurable goals

- Every current ownership path is inventoried with its release mechanism, its
  failure-path behaviour and the generated Go shape, in one table.
- The ownership design names one IR field set that reproduces every row of
  that table and lists which rows would change generated output.
- The interface design has at least one worked example from `examples/` where
  a comptime interface exists today, with the Go interface it would produce.
- Each design ends with a recommendation and an estimated phase count.

## Supported scope and non-goals

Go stays the only target. This plan produces designs, not code; a follow-up
plan implements whichever design is accepted. `runtime.AddCleanup` and arena
scoping are evaluated as consequences of the ownership design, not designed
in full here.

## Reference source / commit / license

Baseline: commit after plan 109 (generator restructure). Relevant docs:
`docs/bindings.md` sections "슬라이스 반환 소유권", "호출자 소유 slice 반환",
"Materialized 결과 트리"; `docs/limitations.md` line on generic functions.

## Completion criteria for the whole plan

Both design documents exist, are linked from `docs/.agent/design/README.md`,
and each states a recommendation. The user has read them and chosen what, if
anything, to implement.
