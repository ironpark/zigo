//! Handles that live in Zig and travel through Go as opaque pointers.
//! This block sits in the bindings file, which zigo reads before the library's
//! root module: it is the one file the binding's author owns.
const zigo = @import("zigo");
const library = @import("opaque");

pub const bindings = zigo.define(.{
    .root = library,
    .types = .{
        .{ .type = library.Context, .repr = .@"opaque" },
        .{ .type = library.ContextView, .repr = .@"opaque" },
    },
    .functions = .{
        .{ .path = "Context.create" },
        .{ .path = "Context.add", .params = .{"value"} },
        .{ .path = "Context.maybeTotal", .params = .{"present"} },
        .{ .path = "Context.setTotal", .params = .{"c"} },
        // `.iterator` adds a range-over-func wrapper beside the method:
        // `All()` here, and `Checked()` for the fallible variant.
        .{ .path = "Context.next", .iterator = .{} },
        .{ .path = "Context.nextChecked", .iterator = .{ .name = "Checked" } },
        .{ .path = "Context.rewind" },
        .{ .path = "Context.addCopy", .params = .{"value"} },
        .{ .path = "Context.borrowView", .returns = .borrowed },
        .{ .path = "ContextView.total" },
        .{ .path = "Context.crash" },
        .{ .path = "Context.crashInfallible" },
        .{ .path = "Context.deinit" },
        .{ .path = "root.crashFatal" },
        .{ .path = "root.liveBytes" },
        .{ .path = "root.sumCopies", .params = .{ "bias", "left", "right" } },
        .{
            .path = "root.echo",
            .params = .{"text"},
            .param_meta = .{ .text = .{ .semantic = .utf8_string } },
            .semantic = .utf8_string,
        },
        .{ .path = "root.fallback" },
    },
});
