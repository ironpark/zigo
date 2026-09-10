---
completed_at: "2026-09-10T06:23:49Z"
depends_on:
- "190-rust-handles-and-buffers#2"
perf_phase: false
status: done
---
> DONE-WHEN: The golden shows a lifetime on the view type and on the returning method's
> NEXT: none

# Borrowed views carry the lifetime they borrow

## Planned Work

- Emit a view wrapper per registered type that `Ownership.BorrowedView` names:
  a lifetime parameter, a `PhantomData<&'owner ()>`, no `Drop`, and its own
  methods.
- A method returning a borrowed view is spelled
  `fn borrow_view(&self) -> ContextView<'_>`, so the view's lifetime is the
  receiver's borrow.
- Add a compile-fail check. **Implemented as two build steps and no new
  dependency:** the golden crate is built as an rlib, then a case-owned
  `compile_fail.rs` is compiled against it with `expectExitCode(1)` and
  `expectStdErrMatch("E0515")`. Gated on the file existing, the way the
  existing `roundtrip.zig` step is, so a case opts in -- the first version
  gated on `expected/src/handle.rs` and therefore ran against `rust_handle`,
  which has no view and failed for the wrong reason.

  The error *code* is asserted rather than the prose: E0515 is stable across
  rustc releases in a way the wording is not, and asserting merely "it
  failed" would pass on a typo in the snippet.

  **The check was verified to have the right polarity** by replacing the
  snippet with `fn main() {}` and confirming the step fails with
  `error: process exited with code 0 (expected exited with code 1)`. A
  compile-fail test that cannot fail is worth nothing, and nothing else in the
  suite would have caught it.
- Confirm what Go does here for the record. Checked against
  `examples/03-opaque/go/opaque/opaque_gen.go`: `BorrowView` returns
  `(*ContextView, error)` with the doc line "The returned reference remains
  valid only while its parent handle remains open", and registers the child
  with the parent so a use-after-close is a *run-time* error. So the rule is
  the same and the enforcement differs -- Go finds the mistake after it is
  made, Rust refuses to build it. The contrast is written into the generated
  view's own doc comment, not only here.

  **Also decided during implementation: `borrow_view` takes `&mut self`, so
  the view holds a mutable borrow.** That follows from phase 2's conservative
  receiver rule, and it turns out to be exactly right rather than merely safe:
  Zig's `borrowView(self: *Context) *ContextView` returns a pointer into the
  `Context`, and `add` mutates the field the view reads. Blocking use of the
  parent while the view is alive is the sound answer, and it is one Go cannot
  express at all.

  `PhantomData<&'owner ()>` rather than `&'owner Owner`: the view borrows the
  *lifetime* without also claiming to hold a reference to one particular
  type, which would force the owner's name into the view struct and allow
  borrowing it from only one type.

## Done When

- The golden shows a lifetime on the view type and on the returning method's
  signature, and no `impl Drop` for the view.
- A check proves that outliving the owner is a compile error. Actual output:

  ```
  error[E0515]: cannot return value referencing local variable `context`
   --> compile_fail.rs:17:5
    |
  17 |     context.borrow_view()
    |     -------^^^^^^^^^^^^^^
    |     |
    |     returns a value referencing data owned by the current function
    |     `context` is borrowed here
  ```
- The golden crate compiles under `rustc -D warnings` and is clippy-clean.
- Root tests green; Go output unmoved; the Rust example green; `zig fmt
  --check` clean. Committed.
