# GOALS

## Problem and the end result from the user's point of view

Plan 188 shipped a minimal Rust backend covering scalars, slices and error
unions, and handed on two items. This plan is both of them:

1. **Opaque handle → `Drop`.** The research document's largest predicted win.
   Go's binding hands the user a handle with a manual `Close()` and a runtime
   poison check for use-after-close; Rust's `Drop` removes the call and the
   borrow checker removes the check.
2. **Caller-owned buffer returns without a copy.** Go must copy the payload
   and call the release symbol before returning, because Go's GC cannot own a
   Zig pointer. Rust can own it directly, which is one allocation and one copy
   fewer per call.

Along the way this plan fixes a **bug in the shipped backend**: a binding whose
function has a narrow-integer parameter (a `u21` codepoint, say) and no declared
Zig errors generates a crate that does not compile. See CONTEXT.

From the user's point of view: `--output-target rust` on a binding with an
opaque type produces a struct that frees itself, methods that read `&self` or
`&mut self` according to what Zig declared, borrowed views that cannot outlive
what they borrow, and buffer results that are not copied.

## Measurable goals

- A handle-bearing binding generates a crate that compiles under
  `rustc --edition 2021 -D warnings` and is clippy-clean.
- A handle wrapper has no `close`, no `Close`, and no validity flag: `Drop` and
  ownership do that work. `grep` for a poison or closed-handle check in
  generated Rust finds nothing.
- A `*const T` Zig receiver produces `&self` and a `*T` receiver produces
  `&mut self`, which Go cannot express at all.
- A borrowed view's Rust signature carries a lifetime tied to the receiver, so
  a test that outlives the owner fails to compile. Verified by a compile-fail
  check, not by a comment.
- A caller-owned buffer return performs **zero** copies: the generated body
  contains no `to_vec`, no `from_utf8_lossy` and no `String::from`.
- The narrow-integer bug is fixed and covered by a golden case that compiles.
- Go output is unchanged: 77 generator cases clean, thirteen Go examples clean.

## Supported scope and non-goals

Supported: an opaque type with a constructor and a destructor; a fallible or
infallible constructor; methods on `*T` and `*const T` receivers; a handle as a
parameter of a free function or another method; a borrowed view returned from a
method; a caller-owned slice buffer whose release function is a free function.

Non-goals, each for a stated reason:

- **Dependent handles** (`lifecycle.dependent_parent`,
  `Ownership.Handle.child_of_receiver`). A child that must close before its
  parent is a lifetime relation, and expressing it properly means a
  lifetime parameter on the child wrapper -- the same machinery as a borrowed
  view but with ownership, which is a separate design. Refused with a
  diagnostic.
- **Boxed constructor pairs** (`Ownership.Handle.boxed`). A `create`/`destroy`
  pair over a boxed value has its own ownership shape; not needed to prove
  `Drop`.
- **Retained callback slots** (`retained_callback_slots != 0`). Callbacks are
  out of scope for the Rust backend entirely, and a handle that stores callback
  tokens has none to store.
- **By-value receivers** (`receiver_kind == .value`, a registered enum owning
  methods). Not a handle; it needs the enum mapping, which is its own work.
- **A release function that is a method** (`Buffer.release_receiver_c_name`).
  The wrapper would have to hold the receiver too, and then the buffer must not
  outlive it -- a lifetime, on a type that also has `Drop`. Refused.
- **`Send`/`Sync`.** A handle wrapper holds a raw pointer and is therefore
  neither, which is the correct default: whether the bound library's object may
  cross threads is a fact about that library that zigo does not record. Not
  asserted, and the generated doc comment says so.
- **An explicit `close()`.** Deliberately absent. Offering one re-introduces
  the manual-close problem this mapping exists to remove, and making it safe
  needs `mem::forget` bookkeeping that `Drop` alone does not.
- **Tagged unions, materialized trees, streams, cancellation, dynamic
  loading.** Unchanged from plan 188.

## Reference source / commit / license

Branch off `main` at `7cdf8e7f`, the commit that closed plan 189. Prior art in
this repository:

- `docs/.agent/plan/188-minimal-rust-backend/` -- the backend this extends, and
  the hand-off list whose items 1 and 2 this plan is.
- `docs/.agent/plan/189-rust-backend-cleanup/` -- already fixed the
  name-override seam (`VTable.setNameOverride`), made the backend a table, and
  removed the slice-return double copy. This plan must not re-do those.
- `docs/.agent/research/rust-target-feasibility.md` -- the "Rust가 오히려
  유리한 지점" list, of which handles and buffers are the top two.
- `src/gen/emit/handles.zig` (495 lines) -- Go's handle emitter. Read for what
  the C ABI offers, not for structure: it is a Go emitter behind the seam.

No external source is copied.

## Completion criteria for the whole plan

- Every phase `done`, each independently verified.
- Root `zig build test --summary all` green.
- `scripts/update-generator-cases.sh` leaves `tests/generator_cases` clean.
- All thirteen Go examples pass their full step list with no committed drift.
- The Rust example passes `zig build test rust-check rust-lib abi-check
  rust-coverage`, `cargo test`, `cargo clippy --all-targets -- -D warnings`,
  `cargo fmt --check`, and its demo.
- `zig fmt --check src build build.zig` clean.
- A `[Unreleased]` CHANGELOG entry, and the research document updated.
