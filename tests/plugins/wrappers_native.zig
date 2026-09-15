//! The Zig `WRAPTEST` contributes to the native library. It is compiled by the
//! generated shim, against nothing but `std`, and exports nothing of its own:
//! the shim writes the `export` wrapper for every symbol the plugin declares.
/// The number the plugin's `answer` symbol hands back.
pub fn answer() u32 {
    return 42;
}
