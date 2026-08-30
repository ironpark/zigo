---
depends_on:
- "01-zigo-go-bindings#9"
perf_phase: false
status: in-progress
---
> DONE-WHEN: Two specializations of the same generic produce distinct, non-colliding symbols and
> NEXT: none

# Generic specialization and callbacks

## Planned Work

- Accept named specializations such as `.{ .name = "FloatBuffer", .type = lib.Buffer(f32) }`
  and reject any function still carrying a comptime parameter as ZIGO008.
- Validate that callback types are `callconv(.c)`, rejecting others as ZIGO004.
- Generate the C trampoline and register Go callbacks through `cgo.NewHandle`, passing
  the handle as userdata.
- Wrap the trampoline body in a recover so a panicking Go callback becomes error code
  -3 instead of killing the process.
- For retained callbacks, store the handle on the Go wrapper and force generation of a
  `Close()` that deletes it.
- Add `examples/04-callback`.

## Done When

- Two specializations of the same generic produce distinct, non-colliding symbols and
  Go types.
- A Go callback that panics returns -3 and the process stays alive.
- Creating and closing a retained callback repeatedly does not grow the handle table.
