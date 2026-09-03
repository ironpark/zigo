# SCOPE

- The mirror is the only Go surface; the backing integer is never exposed except through `Backing()`.

# CONTEXT

## Current implementation and bottlenecks

- `validate.zig` test "a packed struct and an opaque-pointer field stay out of the extern struct path" pins ZIGO003 for a standalone packed registration; `emit.zig` near `renderPackedMirrors` (search "mirrors the Zig packed struct") already writes the mirror for union payload types.

## Target structure and invariants

- One packed layout table (plan 95) feeds every conversion site.
