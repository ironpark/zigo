# SCOPE

Add a pure CLI parser module, route `src/main.zig` through it, update build graph invocations and test wiring, and document the internal protocol boundary if needed.

# CONTEXT

## Current implementation and bottlenecks

`src/main.zig` interprets argument counts 5–16 and accesses configuration by hard-coded indexes. Adding one option requires changing accepted lengths and multiple index branches.

## Target structure and invariants

The executable dispatches one explicit subcommand. Every value has a named flag, boolean switches are presence-based, unknown/duplicate/missing arguments fail, and defaults remain identical to the former protocol.
