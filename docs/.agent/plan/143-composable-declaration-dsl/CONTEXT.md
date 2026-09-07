# SCOPE

Modify `src/dsl.zig`, the typed declaration structs only where fluent lifecycle methods belong, public documentation, and the changelog. Add unit and compile-failure coverage using the repository's established test patterns.

# CONTEXT

## Current implementation and bottlenecks

`FuncSelector` currently selects by prefix and exclusion in container declaration order. `collect` accepts only `zigo.Function` values and arrays. Package declarations must repeat function paths, and simple registered types require full union literals. `Function` already carries ownership shortcuts and a typed `with` overlay.

## Target structure and invariants

Exact-name selection is opt-in, preserves caller order, and validates missing, non-function, and duplicate names. Prefix selection keeps its existing behavior. Every helper expands to the existing typed schema at comptime; no selectors or builders reach generation. Collection remains fixed-size and order-preserving. Named type batches bind the declaration value and Go name from the same exact declaration string.
