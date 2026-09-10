---
completed_at: "2026-09-10T05:18:31Z"
depends_on:
- "189-rust-backend-cleanup#1"
perf_phase: false
status: done
---
> DONE-WHEN: The new case's goldens contain exactly one allocation per slice result.
> NEXT: none

# Cover the slice-return path and stop copying it twice

## Planned Work

- Add a generator case binding both a UTF-8 slice return and a non-text slice
  return, so the golden `rustc -D warnings` step compiles the path. Add it
  before changing the emitter, so the goldens record the current output first
  and the improvement is visible as a diff.
- Rewrite the slice-payload emission to bind once: build the borrowed slice in
  the `else` arm and convert it there -- `String::from_utf8_lossy(bytes)
  .into_owned()` for text, `bytes.to_vec()` otherwise -- with the empty arm
  spelling `String::new()` or `Vec::new()` to match. This removes both the
  intermediate `Vec` on the text path and the `let result = result;` rebinding
  on the other.
- Confirm against `lower/ownership.zig` which ownership a plain slice return
  carries, and record it in the case's `options.json` or a comment, since the
  two reviews that reached this path disagreed about it.

## Done When

- The new case's goldens contain exactly one allocation per slice result.
- `cargo clippy --all-targets -- -D warnings` stays clean in
  `examples/13-rust-quick-start`.
- `scripts/update-generator-cases.sh` leaves the tree clean, and the only
  goldens that moved are the new case's.
