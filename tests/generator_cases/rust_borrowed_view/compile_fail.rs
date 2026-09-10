//! A borrowed view must not outlive the handle it borrows from.
//!
//! This file is expected **not** to compile. It is the only evidence that the
//! lifetime on a generated view type does real work: a golden snapshot can
//! show that `ContextView<'owner>` was written, and `rustc` can show that
//! valid code using it compiles, but neither says that *invalid* code is
//! rejected. Go's binding carries the same rule as a doc comment and a
//! run-time parent refcount, so the caller learns about the mistake after
//! making it; here the compiler refuses.
//!
//! The build step compiling this asserts a non-zero exit and `E0515`, so this
//! file silently starting to compile is a test failure.

/// Returns a view borrowed from a handle that dies at the end of the call.
fn escape() -> zigo_golden::ContextView<'static> {
    let mut context = zigo_golden::Context::new().expect("the constructor succeeds");
    context.borrow_view()
}

fn main() {
    let _ = escape();
}
