# SCOPE

- `.covers` is metadata only: it never changes generated bindings.

# CONTEXT

## Current implementation and bottlenecks

- `coverage.zig` `classify` collects public types via `@typeName` and shortens with `walk.shortTypeName` (splits on the last `.`, which lands inside `Batch(Coordinate),true)`-style names); registration is checked by exact `@typeName` equality against `binding.types` only, so flattened and auto-appended structs are missed.
- Declarations are bound only if they appear in `document.functions`; wrappers have no link to the upstream declaration.

## Target structure and invariants

- One resolver decides whether a Zig type is "known to the document" for both the reason text and the unregistered list.
