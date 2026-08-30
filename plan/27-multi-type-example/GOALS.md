# GOALS

## Problem and the end result from the user's point of view

Demonstrate that one binding document can expose multiple types and that a method owned by one opaque type can safely accept another exposed opaque type.

## Measurable goals

- Add `examples/09-type-relations` with `Counter` and `Accumulator`.
- Generate two constructors and an `Accumulator.absorb(*Counter)` Go method.
- Exercise lifecycle and cross-type calls from both Zig and Go tests.

## Supported scope and non-goals

This example covers borrowed cross-type opaque parameters. Shared ownership, retained cross-type references, and cyclic lifetime management are not added.

## Reference source / commit / license

The example is original project code and follows the existing repository license.

## Completion criteria for the whole plan

The example passes Zig tests, generation, stale checks, ABI checks, Go tests, root formatting, and CI discovery.
