//! Test root for validation. It sits above `validate/` so the rules reach the
//! plugin registry in `plugins/`, which is a sibling directory: a module's
//! files may only import below its root.
test {
    _ = @import("validate/validate.zig");
}
