# GOALS

## Problem and the end result from the user's point of view

The minimal Rust backend landed on `rust-minimal-backend` and works end to end.
Four independent reviews of `git diff main...HEAD` -- reuse, simplification,
efficiency and altitude -- found dead weight, three copies of rules that should
have one home, one generated-code path that costs the user two allocations and
two full copies per call, and one dispatch that silently falls back to Go.

Afterwards a user calling a slice-returning binding pays one allocation instead
of two, a third target cannot be added and silently emit Go, and the Rust
emitter carries no state that another field already answers.

## Measurable goals

- Generated Go output does not move: 77 generator cases regenerate with no
  diff, all 14 examples pass.
- The slice-return path is covered by a generator case and therefore compiled
  by the golden `rustc -D warnings` step, which no case reaches today.
- A UTF-8 slice result costs one allocation and one copy, down from two of
  each.
- `libraryPathEnvironmentAlloc` has one definition, not two that a test hopes
  agree.
- Every entry of `targets.all` has a backend row, asserted at comptime.

## Supported scope and non-goals

In scope: findings the four reviews raised against source files in the diff.

Non-goals, all recorded rather than fixed, with the reason:

- `cli.zig`'s `formatter_flags` duplicating `Target.formatter.override_flag`.
  Two reviews disagreed on whether the `std`-only-leaf justification holds. The
  fix changes CLI diagnostic text and touches fixtures; it is its own plan.
- `sync_check.compare` taking a `Target`. Only the no-manifest fallback is
  affected and the manifest covers every path `generate` writes.
- `Target.publicFunctionNameAlloc`'s hardcoded `New{s}`. Unreachable until
  handles are supported, which is the next feature plan, not this one.
- The output manifest's `kind: "go"` tag on `.rs` files. Renaming is a wire
  format change needing `Document.version = 2` and a compatibility read.
- `report` rejecting `--output-target` as an unknown argument rather than
  refusing it by name.

## Reference source / commit / license

The branch under review is `rust-minimal-backend`; the diff base is `main`.
No external source.

## Completion criteria for the whole plan

Every phase done, the tree clean, and the verification block below green.
