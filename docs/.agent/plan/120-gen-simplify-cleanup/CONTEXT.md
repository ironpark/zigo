# SCOPE

`src/gen/**` only.

# CONTEXT

## Current implementation and bottlenecks

Emitters re-derive lookups that `ir/semantic.zig`, `lower/ownership.zig`, and `naming.zig` already
provide; `handles.zig` repeats lifecycle-name ternaries and parent-lookup snippets.

## Target structure and invariants

Single owner per lookup; generated output unchanged.
