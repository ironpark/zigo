//! Handles that live in Zig and travel through Go as opaque pointers.
//! This block sits in the bindings file, which zigo reads before the library's
//! root module: it is the one file the binding's author owns.
const zigo = @import("zigo");
const library = @import("opaque");

pub const bindings = zigo.define(.{
    .root = library,
    .types = &.{
        .{ .handle = .{ .type = library.Context } },
        .{ .handle = .{ .type = library.ContextView } },
    },
    .functions = &.{
        .{ .path = "Context.create" },
        .{ .path = "Context.add", .params = &.{.{ .name = "value" }} },
        .{ .path = "Context.maybeTotal", .params = &.{.{ .name = "present" }} },
        .{ .path = "Context.setTotal", .params = &.{.{ .name = "c" }} },
        // `.iterator` adds a range-over-func wrapper beside the method:
        // `All()` here, and `Checked()` for the fallible variant.
        .{ .path = "Context.next", .iterator = .{} },
        .{ .path = "Context.nextChecked", .iterator = .{ .name = "Checked" } },
        .{ .path = "Context.rewind" },
        .{ .path = "Context.addCopy", .params = &.{.{ .name = "value" }} },
        .{ .path = "Context.borrowView", .returns = .{ .ownership = .borrowed } },
        .{ .path = "ContextView.total" },
        .{ .path = "Context.crash" },
        .{ .path = "Context.crashInfallible" },
        .{ .path = "Context.deinit" },
        .{ .path = "root.crashFatal" },
        .{ .path = "root.liveBytes" },
        .{ .path = "root.sumCopies", .params = &.{ .{ .name = "bias" }, .{ .name = "left" }, .{ .name = "right" } } },
        .{
            .path = "root.echo",
            .params = &.{.{ .name = "text", .semantic = .utf8_string }},
            .returns = .{ .semantic = .utf8_string },
        },
        .{ .path = "root.fallback" },
    },
});
