---
completed_at: "2026-09-10T06:35:28Z"
depends_on:
- "190-rust-handles-and-buffers#3"
perf_phase: false
status: done
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
  with a `ZIGO060` naming it. Also refused: a narrow-integer buffer, which the
  shim rewrites in place, and a materialized tree.
- **Also done, and not in the plan: the release function is not published.**
  `OwnedSlice`'s `Drop` owns the release, so a public `free_digits` beside a
  buffer that already frees itself would be a double free waiting to be
  written. `Placement` gains a `.release` variant, symmetric with
  `.destructor`. Go publishes both halves and documents the hazard; Rust can
  simply not offer the second one.
- Settle the UTF-8 question against the actual IR.

  **Answer: one rule holds, and the IR made a second refusal necessary.** A
  `utf8_string` return carries `ret_string == .utf8_slice` and an ordinary
  byte element, so `OwnedSlice<u8>` covers it and the caller converts through
  `to_str_lossy`, which borrows for valid UTF-8 and therefore keeps the
  no-copy promise. But a *caller-owned C string* carries
  `ret_string == .c_string`, and that crosses as one NUL-terminated pointer
  rather than the pointer-and-length pair an owning slice needs, so it is
  refused with its own message.
- New case `tests/generator_cases/rust_owned_buffer/` binding a non-text buffer
  return and a text one, plus `rust_handle_buffer/` -- the `root_constructor`
  document -- where a *method* on a handle hands over an owned buffer and the
  destructor carries an injected allocator. That second case is what found
  both bugs above.

## Done When

- The golden bodies for both buffer returns contain no `to_vec`, no
  `from_utf8_lossy` and no `String::`, which is the whole point of the phase.
- `OwnedSlice` appears once per crate, not once per release function.
- No release function is published: `grep "pub fn free" ` over the golden
  `lib.rs` finds nothing.
- The audit accepts 7 of the 74 Go documents, all of which compile under
  `-D warnings`, and none crash.
- A method-form release is refused with a test asserting the `ZIGO060`.
- The golden crate compiles under `rustc -D warnings` and is clippy-clean.
- Root tests green; Go output unmoved; the Rust example green; `zig fmt
  --check` clean. Committed.
