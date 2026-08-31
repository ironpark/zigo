# GOALS

## Problem and the end result from the user's point of view

`zig build test` succeeds but prints a failure-shaped build runner diagnostic because a passing snapshot test writes an intentional mismatch to stderr. Make a normal successful test run silent while retaining coverage of both mismatch detection and its human-readable rendering.

## Measurable goals

- A plain `zig build test` exits zero without `snapshot content` or `failed command` output.
- The corrupted-tree test still asserts the structured difference and rendered diagnostic text.

## Supported scope and non-goals

Change only snapshot diagnostic rendering and its tests. Preserve the `zig build snapshot` CLI behavior and output for real mismatches; do not redesign the build graph or snapshot comparison algorithm.

## Reference source / commit / license

The current repository implementation in `tests/snapshot.zig` and `tests/snapshot_main.zig`; no external source or license applies.

## Completion criteria for the whole plan

The focused snapshot tests and the full `zig build test` suite pass, and the default successful build output contains no misleading failure diagnostic.
