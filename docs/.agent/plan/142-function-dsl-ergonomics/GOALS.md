# GOALS

## Problem and the end result from the user's point of view

The initial function DSL is typed but offers little advantage for one entry and makes mixed generated/manual lists awkward. Users get concise ownership shortcuts, root selection defaults, exclusions, and a typed flattening combinator.

## Measurable goals

- Let common caller-owned and borrowed returns be expressed more briefly than raw literals.
- Let `funcs` omit `.base = "root"`, exclude exact declaration names, and keep deterministic order.
- Flatten tuples containing individual `Function` values and generated arrays into one fixed-size array.

## Supported scope and non-goals

Improve declaration ergonomics only. Do not introduce runtime patterns, recursive selection, implicit metadata broadcast, or changes to reflection and semantic IR.

## Reference source / commit / license

Build on in-repository `src/dsl.zig` and `src/declare.zig` at commit `03075b6f`; no external source.

## Completion criteria for the whole plan

The improved API has focused tests and documentation, the full suite passes, and changes are committed.
