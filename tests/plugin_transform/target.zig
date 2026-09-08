pub const State = enum(u8) { ready = 0 };
pub fn combine(left: u64, right: u64) u64 {
    return left * 100 + right;
}
pub fn state(value: State) State {
    return value;
}
