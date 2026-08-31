# SCOPE

Files in scope are `build.zig`, `.github/workflows/ci.yml`, and a new `examples/06-camel-case/` integration fixture including committed generated output.

# CONTEXT

## Current implementation and bottlenecks

`addGoBindings` normalizes the Go package name but still constructs the Zig library and installed header from the original `Options.name`. The emitter uses the normalized form. CI invokes `zig build go` before `go-check`, so stale committed generated Go is overwritten before comparison and changes to other generated state are not gated.

## Target structure and invariants

The normalized package stem owns generated Go filenames, cgo flags, installed library names, and installed header names. CI checks committed sources first, regenerates only after that check, then requires the examples tree to remain clean before running Go tests.
