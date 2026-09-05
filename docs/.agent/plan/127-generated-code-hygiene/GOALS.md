# GOALS

## Problem and the end result from the user's point of view

Four cosmetic findings from the generated-code review: a `var parent; parent = x` pair where `:=` does, a borrowed-handle `zigoAcquire` that unlocks by hand in three places while its sibling uses `defer`, empty-slice pointer setup spelled inline in four lines per parameter although a helper exists, cgo raw imports written one statement per line, and a `Close` doc claiming the error is always nil when `*HandleInUseError` is returned.

## Measurable goals

Generated files in every example show the four shapes fixed; no behaviour change (all Go tests pass on both backends).

## Supported scope and non-goals

Template-only changes in the emitters. No ABI or API change.

## Reference source / commit / license

Own code.

## Completion criteria for the whole plan

`zig build test`, all examples regenerated and tested, CHANGELOG entry.
