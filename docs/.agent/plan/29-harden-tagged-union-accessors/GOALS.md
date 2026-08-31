# GOALS

## Problem and the end result from the user's point of view

Generated tagged-union accessors remain safe under opt-in cleanup, reject unrepresentable payloads before emission, have explicit lowered ABI contracts, and report lifecycle/panic/ABI changes predictably.

## Measurable goals

- Keep owned and borrowed wrappers alive through every accessor call and slice copy.
- Reject unsupported integer/float widths with stable diagnostics.
- Represent every generated projection in ABI IR and derive all emitters and collision checks from it.
- Define closed/nil handle and projection panic behavior without process aborts or false variant matches.
- Classify additive versus breaking union changes and cover adversarial runtime/ABI cases.

## Supported scope and non-goals

Harden the existing pointer-only `.repr = .tagged_union` feature without exposing union layout or adding new aggregate payload kinds. General thread-safe serialization of all generated wrappers is not introduced; concurrent mutation remains an explicit caller synchronization requirement.

## Reference source / commit / license

Current repository implementation on Zig 0.16.0. No external implementation is copied.

## Completion criteria for the whole plan

Unit, emitter, ABI-diff, process/build graph, tagged-union example, all example Go tests, stale checks, and documentation agree on the hardened contract, with a clean worktree.
