//! Registered before CONTRACT to exercise dependency ordering across phases.
const std = @import("std");
const api = @import("plugin");
const semantic = @import("semantic");
pub var runs: usize = 0;
pub var policies: usize = 0;
pub const plugin: api.Plugin = .{
    .name = "OBSERVER",
    .requires = &.{"CONTRACT"},
    .transform = transform,
    .name_function = nameFunction,
};
fn transform(context: api.TransformContext) !semantic.Semantic {
    runs += 1;
    for (context.document.functions) |function| {
        if (std.mem.eql(u8, function.name, "combine")) {
            var derived = false;
            for (context.document.functions) |candidate| if (std.mem.eql(u8, candidate.name, "derived")) {
                derived = true;
            };
            if (!derived or function.goName() != null) return error.IncorrectTransformOrder;
        }
    }
    return context.document;
}
fn nameFunction(_: api.TransformContext, function: semantic.SemanticFn) !?[]const u8 {
    if (std.mem.eql(u8, function.name, "derived")) {
        policies += 1;
        if (function.goName() == null or function.returnGoAdapter() == null) return error.IncorrectPolicyOrder;
    }
    return null;
}
