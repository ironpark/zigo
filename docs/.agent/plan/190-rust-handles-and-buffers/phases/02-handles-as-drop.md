---
depends_on:
- "190-rust-handles-and-buffers#1"
perf_phase: false
status: planned
---
> DONE-WHEN: The golden `src/handle.rs` contains `impl Drop for` once per handle type, and
> NEXT: none

# Opaque handles become owning structs with Drop

## Planned Work

- `src/gen/emit_rust/handles.zig`, emitting `src/handle.rs`: one wrapper struct
  per entry of `program.handles`, an `impl` block carrying its constructor and
  its methods, and a `Drop` calling the destructor and discarding the status.
- Receiver mutability from the Zig receiver: `*T` gives `&mut self`, `*const T`
  and a by-value handle receiver give `&self`. This distinction is the one Go
  cannot express, so a test pins both spellings.
- Handles as parameters: a free function or a method taking `*const T` receives
  `&Type`, and one taking `*T` receives `&mut Type`.
- The raw layer gains the opaque pointer type, the out-pointer form a
  constructor and a view use, and the release-free handle declarations.
- Constructors: fallible ones return `Result<Self, Error>`, infallible ones
  return `Self` and panic through `panic_native`, following phase 0's rule.
- Refuse, each with its own `ZIGO060` message naming the feature: dependent
  handles, boxed pairs, retained callback slots, by-value (enum) receivers.
- New case `tests/generator_cases/rust_handle/`, compiled by the build's
  `rustc -D warnings` step and read for the absence of any poison or
  closed-handle check.

## Done When

- The golden `src/handle.rs` contains `impl Drop for` once per handle type, and
  contains no `close`, no `is_closed` and no validity flag.
- The golden shows `&self` for a `*const T` receiver and `&mut self` for a
  `*T` receiver, in one case file so the pair is visible in one diff.
- Each of the four refused shapes has a test asserting a `ZIGO060` naming it.
- The golden crate compiles under `rustc -D warnings` and is clippy-clean.
- Root tests green; 77 Go cases clean; thirteen Go examples clean; the Rust
  example green; `zig fmt --check` clean. Committed.
