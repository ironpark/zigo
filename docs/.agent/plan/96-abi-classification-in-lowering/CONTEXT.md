# SCOPE

- Decisions are made in lowering; validate may keep its own checks but must call shared helpers on `semantic` types for identical predicates.

# CONTEXT

## Current implementation and bottlenecks

- See the list above; `emit.zig` still holds `isStringSliceParameter`, `isCStringSlice`, `isStringSlice`, `isCStringParameter`, `sliceReturnElement`, `stringSliceForm`, `constructorForInit/ForDeinit`, callback naming helpers, and struct-cast checks.

## Target structure and invariants

- lowering is the only place that classifies; the emitter renders `abi.Program`; validate reasons about `semantic` only; abi-diff reasons about lowered shape plus semantic names.
