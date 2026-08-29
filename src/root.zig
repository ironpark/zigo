//! Declaration DSL imported by a user's `bindings.zig`.
//!
//! The DSL itself is introduced with the reflector in Phase 2. This module is
//! present from Phase 0 so consumers resolve `@import("zigo")` immediately.

test {
    _ = @This();
}
