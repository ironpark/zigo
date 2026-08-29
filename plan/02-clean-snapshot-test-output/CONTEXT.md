# SCOPE

Introduce an explicit writer-based rendering API, keep the CLI's stderr renderer as a convenience wrapper, and capture rendering in the corruption test with an in-memory writer.

# CONTEXT

## Current implementation and bottlenecks

`Result.render()` unconditionally calls `std.debug.print`. The corruption test invokes it during a passing test, so Zig's build runner classifies the step as having warning output and prints `failed command` despite exit status zero.

## Target structure and invariants

Rendering must be testable without process-global stderr. Production mismatch diagnostics retain exactly the `snapshot <kind>: <path>\n` format and continue to go to stderr from the snapshot CLI.
