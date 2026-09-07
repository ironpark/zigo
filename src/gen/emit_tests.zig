//! Test root for the emitters. It sits above `emit/` so the emitters reach
//! the plugin registry in `plugins/`, which is a sibling directory: a module's
//! files may only import below its root.
test {
    _ = @import("emit/emit.zig");
}
