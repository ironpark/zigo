//! The Zig the test plugin ships for the generated shim to compile. It is
//! never part of a real build: the plugin that names it is registered in test
//! builds alone.
/// The number the test plugin's `answer` symbol hands back.
pub fn answer() u32 {
    return 42;
}
