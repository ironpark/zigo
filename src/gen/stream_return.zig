//! Expansion of a stream-returning Zig method into the operations Go needs.
//!
//! `fn writer(self: *T) *std.Io.Writer` has no C representation: the pointer
//! belongs to the object, and a Go handle holding it would outlive whatever
//! made it valid. What Go actually wants from it is `io.Writer`, so the
//! binding generates the methods that interface asks for -- `Write`, `Flush`,
//! and `Read` for the reader direction -- and each of them calls the accessor
//! again rather than remembering what it returned. Nothing is stored, so
//! nothing can go stale, and the existing acquire/release/poison rules on the
//! receiver handle cover the whole lifetime question by themselves.
//!
//! The expansion runs between parsing and lowering. `semantic.json` keeps the
//! Zig method it found, which is what `abi-diff` should be comparing; every
//! layer below lowering sees only the operations.
const std = @import("std");
const semantic = @import("semantic");

/// Rewrites `document.functions`, replacing each stream-returning method with
/// its operations. Everything else is passed through untouched. The result
/// borrows the original document's strings and allocates only the new function
/// list and the synthetic parameters.
pub fn expand(allocator: std.mem.Allocator, document: semantic.Semantic) !semantic.Semantic {
    var count: usize = 0;
    for (document.functions) |function| count += operationCount(function);
    if (count == document.functions.len) return document;

    var functions = try allocator.alloc(semantic.SemanticFn, count);
    var index: usize = 0;
    for (document.functions) |function| {
        if (function.@"return" != .io_stream) {
            functions[index] = function;
            index += 1;
            continue;
        }
        const direction = function.@"return".io_stream.direction;
        const ops: []const semantic.StreamAccessor.Op = switch (direction) {
            .writer => &.{ .write, .flush },
            .reader => &.{.read},
        };
        for (ops) |op| {
            functions[index] = try operation(allocator, function, direction, op);
            index += 1;
        }
    }
    var expanded = document;
    expanded.functions = functions;
    return expanded;
}

fn operationCount(function: semantic.SemanticFn) usize {
    if (function.@"return" != .io_stream) return 1;
    return switch (function.@"return".io_stream.direction) {
        .writer => 2,
        .reader => 1,
    };
}

/// `isize` rather than `usize`, because Go spells it `int` and that is what
/// `io.Writer` and `io.Reader` require of the count they return.
const count_type: semantic.TypeNode = .{ .int = .{ .bits = 64, .is_usize = true, .signed = true } };
const byte_type: semantic.TypeNode = .{ .int = .{ .bits = 8, .signed = false } };

fn operation(
    allocator: std.mem.Allocator,
    function: semantic.SemanticFn,
    direction: semantic.StreamDirection,
    op: semantic.StreamAccessor.Op,
) !semantic.SemanticFn {
    const name = switch (op) {
        .write => "write",
        .flush => "flush",
        .read => "read",
    };
    const error_name: []const u8 = switch (direction) {
        .writer => "WriteFailed",
        .reader => "ReadFailed",
    };
    const error_set = try allocator.alloc([]const u8, 1);
    error_set[0] = error_name;

    const payload = try allocator.create(semantic.TypeNode);
    payload.* = if (op == .flush) .{ .void = {} } else count_type;

    var params: []const semantic.Parameter = &.{};
    if (op != .flush) {
        const element = try allocator.create(semantic.TypeNode);
        element.* = byte_type;
        const buffer = try allocator.alloc(semantic.Parameter, 1);
        buffer[0] = .{
            // `.in` for a write and for a read alike: the read fills the
            // caller's slice, but its count comes back as the return value,
            // so it needs none of the `.out` machinery that reports one.
            .direction = .in,
            .name = if (op == .write) "bytes" else "buffer",
            .type = .{ .slice = .{ .@"const" = op == .write, .element = element } },
        };
        params = buffer;
    }

    return .{
        .doc = null,
        .name = name,
        .params = params,
        .receiver = function.receiver,
        .@"return" = .{ .error_union = .{ .error_set = error_set, .payload = payload } },
        .source = function.source,
        .stream_accessor = .{ .accessor = function.name, .direction = direction, .op = op },
        // Lowering recomputes this from the prefix, the receiver and the
        // name, so what matters here is only that it is distinct and says
        // where it came from.
        .symbol = try std.fmt.allocPrint(allocator, "{s}_{s}", .{ function.symbol, name }),
    };
}

test "a writer method becomes Write and Flush, a reader method becomes Read" {
    const writer_node: semantic.TypeNode = .{ .io_stream = .{ .direction = .writer } };
    const reader_node: semantic.TypeNode = .{ .io_stream = .{ .direction = .reader } };
    const document: semantic.Semantic = .{
        .functions = &.{
            .{ .name = "writer", .params = &.{}, .receiver = "Doc", .@"return" = writer_node, .symbol = "zg_doc_writer" },
            .{ .name = "reader", .params = &.{}, .receiver = "Doc", .@"return" = reader_node, .symbol = "zg_doc_reader" },
            .{ .name = "count", .params = &.{}, .receiver = "Doc", .@"return" = .{ .void = {} }, .symbol = "zg_doc_count" },
        },
        .package = "doc",
        .prefix = "zg",
        .zig_version = "0.16.0",
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const expanded = try expand(arena.allocator(), document);

    // Two for the writer, one for the reader, and the untouched method.
    try std.testing.expectEqual(@as(usize, 4), expanded.functions.len);
    try std.testing.expectEqualStrings("write", expanded.functions[0].name);
    try std.testing.expectEqualStrings("zg_doc_writer_write", expanded.functions[0].symbol);
    try std.testing.expectEqualStrings("writer", expanded.functions[0].stream_accessor.?.accessor);
    // The slice a write takes is const; the one a read fills is not.
    try std.testing.expect(expanded.functions[0].params[0].type.slice.@"const");
    try std.testing.expectEqualStrings("flush", expanded.functions[1].name);
    try std.testing.expectEqual(@as(usize, 0), expanded.functions[1].params.len);
    try std.testing.expectEqualStrings("read", expanded.functions[2].name);
    try std.testing.expect(!expanded.functions[2].params[0].type.slice.@"const");
    try std.testing.expectEqualStrings("count", expanded.functions[3].name);

    // A count Go can hand back as `int`, so the methods satisfy io.Writer and
    // io.Reader rather than nearly doing so.
    const payload = expanded.functions[0].@"return".error_union.payload.*;
    try std.testing.expect(payload.int.is_usize and payload.int.signed);

    // A document without one is handed straight back rather than copied.
    const untouched: semantic.Semantic = .{
        .functions = &.{document.functions[2]},
        .package = "doc",
        .prefix = "zg",
        .zig_version = "0.16.0",
    };
    const same = try expand(arena.allocator(), untouched);
    try std.testing.expectEqual(untouched.functions.ptr, same.functions.ptr);
}
