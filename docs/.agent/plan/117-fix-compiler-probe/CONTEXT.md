# SCOPE

Compiler probe command parsing and truthful diagnostics.

# CONTEXT

## Current implementation and bottlenecks

Only the first word is probed, producing unsupported zig --version.

## Target structure and invariants

Append --version to the parsed CC argv; never invoke a shell.
