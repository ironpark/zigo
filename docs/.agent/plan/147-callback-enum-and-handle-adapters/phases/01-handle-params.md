---
depends_on:
- "147-callback-enum-and-handle-adapters#0"
perf_phase: false
status: planned
---
> DONE-WHEN: `zig build test` passes and the `OnStream`/`OnView` constructors in both goldens wrap
> NEXT: none

# Borrowed handle callback parameters

## Planned Work

- `typeCanBeBorrowed` also returns true when any function's callback parameter lists an
  `opaque_ptr` of that type; extend the lowering unit test.
- `callbackNeedsAdapter` returns true for `opaque_ptr` parameters; the adapter wraps them
  in `zigoNewBorrowed<T>(p, nil)`, guarding nullable pointers so `nil` stays `nil`.
- Regenerate the `callback_enum_handle` goldens; update the handle row of the docs table.

## Done When

- `zig build test` passes and the `OnStream`/`OnView` constructors in both goldens wrap
  the pointer, and the `Stream` handle gains `owner` and `zigoNewBorrowedStream`.
