//! The three shapes the minimal Rust backend covers, called across the C ABI.
//!
//! An integration test rather than a `#[cfg(test)]` module: the generated
//! `src/lib.rs` is rewritten by `zig build rust`, so a test written inside it
//! would be overwritten. This is the Rust counterpart of the Go examples'
//! `example_test.go`, which lives beside the generated package for the same
//! reason.

use calculator::{divide, sum, Error, ErrorKind, Tally};
use std::sync::{Mutex, MutexGuard};

/// Serializes the tests that hold a `Tally`.
///
/// `live_bytes` counts allocations for the whole process and cargo runs tests
/// on several threads, so a test reading the counter has to know that no other
/// test is holding a tally at the time. Without this the `Drop` test passed or
/// failed depending on the scheduler -- which is precisely the kind of defect a
/// test that is compiled but never run cannot reveal.
static TALLY_LOCK: Mutex<()> = Mutex::new(());

fn hold_tallies() -> MutexGuard<'static, ()> {
    // A poisoned lock means another test panicked while holding it; the count
    // is then already suspect, and recovering keeps the failure reported
    // against that test rather than cascading into this one.
    TALLY_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
}

#[test]
fn scalars_cross_unchanged() {
    assert_eq!(calculator::add(2, 3), 5);
    assert_eq!(calculator::add(-1, 1), 0);
    assert_eq!(calculator::add(i32::MIN + 1, -1), i32::MIN);
}

#[test]
fn a_borrowed_slice_crosses_as_a_pointer_and_a_length() {
    assert_eq!(sum(&[1, 2, 3]), 6);
    assert_eq!(sum(&[-5, 5]), 0);
    // An empty slice still yields a non-null aligned pointer in Rust, which is
    // exactly what Zig's `[]const i32` wants, so this needs no placeholder on
    // either side.
    assert_eq!(sum(&[]), 0);
    // A slice whose element sum overflows `i32` is why the Zig declaration
    // widens the total.
    assert_eq!(sum(&[i32::MAX, i32::MAX]), 2 * i64::from(i32::MAX));
}

#[test]
fn an_error_union_arrives_as_a_result() {
    assert_eq!(divide(7, 2), Ok(3));
    assert_eq!(divide(-7, 2), Ok(-3));

    let error: Error = divide(1, 0).expect_err("dividing by zero fails");
    assert_eq!(error.kind, ErrorKind::DivideByZero);
    assert_eq!(error.name(), "DivideByZero");
    assert_eq!(error.operation, "divide");
    assert_eq!(error.message, None);
    // The code is the stable integer in `errors.lock.json`.
    assert_eq!(error.code, 1);
    assert_eq!(error.to_string(), "zigo: divide: DivideByZero");
    // And it is a real `std::error::Error`, so it composes with `?` and with
    // anything that takes a boxed error.
    let boxed: Box<dyn std::error::Error> = Box::new(error);
    assert_eq!(boxed.to_string(), "zigo: divide: DivideByZero");
}

#[test]
fn the_result_type_makes_the_absent_payload_unrepresentable() {
    // The point of the Rust mapping: unlike Go's `(T, error)`, there is no
    // zero value to inspect and no convention about when to trust it.
    fn compute() -> Result<i32, Error> {
        Ok(divide(10, 2)? + divide(10, 5)?)
    }
    assert_eq!(compute().unwrap(), 7);
}

#[test]
fn a_handle_frees_itself_when_dropped() {
    // The only evidence that `Drop` reached the native destructor rather than
    // merely compiling: the library counts its own live bytes, so the count
    // returning to where it started is the destructor's own report.
    let _guard = hold_tallies();
    let before = calculator::live_bytes();
    {
        let mut tally = Tally::new().expect("the constructor succeeds");
        assert!(calculator::live_bytes() > before);
        assert_eq!(tally.add(10), 10);
    }
    // No `close`, no `deinit`, nothing called here. Going out of scope did it.
    assert_eq!(calculator::live_bytes(), before);
}

#[test]
fn the_receiver_is_shared_or_mutable_as_zig_declared_it() {
    let _guard = hold_tallies();
    let mut tally = Tally::new().expect("the constructor succeeds");
    assert_eq!(tally.add(7), 7);
    // `peek` takes the value in Zig, so it borrows shared here and can be
    // called through a shared reference. Go gives every receiver `*Tally`.
    let shared: &Tally = &tally;
    assert_eq!(shared.peek(), 7);
}

#[test]
fn a_method_without_a_zig_error_set_returns_its_value() {
    let _guard = hold_tallies();
    let mut tally = Tally::new().expect("the constructor succeeds");
    // `add` is infallible in Zig, so there is no `?` to write even though the
    // C ABI gave it a status channel. Go returns `(int64, error)` here.
    let total: i64 = tally.add(4);
    assert_eq!(total, 4);
    // `checkedHalf` declares one, so it is a `Result`.
    assert_eq!(tally.checked_half(), Ok(2));
    let empty = Tally::new().expect("the constructor succeeds");
    let mut empty = empty;
    let error = empty.checked_half().expect_err("a zero total fails");
    assert_eq!(error.kind, ErrorKind::DivideByZero);
}

#[test]
fn a_borrowed_reading_reads_through_to_its_owner() {
    let _guard = hold_tallies();
    let mut tally = Tally::new().expect("the constructor succeeds");
    tally.add(21);
    // The reading holds a mutable borrow of the tally for as long as it
    // lives, so the tally cannot be touched until the borrow ends. A scope
    // rather than `drop`: the view has no `Drop` -- that is the whole point
    // of it -- so `drop` would only extend the lifetime, which is what
    // `clippy::drop_non_drop` says.
    {
        let mut reading = tally.borrow_reading();
        assert_eq!(reading.total(), 21);
    }
    // That the reading cannot *outlive* the tally is checked by the
    // `compile_fail.rs` of the `rust_borrowed_view` generator case, which the
    // build compiles and expects to fail with E0515.
    assert_eq!(tally.add(0), 21);
}

#[test]
fn a_caller_owned_buffer_is_owned_rather_than_copied() {
    let _guard = hold_tallies();
    let mut tally = Tally::new().expect("the constructor succeeds");
    tally.add(42);
    let rendered = tally.render().expect("rendering succeeds");
    // Derefs to the native allocation; nothing was copied on the way out.
    assert_eq!(&*rendered, b"total=42");
    assert_eq!(rendered.to_str_lossy(), "total=42");
    assert_eq!(rendered.len(), 8);
    // Released by going out of scope. There is no `free_rendered` to call --
    // the binding does not publish one, because `Drop` owns the release.
}
