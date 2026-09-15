//! The Zig `RUSTMARK` contributes to the native library, to show that a
//! plugin's native half is target-neutral: the same source and the same symbol
//! whichever language the binding set generates.
/// The version the plugin's `version` symbol hands back.
pub fn version() u32 {
    return 7;
}
