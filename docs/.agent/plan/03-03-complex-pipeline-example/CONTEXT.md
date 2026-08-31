# SCOPE

- Add `examples/05-pipeline` with Zig sources, zigo configuration, generated Go package, focused tests, benchmark, and README.
- Add the example to the repository CI example matrix.
- Keep existing examples and generator behavior unchanged except for fixes proven necessary by the integrated example.

# CONTEXT

## Current implementation and bottlenecks

Examples 01 through 04 each isolate a narrow capability. Example 04 covers several advanced mechanisms, but no existing package drives slices through a retained callback while also checking typed application errors, UTF-8 state, opaque ownership, concurrent teardown, generic helpers, and native system-link propagation together.

## Target structure and invariants

`Pipeline` owns its copied UTF-8 name and retained callback registration until `Close`. Processing is rejected for disabled pipelines and empty input. A recovered Go callback panic is converted into a stable typed Zig error. Every successful constructor has an idempotent generated Go `Close`, and all tests finish with zero active callback handles and zero Zig-tracked live bytes. Generic batch specializations remain distinct named opaque types. The build declares zlib so the generated cgo package receives the link flag.
