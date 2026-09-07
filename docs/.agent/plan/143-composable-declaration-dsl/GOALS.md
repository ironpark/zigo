# GOALS

## Problem and the end result from the user's point of view

Large explicit bindings repeat exact function paths, repeat those paths again when assigning packages, and spell many simple registered types one literal at a time. The DSL should compress those stable allowlists without turning upstream declaration growth into an implicit public API change.

## Measurable goals

- Let `funcs` select an explicit ordered list of declaration names with compile-time validation.
- Derive package function path lists from function entries instead of duplicating strings.
- Let `collect` combine either functions or registered types while preserving order and rejecting mixed inputs.
- Build batches of simple handle, value, enumeration, and tagged-union entries from exact declaration names.
- Provide concise function lifecycle modifiers for constructors, destructors, and child handles.

## Supported scope and non-goals

The work covers compile-time declaration helpers, focused tests, reference documentation, and the changelog. It does not add path globs, infer type representations, add parameter/field/package builders, or change the binding schema accepted by `zigo.define`.

## Reference source / commit / license

This is an original extension of zigo's existing DSL on the current repository state; no external source or license is introduced.

## Completion criteria for the whole plan

All new helpers compile on the supported Zig toolchain, invalid exact selectors fail at compile time, existing DSL callers remain source-compatible, the full test suite passes, and the public documentation explains stable exact selection and derived package paths.
