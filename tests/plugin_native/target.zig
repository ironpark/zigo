//! The bound library the `plugin_native` case's document describes, so the
//! generated shim has something to call beside the plugin's own source.
/// Adds two signed 32-bit integers.
pub fn add(a: i32, b: i32) i32 {
    return a + b;
}
