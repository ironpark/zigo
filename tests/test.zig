test {
    const std = @import("std");
    _ = @import("abi_diff");
    std.testing.refAllDecls(@import("abi"));
    std.testing.refAllDecls(@import("abi_diff"));
    std.testing.refAllDecls(@import("diagnostic"));
    _ = @import("ir.zig");
    std.testing.refAllDecls(@import("reflect_walk"));
    std.testing.refAllDecls(@import("reflect_names"));
    std.testing.refAllDecls(@import("sync_check"));
    _ = @import("snapshot.zig");
    _ = @import("sync_check");
}
