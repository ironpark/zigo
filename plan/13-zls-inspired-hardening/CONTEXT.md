# SCOPE

Modify `src/gen`, generator and snapshot tests, `build.zig`, and CI configuration. Preserve the current public Go artifacts, stale-generation checks, semantic input format, and supported macOS/Linux behavior.

# CONTEXT

## Current implementation and bottlenecks

`generate` receives a caller allocator but produces an allocation graph without a matching deinitializer, so correctness depends on callers choosing an arena. Validation and borrowed-result emission allocate through `std.heap.page_allocator`; validation converts OOM into `null`, which means “no issue”. Several append helpers allocate fields inside an append expression and can leak on later failure. Generator tests embed large JSON and output strings inline, while `build.zig` repeats module construction. Snapshot content mismatches only identify a path.

## Target structure and invariants

Generator-lifetime allocations belong to an internal scratch arena. Temporary allocations use an explicitly passed allocator and propagate errors. Owned report values either append atomically or free every partially acquired field. Test fixtures own semantic input and expected trees. Production and test modules share the same constructor. Diagnostics remain pure until the CLI boundary translates them to process behavior.
