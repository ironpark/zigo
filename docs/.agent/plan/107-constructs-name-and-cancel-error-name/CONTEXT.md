# SCOPE

- Bindings without `.name` on constructors and with `Canceled` produce identical output.

# CONTEXT

## Current implementation and bottlenecks

- Constructor Go names are derived from the constructed type regardless of `.name`.
- The cancel error name is a literal in validation and in the Go error mapping.

## Target structure and invariants

- Constructor naming reads `function.name` when the binding set it, otherwise `New<Type>`.
- The cancel error name is a field on the function, defaulting to `Canceled`.
