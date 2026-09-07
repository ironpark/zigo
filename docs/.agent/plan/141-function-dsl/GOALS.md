# GOALS

## Problem and the end result from the user's point of view

Typed binding declarations still repeat exact function paths and have no reusable comptime constructor or selector. Users can write `zigo.dsl.func(...)` for one entry and `zigo.dsl.funcs(Container, selector)` to expand public declarations into exact `zigo.Function` entries.

## Measurable goals

- Export a `zigo.dsl` namespace with typed `func` and `funcs` helpers.
- Preserve exact paths in the final `zigo.Binding`; no wildcard reaches reflection.
- Cover shorthand, detailed options, prefix selection, empty selection, and deterministic order with tests.

## Supported scope and non-goals

Support public function declarations on one comptime container and prefix-based selection with an explicit path base. Do not add runtime glob matching, function-value identity recovery, recursive selection, or metadata broadcasting across a selected set.

## Reference source / commit / license

In-repository typed schema at `src/declare.zig`, reflection at `src/reflect/walk.zig`, and Zig 0.16 comptime type reflection. No external source.

## Completion criteria for the whole plan

The DSL is documented, its compile-time output is tested as typed exact-path entries, the full test suite passes, and the changes are committed.
