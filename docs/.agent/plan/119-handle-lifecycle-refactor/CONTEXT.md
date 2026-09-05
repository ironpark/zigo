# SCOPE

lower, public_types, shared runtime contracts and affected examples.

# CONTEXT

## Current implementation and bottlenecks

Ownership helpers are mixed into lower.zig and handle runtime into public_types.zig; concurrent close tests are duplicated.

## Target structure and invariants

Lowering owns ownership decisions; a dedicated emitter owns lifecycle code; tests share behavior but not backend internals.
