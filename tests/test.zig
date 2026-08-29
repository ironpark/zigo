test {
    const std = @import("std");
    std.testing.refAllDecls(@import("abi"));
    std.testing.refAllDecls(@import("diagnostic"));
    _ = @import("ir.zig");
    std.testing.refAllDecls(@import("reflect_walk"));
    std.testing.refAllDecls(@import("reflect_names"));
    _ = @import("snapshot.zig");
}
