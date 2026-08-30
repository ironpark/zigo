# SCOPE

Update `build.zig`, the generator CLI/options/emitter, fixtures and tests, selected examples, and user documentation. Validate custom paths as safe relative Go package paths and preserve the existing `internal/raw` behavior by default.

# CONTEXT

## Current implementation and bottlenecks

`build.zig` and the emitter hardcode `internal/raw`, `package raw`, and imports ending in `/internal/raw`. Placing that file in the public package as-is would collide with public wrapper function names.

## Target structure and invariants

`Options.raw_package` selects `.internal`, `.{ .path = "support/ffi" }`, or `.colocated`. Separate raw packages are imported explicitly as `raw`; colocated raw functions use a private `zigoRaw` prefix. Custom paths remain relative, normalized only for the Go package/file name, and cannot escape the configured Go output directory. The default output remains `internal/raw/raw_gen.go`.
