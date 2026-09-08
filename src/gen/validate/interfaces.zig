const std = @import("std");
const semantic = @import("semantic");
const diagnostic = @import("diagnostic");
const validate = @import("validate.zig");
pub const interfaceIssue = @import("plugin").interfaces.interfaceIssue;
pub const methodOf = @import("plugin").interfaces.methodOf;

test "an interface over two constructed handles with shared methods is accepted" {
    var scratch = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer scratch.deinit();
    try std.testing.expectEqual(@as(?diagnostic.Diagnostic, null), try validate.findIssue(scratch.allocator(), batchDocument(.{})));
}

/// Two `Batch` handles with `len`, constructors and a destructor. The
/// overrides let each test break exactly one rule.
pub const BatchOverrides = struct {
    /// Passed as a literal so the slice outlives the call.
    interfaces: ?[]const semantic.Interface = null,
    extra_types: []const semantic.TypeDecl = &.{},
    packages: ?[]const semantic.Package = null,
    constructors: ?[]const semantic.Constructor = null,
    functions: ?[]const semantic.SemanticFn = null,
};

pub fn batchDocument(overrides: BatchOverrides) semantic.Semantic {
    return .{
        .constructors = overrides.constructors orelse &.{
            .{ .deinit = "deinit", .init = "create", .type = "IntBatch" },
            .{ .deinit = "deinit", .init = "create", .type = "FloatBatch" },
        },
        .functions = overrides.functions orelse &batch_functions,
        .interfaces = overrides.interfaces orelse &batch_interface,
        .package = "batches",
        .packages = overrides.packages,
        .prefix = "zg",
        .types = if (overrides.extra_types.len == 0) &batch_types else overrides.extra_types,
        .zig_version = "0.16.0",
    };
}

const batch_interface = [_]semantic.Interface{.{ .methods = &.{"len"}, .name = "Batch", .types = &.{ "IntBatch", "FloatBatch" } }};

const batch_types = [_]semantic.TypeDecl{
    .{ .kind = .@"opaque", .name = "IntBatch" },
    .{ .kind = .@"opaque", .name = "FloatBatch" },
};

var int_batch: semantic.TypeNode = .{ .opaque_ptr = .{ .@"const" = false, .nullable = false, .ref = "IntBatch" } };
var float_batch: semantic.TypeNode = .{ .opaque_ptr = .{ .@"const" = false, .nullable = false, .ref = "FloatBatch" } };
const count: semantic.TypeNode = .{ .int = .{ .bits = 64, .is_usize = true, .signed = false } };
pub const batch_functions = [_]semantic.SemanticFn{
    .{ .name = "create", .namespace = "IntBatch", .ownership = .caller, .params = &.{}, .@"return" = .{ .error_union = .{ .error_set = &.{"OutOfMemory"}, .payload = &int_batch } }, .symbol = "zg_int_batch_create" },
    .{ .name = "len", .receiver = "IntBatch", .params = &.{}, .@"return" = count, .symbol = "zg_int_batch_len" },
    .{ .name = "deinit", .receiver = "IntBatch", .params = &.{}, .@"return" = .{ .void = {} }, .symbol = "zg_int_batch_deinit" },
    .{ .name = "create", .namespace = "FloatBatch", .ownership = .caller, .params = &.{}, .@"return" = .{ .error_union = .{ .error_set = &.{"OutOfMemory"}, .payload = &float_batch } }, .symbol = "zg_float_batch_create" },
    .{ .name = "len", .receiver = "FloatBatch", .params = &.{}, .@"return" = count, .symbol = "zg_float_batch_len" },
    .{ .name = "deinit", .receiver = "FloatBatch", .params = &.{}, .@"return" = .{ .void = {} }, .symbol = "zg_float_batch_deinit" },
};
