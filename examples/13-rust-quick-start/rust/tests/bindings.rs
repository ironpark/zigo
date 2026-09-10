//! The three shapes the minimal Rust backend covers, called across the C ABI.
//!
//! An integration test rather than a `#[cfg(test)]` module: the generated
//! `src/lib.rs` is rewritten by `zig build rust`, so a test written inside it
//! would be overwritten. This is the Rust counterpart of the Go examples'
//! `example_test.go`, which lives beside the generated package for the same
//! reason.

use calculator::{divide, sum, Error, ErrorKind};

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
