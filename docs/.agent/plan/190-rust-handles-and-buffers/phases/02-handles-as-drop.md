---
depends_on:
- "190-rust-handles-and-buffers#1"
perf_phase: false
status: in-progress
---
> DONE-WHEN: The golden `src/handle.rs` contains `impl Drop for` once per handle type, and
> NEXT: none

# Opaque handles become owning structs with Drop

## Planned Work

- `src/gen/emit_rust/handles.zig`, emitting `src/handle.rs`: one wrapper struct
  per entry of `program.handles`, an `impl` block carrying its constructor and
  its methods, and a `Drop` calling the destructor and discarding the status.
- Receiver mutability from the Zig receiver.

  **Divergence: the distinction available is by-value versus pointer, not
  `*const T` versus `*T` as planned.** The IR does not record receiver
  constness. `Context.maybeTotal(self: *const Context)` reaches the C header
  as `zg_context_maybe_total(zg_context *self, ...)` -- non-const -- while only
  a by-value receiver produces `const zg_context *self`. So `receiver_by_value`
  is the one bit there is, and Zig's `*const` is erased before the ABI. A
  pointer receiver therefore gets `&mut self` and a by-value receiver gets
  `&self`.

  `&mut self` where `&self` would do costs a caller some flexibility and is
  never unsound, so the conservative answer is the safe one. It is still a
  distinction Go cannot express at all: every Go receiver is `*Context`.
  Recording receiver constness in the IR would give Rust the finer answer and
  is a hand-off.

  A handle *parameter* does carry `const` -- `sumCopies(bias, left: Context,
  right: Context)` gives both `const zg_context *` -- so parameters get the
  full `&T`/`&mut T` distinction.
- Handles as parameters: a free function or a method taking `*const T` receives
  `&Type`, and one taking `*T` receives `&mut Type`.
- The raw layer gains the opaque pointer type, the out-pointer form a
  constructor uses, and the handle declarations.

  The opaque C type is incomplete -- `typedef struct zg_context zg_context;` --
  so Rust must not claim to know its layout. A `#[repr(C)]` struct with one
  zero-length private field is the stable way to say "an address I never
  dereference"; `extern type`, which would say it directly, is unstable.

  **Also needed, and not in the plan: a raw wrapper that takes a handle
  pointer is `unsafe fn`.** `clippy`'s `not_unsafe_ptr_arg_deref` objected, and
  it is right -- the wrapper cannot check that the pointer is a live handle.
  So the wrapper carries a `# Safety` section, and the public wrapper is where
  the precondition is discharged, because the only way to obtain a handle is a
  constructor and the only way to release one is `Drop`. `raw.rs` also gains
  `#![deny(unsafe_op_in_unsafe_fn)]`, without which the block inside an
  `unsafe fn` would be redundant in edition 2021 and every native call would
  stop being visibly unsafe.
- Constructors: fallible ones return `Result<Self, Error>`, infallible ones
  return `Self` and panic through `panic_native`, following phase 0's rule.
- Refuse, each with its own `ZIGO060` message naming the feature: dependent
  handles, boxed pairs, retained callback slots, by-value (enum) receivers.

  **Two more refusals were needed than the plan expected, both because the
  audit was re-run properly this time.** Phase 0's audit script treated any
  non-zero exit as "refused", which hid the difference between a diagnostic
  and a crash. Re-running it with that distinction made visible:

  - **Every callback document crashed the Rust backend**, with `reached
    unreachable code` in `type_spelling.semanticScalar`, rather than reporting
    ZIGO060. Confirmed to predate this plan by checking out the branch point
    and reproducing it. The cause: under the cgo callback convention a
    callback parameter is *not an ABI parameter at all* -- only its `userdata`
    token crosses, as `zg_filter(int32_t value, size_t userdata)` -- so plan
    188's check on ABI parameter scalars never saw one. The refusal is now a
    whitelist over *semantic* kinds (`types.unsupportedNode`), so a shape the
    backend has never met is refused instead of reaching an `unreachable`.
  - **A registered opaque with nothing bound to it crashed the handle
    emitter.** `plugin_disabled` registers a `Counter` with no constructor, no
    destructor and no methods; `renderHandles` tried to emit a `Drop` for it
    and failed on the missing destructor. `types.ownedHandleFor` now asks the
    stronger question -- is there a bound constructor *and* destructor pair --
    and such a type is skipped. That is not a silent omission: no function can
    mention it without being refused, because the parameter and receiver rules
    both ask for the pair.

  Also fixed: the role-based refusal was passing `@tagName(role)` to the user,
  so a flattened struct parameter was reported as "it has flattened_field" --
  an internal enum name for a concept the message never explained.
  `roleDescription` names the feature the user wrote instead.

  The audit now says: of the 74 Go case documents, 5 generate a crate that
  compiles under `rustc -D warnings`, 69 are refused with a ZIGO060 naming the
  feature, and **none crash**.
- New case `tests/generator_cases/rust_handle/`, compiled by the build's
  `rustc -D warnings` step and read for the absence of any poison or
  closed-handle check.

## Done When

- The golden `src/handle.rs` contains `impl Drop for` once per handle type, and
  contains no `close`, no `is_closed` and no validity flag.
- The golden shows `&self` for a by-value receiver and `&mut self` for a
  pointer receiver, in one case file so the pair is visible in one diff.
- Each refused shape has either a unit test asserting a `ZIGO060` naming it or
  a real Go case document that exercises it; the audit output lists the
  distinct reasons reached.
- The audit reports no document that crashes rather than diagnosing.
- The golden crate compiles under `rustc -D warnings` and is clippy-clean.
- Root tests green; 77 Go cases clean; thirteen Go examples clean; the Rust
  example green; `zig fmt --check` clean. Committed.
