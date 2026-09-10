//! Links the native library `zig build rust-lib` installed.
//!
//! This is the whole of the Rust-side link setup, and it is the counterpart of
//! the `#cgo LDFLAGS` line zigo writes into a Go binding's raw package. It is
//! hand-written rather than generated because where the archive lives is a
//! property of the project's layout, not of the binding.

fn main() {
    // `zig build` installs into `<example>/zig-out` by default, and this crate
    // sits one level below it.
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("the crate directory has a parent")
        .join("zig-out");
    println!(
        "cargo:rustc-link-search=native={}",
        root.join("lib").display()
    );
    println!("cargo:rustc-link-lib=static=calculator_zigo");
    // The archive is rebuilt by `zig build rust-lib`, which cargo cannot see,
    // so the link line is re-emitted whenever the archive's timestamp moves.
    println!(
        "cargo:rerun-if-changed={}",
        root.join("lib").join("libcalculator_zigo.a").display()
    );
    println!("cargo:rerun-if-changed=build.rs");
}
