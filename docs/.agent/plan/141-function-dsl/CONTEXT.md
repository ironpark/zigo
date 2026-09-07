# SCOPE

Add `src/dsl.zig`, re-export it from `src/root.zig`, add focused tests and reference documentation, and leave reflection/semantic IR contracts unchanged.

# CONTEXT

## Current implementation and bottlenecks

`zigo.define` already takes a comptime `Binding`, but callers manually spell every `Function` literal. `appendSelectedPath` then relies on exact strings and compile-time `@field`, so core wildcard paths would complicate metadata and validation semantics.

## Target structure and invariants

`func` always returns one `zigo.Function`. `funcs` returns a fixed-size array computed at comptime from public function declarations, with stable declaration order and exact paths constructed from `selector.base`. A zero-match selector fails at compile time. The existing reflection path remains unchanged.
