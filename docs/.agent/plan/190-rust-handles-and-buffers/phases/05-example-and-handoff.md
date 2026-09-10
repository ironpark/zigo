---
depends_on:
- "190-rust-handles-and-buffers#4"
perf_phase: false
status: in-progress
---
> DONE-WHEN: The live-bytes assertion passes, which is the only evidence that `Drop`
> NEXT: none

# Prove it in the example, and hand it on

## Planned Work

- Extend `examples/13-rust-quick-start` with an opaque `Tally` exercising a
  constructor, a `*T` method (`add`), a by-value method (`peek`), a fallible
  method (`checkedHalf`), a borrowed view (`borrowReading`) and a
  caller-owned buffer return (`render`). The scalar, slice and error-union
  functions stay, so the example still mirrors the quick start.

  **A by-value method rather than the planned `*const T` one**, for phase 2's
  reason: the IR records only `receiver_by_value`, so that is the distinction
  the example can actually demonstrate.

  Two DSL details cost a round trip each and are worth recording:
  `api.handle` takes a type *name*, not a type, and a release target must
  itself be a bound declaration reachable from the module root -- so
  `freeRendered` moved out of `Tally` and is bound, while Rust still does not
  publish it.
- Add integration tests: the handle frees itself (assert against a live-bytes
  counter that returns to zero after the wrapper is dropped, which is the
  observable proof `Drop` ran), the borrowed view reads through, the buffer
  derefs without copying.
- Extend the demo so `2 + 3 = 5` still prints and the new shapes print beside
  it.
- Run everything for real. **Actual output:**

  ```
  $ cargo test
  running 9 tests
  test a_borrowed_reading_reads_through_to_its_owner ... ok
  test a_borrowed_slice_crosses_as_a_pointer_and_a_length ... ok
  test a_caller_owned_buffer_is_owned_rather_than_copied ... ok
  test a_handle_frees_itself_when_dropped ... ok
  test a_method_without_a_zig_error_set_returns_its_value ... ok
  test an_error_union_arrives_as_a_result ... ok
  test scalars_cross_unchanged ... ok
  test the_receiver_is_shared_or_mutable_as_zig_declared_it ... ok
  test the_result_type_makes_the_absent_payload_unrepresentable ... ok
  test result: ok. 9 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out

  $ cargo run --example demo
  2 + 3 = 5
  sum([1, 2, 3]) = 6
  7 / 2 = 3
  1 / 0 failed: zigo: divide: DivideByZero
  tally.add(40) = 40
  tally.add(2) = 42
  tally.peek() = 42
  reading.total() = 42
  tally.render() = total=42
  live bytes after drop = 0
  ```

  `cargo fmt --check` and `cargo clippy --all-targets -- -D warnings` are both
  clean. Clippy caught one thing worth keeping: `drop(reading)` on a view is
  `clippy::drop_non_drop`, because a view deliberately has no `Drop` and
  `drop` would only extend its lifetime. A scope reads better and says the
  right thing, so the test uses one.

  **The `Drop` test was order-dependent and had to be fixed.** It passed on
  the first run and then failed on every subsequent one:
  `calculator::live_bytes()` counts allocations for the whole process, and
  cargo runs tests on several threads, so another test holding a `Tally` made
  the absolute count non-zero. The test now measures the *delta* across one
  scope, and every test that holds a `Tally` takes a shared mutex so the delta
  means something. Verified stable over five consecutive runs.

  This is worth recording as the phase's own justification: a test that is
  compiled but never run cannot reveal a scheduling-dependent assertion, and
  nothing else in the suite would have caught it. It is exactly the failure
  this phase exists to rule out, found in the phase's own test.

  The last demo line is the phase's whole point. `live bytes after drop = 0`
  is the library's own count, and nothing in the demo calls `close` or
  `deinit`; the CI leg greps for that line as well as for `2 + 3 = 5`.
- `CHANGELOG.md` `[Unreleased]`, and update
  `docs/.agent/research/rust-target-feasibility.md`: strike items 1 and 2 off
  the hand-off list, replace the estimate with the measured line count, and
  record which creaks this plan closed and which it left.

## Done When

- The live-bytes assertion passes, which is the only evidence that `Drop`
  actually reached the native destructor rather than merely compiling.
- `cargo test`, `cargo clippy --all-targets -- -D warnings`,
  `cargo fmt --check` and the demo all pass, with real output recorded.
- `git status --short examples/13-rust-quick-start` empty after `zig build
  rust`.
- All thirteen Go examples still pass with no drift; 77+ generator cases clean;
  root tests green; `zig fmt --check` clean.
- CHANGELOG entry present; the research document's hand-off list reflects what
  is left. Committed.
