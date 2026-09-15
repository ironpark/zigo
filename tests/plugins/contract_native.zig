//! The Zig the contract fixture ships for the generated shim to compile.
/// The number the plugin's `answer` symbol hands back.
pub fn answer() u32 {
    return 42;
}
/// The product the plugin's `scale` symbol hands back.
pub fn scale(value: i32, factor: i32) i32 {
    return value * factor;
}
