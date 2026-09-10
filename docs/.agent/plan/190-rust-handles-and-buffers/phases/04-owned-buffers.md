---
depends_on:
- "190-rust-handles-and-buffers#3"
perf_phase: false
status: planned
---
> DONE-WHEN: The golden bodies for both buffer returns contain no `to_vec`, no
> NEXT: none

# Caller-owned buffers are owned, not copied

## Planned Work

- Emit `OwnedSlice<T>` once per crate that needs it: `ptr`, `len`, an
  `unsafe extern "C" fn(*const T, usize)` release, `Deref<Target = [T]>`, and a
  `Drop` that calls the release. Its doc comment states that nothing is copied
  and why Go's binding has to copy.
- A function whose `Ownership` is `buffer` returns `OwnedSlice<T>`, or
  `Result<OwnedSlice<T>, Error>` when it declares errors. The raw layer
  declares the release symbol and hands the pointer and length over untouched.
- Refuse a release function that is a method (`release_receiver_c_name` set),
  with a `ZIGO060` naming it.
- Settle the UTF-8 question against the actual IR rather than in advance: check
  what `ret_string` and `Ownership.Buffer.element` carry for a caller-owned
  text return, and record the answer. The intent is one rule -- text derefs to
  `[u8]` like anything else -- but the IR gets the last word.
- New case `tests/generator_cases/rust_owned_buffer/` binding a non-text buffer
  return and a text one.

## Done When

- The golden bodies for both buffer returns contain no `to_vec`, no
  `from_utf8_lossy` and no `String::`, which is the whole point of the phase.
- `OwnedSlice` appears once per crate, not once per release function.
- A method-form release is refused with a test asserting the `ZIGO060`.
- The golden crate compiles under `rustc -D warnings` and is clippy-clean.
- Root tests green; Go output unmoved; the Rust example green; `zig fmt
  --check` clean. Committed.
