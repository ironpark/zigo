---
depends_on:
- "190-rust-handles-and-buffers#2"
perf_phase: false
status: planned
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
- Add a compile-fail check: a Rust snippet that lets a view outlive its owner
  must fail to compile, and the check must assert the failure rather than
  merely tolerate it. Decide during implementation whether that lives as a
  `trybuild`-style case in the example or as a build step running `rustc` and
  expecting a non-zero exit; prefer the one that needs no new dependency.
- Confirm what Go does here for the record: it wraps the pointer with no
  destructor, so the wrapper is valid only while the owner is and nothing
  enforces it. That contrast is the phase's justification and belongs in a
  comment, not only in this plan.

## Done When

- The golden shows a lifetime on the view type and on the returning method's
  signature, and no `impl Drop` for the view.
- A check proves that outliving the owner is a compile error. Its actual output
  is recorded in the phase outcome.
- The golden crate compiles under `rustc -D warnings` and is clippy-clean.
- Root tests green; Go output unmoved; the Rust example green; `zig fmt
  --check` clean. Committed.
