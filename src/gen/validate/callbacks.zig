//! Callback contracts: Go errors, failure results and reentrancy metadata.
const std = @import("std");
const diagnostic = @import("diagnostic");
const semantic = @import("semantic");
const site = @import("site.zig");
const validate = @import("validate.zig");

/// `go_error` widens the Go callback type to `(i32, error)` and spends the
/// native result to say so: the trampoline returns `-5` instead of whatever
/// the callback computed. That only works when the native result is an `i32`
/// the target function reads as a status, so the two other callback shapes --
/// `void`, which has no result at all, and anything else, which `ZIGO014`
/// already refuses on purego -- are rejected here rather than silently
/// dropping the error.
pub fn callbackGoErrorIssue(
    allocator: std.mem.Allocator,
    function: semantic.SemanticFn,
    parameter: semantic.Parameter,
) !?diagnostic.Diagnostic {
    if (!parameter.goError()) return null;
    if (parameter.type != .callback) {
        const declaration = try site.functionDeclarationAlloc(allocator, function);
        return .{
            .severity = .@"error",
            .code = "ZIGO025",
            .message = try std.fmt.allocPrint(
                allocator,
                "`go_error` declared on parameter `{s}`, which is not a callback",
                .{parameter.name},
            ),
            .site = site.functionSiteFor(function, declaration),
            .hint = "use `.go_error = true` only on a function-pointer parameter",
        };
    }
    const result = parameter.type.callback.@"return".*;
    if (result == .int and result.int.signed and result.int.bits == 32) return null;
    const declaration = try site.functionDeclarationAlloc(allocator, function);
    return .{
        .severity = .@"error",
        .code = "ZIGO025",
        .message = try std.fmt.allocPrint(
            allocator,
            "callback `{s}` cannot return a Go error: its Zig result is not `i32`",
            .{parameter.name},
        ),
        .site = site.functionSiteFor(function, declaration),
        .hint = "declare the Zig callback as `*const fn (...) callconv(.c) i32`; the trampoline reports a Go error as the result `-5`",
    };
}

pub fn callbackFailureResultIssue(
    allocator: std.mem.Allocator,
    document: semantic.Semantic,
    function: semantic.SemanticFn,
    parameter: semantic.Parameter,
) !?diagnostic.Diagnostic {
    const failure = semantic.callbackFailure(document.types, parameter) orelse return null;
    const declaration = try site.functionDeclarationAlloc(allocator, function);
    if (parameter.type != .callback) return .{
        .severity = .@"error",
        .code = "ZIGO046",
        .message = try std.fmt.allocPrint(allocator, "callback failure result declared on parameter `{s}`, which is not a callback", .{parameter.name}),
        .site = site.functionSiteFor(function, declaration),
        .hint = "use `.on_callback_failure` only on a callback type entry or callback parameter",
    };
    const result = parameter.type.callback.@"return".*;
    if (result == .void) return .{
        .severity = .@"error",
        .code = "ZIGO046",
        .message = try std.fmt.allocPrint(allocator, "callback `{s}` cannot declare a failure result because it returns void", .{parameter.name}),
        .site = site.functionSiteFor(function, declaration),
        .hint = "remove `.on_callback_failure`, or give the callback a scalar return type",
    };
    if (callbackFailureValueFits(document, result, failure.result)) return null;
    return .{
        .severity = .@"error",
        .code = "ZIGO046",
        .message = try std.fmt.allocPrint(allocator, "callback failure result {d} does not fit callback `{s}`'s return type", .{ failure.result, parameter.name }),
        .site = site.functionSiteFor(function, declaration),
        .hint = "choose a `.result` value representable by the callback return type",
    };
}

fn callbackFailureValueFits(document: semantic.Semantic, node: semantic.TypeNode, value: i128) bool {
    return switch (node) {
        .bool => value == 0 or value == 1,
        .int => |integer| blk: {
            if (integer.bits == 0 or integer.bits > 64) break :blk false;
            if (integer.signed) {
                const magnitude = @as(i128, 1) << @intCast(integer.bits - 1);
                break :blk value >= -magnitude and value < magnitude;
            }
            break :blk value >= 0 and value < (@as(i128, 1) << @intCast(integer.bits));
        },
        .float => true,
        .@"enum" => |enum_ref| blk: {
            const declaration = semantic.typeDecl(document.types, enum_ref.ref) orelse break :blk false;
            if (declaration.kind != .@"enum") break :blk false;
            const tag = declaration.tag_type orelse break :blk false;
            break :blk callbackFailureValueFits(document, tag, value);
        },
        else => false,
    };
}

fn isUsize(node: semantic.TypeNode) bool {
    return node == .int and node.int.is_usize and !node.int.signed;
}

/// The userdata contract: a callback carries its Go token in a `usize` slot,
/// last unless its type entry says otherwise, and the function that takes the
/// callback passes the token through a `usize` parameter of its own, the one
/// right after the callback unless `Param.userdata` names it.
/// Everything a misplaced slot used to do at runtime -- dispatch on the wrong
/// argument, or fail generation without a site -- is refused here instead.
pub fn callbackUserdataIssue(
    allocator: std.mem.Allocator,
    function: semantic.SemanticFn,
    parameter_index: usize,
) !?diagnostic.Diagnostic {
    const parameter = function.params[parameter_index];
    if (parameter.type != .callback) {
        if (parameter.userdata == null) return null;
        const declaration = try site.functionDeclarationAlloc(allocator, function);
        return .{
            .severity = .@"error",
            .code = "ZIGO055",
            .message = try std.fmt.allocPrint(allocator, "`userdata` declared on parameter `{s}`, which is not a callback", .{parameter.name}),
            .site = site.functionSiteFor(function, declaration),
            .hint = "use `.userdata` only on a function-pointer parameter",
        };
    }
    const callback = parameter.type.callback;
    if (!callback.has_userdata or callback.params.len == 0) {
        const declaration = try site.functionDeclarationAlloc(allocator, function);
        return .{
            .severity = .@"error",
            .code = "ZIGO055",
            .message = try std.fmt.allocPrint(allocator, "callback `{s}` has no userdata parameter", .{parameter.name}),
            .site = site.functionSiteFor(function, declaration),
            .hint = "make the callback's last parameter a `usize` userdata, or point `.userdata` on its type entry at the parameter that carries it",
        };
    }
    if (!isUsize(callback.params[callback.params.len - 1])) {
        const declaration = try site.functionDeclarationAlloc(allocator, function);
        return .{
            .severity = .@"error",
            .code = "ZIGO055",
            .message = try std.fmt.allocPrint(allocator, "callback `{s}` userdata parameter {d} is not `usize`", .{ parameter.name, callback.nativeUserdataIndex().? }),
            .site = site.functionSiteFor(function, declaration),
            .hint = "declare the userdata slot as `usize`; the Go token travels through it",
        };
    }
    if (parameter.userdata) |name| {
        for (function.params, 0..) |candidate, candidate_index| {
            if (candidate_index == parameter_index or !std.mem.eql(u8, candidate.name, name)) continue;
            if (isUsize(candidate.type)) return null;
            const declaration = try site.functionDeclarationAlloc(allocator, function);
            return .{
                .severity = .@"error",
                .code = "ZIGO055",
                .message = try std.fmt.allocPrint(allocator, "userdata parameter `{s}` of callback `{s}` is not `usize`", .{ name, parameter.name }),
                .site = site.functionSiteFor(function, declaration),
                .hint = "name a `usize` parameter with `.userdata`; the Go token travels through it",
            };
        }
        const declaration = try site.functionDeclarationAlloc(allocator, function);
        return .{
            .severity = .@"error",
            .code = "ZIGO055",
            .message = try std.fmt.allocPrint(allocator, "callback `{s}` names userdata parameter `{s}`, which the function does not have", .{ parameter.name, name }),
            .site = site.functionSiteFor(function, declaration),
            .hint = "set `.userdata` to the name of the `usize` parameter that carries the token",
        };
    }
    if (parameter_index + 1 < function.params.len and isUsize(function.params[parameter_index + 1].type)) return null;
    const declaration = try site.functionDeclarationAlloc(allocator, function);
    return .{
        .severity = .@"error",
        .code = "ZIGO055",
        .message = try std.fmt.allocPrint(allocator, "callback `{s}` is not followed by its `usize` userdata parameter", .{parameter.name}),
        .site = site.functionSiteFor(function, declaration),
        .hint = "declare a `usize` parameter directly after the callback, or name the one that carries the token with `Param.userdata = .{ .param = \"...\" }`",
    };
}

/// The userdata contract over the whole document. It runs last: a callback
/// with a sharper fault (calling convention, a type it cannot carry) is
/// reported for that first.
pub fn callbackUserdataRule(allocator: std.mem.Allocator, document: semantic.Semantic) !?diagnostic.Diagnostic {
    for (document.functions) |function| {
        for (function.params, 0..) |_, parameter_index| {
            if (try callbackUserdataIssue(allocator, function, parameter_index)) |issue| return issue;
        }
    }
    return null;
}

pub fn callbackContractIssue(
    allocator: std.mem.Allocator,
    function: semantic.SemanticFn,
    parameter: semantic.Parameter,
) !?diagnostic.Diagnostic {
    const field = if (parameter.reentrancy != null)
        "reentrancy"
    else if (parameter.thread != null)
        "thread"
    else
        return null;
    if (parameter.type == .callback) return null;
    const declaration = try site.functionDeclarationAlloc(allocator, function);
    return .{
        .severity = .@"error",
        .code = "ZIGO025",
        .message = try std.fmt.allocPrint(
            allocator,
            "`{s}` declared on parameter `{s}`, which is not a callback",
            .{ field, parameter.name },
        ),
        .site = site.functionSiteFor(function, declaration),
        .hint = try std.fmt.allocPrint(allocator, "use `.{s}` only on a function-pointer parameter", .{field}),
    };
}

test "a purego callback result outside the uintptr ABI is rejected" {
    var int32_return: semantic.TypeNode = .{ .int = .{ .bits = 32, .signed = true } };
    var float_return: semantic.TypeNode = .{ .float = .{ .bits = 64 } };
    const usize_param: semantic.TypeNode = .{ .int = .{ .bits = 64, .is_usize = true, .signed = false } };
    const float_callback: semantic.TypeNode = .{ .callback = .{
        .c_callconv = true,
        .has_userdata = true,
        .params = &.{ .{ .float = .{ .bits = 64 } }, usize_param },
        .@"return" = &int32_return,
    } };
    const document: semantic.Semantic = .{
        .functions = &.{.{
            .name = "observe",
            .params = &.{ .{ .name = "sink", .type = float_callback }, .{ .name = "userdata", .type = usize_param } },
            .@"return" = .{ .void = {} },
            .symbol = "ignored",
        }},
        .package = "hub",
        .prefix = "zg",
        .zig_version = "0.16.0",
    };
    // A float parameter travels as its bit pattern now, so neither validator
    // has anything to say about it.
    try std.testing.expect((try validate.findIssue(std.testing.allocator, document)) == null);
    try std.testing.expect(validate.puregoCallbackIssue(document) == null);

    const float_result_callback: semantic.TypeNode = .{ .callback = .{
        .c_callconv = true,
        .has_userdata = true,
        .params = &.{ .{ .int = .{ .bits = 64, .signed = false } }, usize_param },
        .@"return" = &float_return,
    } };
    var float_result = document;
    float_result.functions = &.{.{
        .name = "observe",
        .params = &.{ .{ .name = "sink", .type = float_result_callback }, .{ .name = "userdata", .type = usize_param } },
        .@"return" = .{ .void = {} },
        .symbol = "ignored",
    }};
    const issue = validate.puregoCallbackIssue(float_result) orelse return error.MissingDiagnostic;
    try std.testing.expectEqualStrings("ZIGO014", issue.code);
    try std.testing.expectEqualStrings("observe", issue.site.declaration);
    // The result shape is a purego-backend rule, not a platform one, so the
    // general validator stays silent about it.
    try std.testing.expect((try validate.findIssue(std.testing.allocator, float_result)) == null);

    // A `bool` result crosses as `u8` through the shim thunk, so purego
    // accepts it alongside `void` and `i32`.
    var bool_return: semantic.TypeNode = .{ .bool = {} };
    const bool_result_callback: semantic.TypeNode = .{ .callback = .{
        .c_callconv = true,
        .has_userdata = true,
        .params = &.{ .{ .bool = {} }, usize_param },
        .@"return" = &bool_return,
    } };
    var bool_result = document;
    bool_result.functions = &.{.{
        .name = "filter",
        .params = &.{ .{ .name = "predicate", .type = bool_result_callback }, .{ .name = "userdata", .type = usize_param } },
        .@"return" = .{ .void = {} },
        .symbol = "ignored",
    }};
    try std.testing.expect(validate.puregoCallbackIssue(bool_result) == null);
}

test "a Go error on a callback is refused unless the Zig result is i32" {
    var i32_node: semantic.TypeNode = .{ .int = .{ .bits = 32, .signed = true } };
    const usize_node: semantic.TypeNode = .{ .int = .{ .bits = 64, .is_usize = true, .signed = false } };
    var void_node: semantic.TypeNode = .{ .void = {} };
    var i64_node: semantic.TypeNode = .{ .int = .{ .bits = 64, .signed = true } };
    const params = [_]semantic.TypeNode{ i32_node, usize_node };

    const accepted: semantic.TypeNode = .{ .callback = .{
        .c_callconv = true,
        .has_userdata = true,
        .params = &params,
        .@"return" = &i32_node,
    } };
    const returns_void: semantic.TypeNode = .{ .callback = .{
        .c_callconv = true,
        .has_userdata = true,
        .params = &params,
        .@"return" = &void_node,
    } };
    const returns_wide: semantic.TypeNode = .{ .callback = .{
        .c_callconv = true,
        .has_userdata = true,
        .params = &params,
        .@"return" = &i64_node,
    } };

    const Case = struct { type: semantic.TypeNode, message: []const u8 };
    const rejected = [_]Case{
        .{ .type = returns_void, .message = "callback `observer` cannot return a Go error: its Zig result is not `i32`" },
        .{ .type = returns_wide, .message = "callback `observer` cannot return a Go error: its Zig result is not `i32`" },
        // The flag only means anything on a callback: on anything else it is
        // a typo that would otherwise generate nothing at all.
        .{ .type = usize_node, .message = "`go_error` declared on parameter `observer`, which is not a callback" },
    };
    for (rejected) |case| {
        var scratch = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer scratch.deinit();
        const document: semantic.Semantic = .{
            .functions = &.{.{
                .name = "watch",
                .params = &.{
                    .{ .go_error = true, .name = "observer", .type = case.type },
                    .{ .name = "userdata", .type = usize_node },
                },
                .@"return" = .{ .void = {} },
                .symbol = "zg_watch",
            }},
            .package = "cb",
            .prefix = "zg",
            .zig_version = "0.16.0",
        };
        const issue = (try validate.findIssue(scratch.allocator(), document)) orelse return error.MissingDiagnostic;
        try std.testing.expectEqualStrings("ZIGO025", issue.code);
        try std.testing.expectEqualStrings(case.message, issue.message);
    }

    // The accepted shape is what every generated callback already is, so the
    // opt-in must not reject the case it exists for.
    var scratch = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer scratch.deinit();
    const document: semantic.Semantic = .{
        .functions = &.{.{
            .name = "watch",
            .params = &.{
                .{ .go_error = true, .name = "observer", .type = accepted },
                .{ .name = "userdata", .type = usize_node },
            },
            .@"return" = .{ .void = {} },
            .symbol = "zg_watch",
        }},
        .package = "cb",
        .prefix = "zg",
        .zig_version = "0.16.0",
    };
    try std.testing.expectEqual(@as(?diagnostic.Diagnostic, null), try validate.findIssue(scratch.allocator(), document));
}

test "callback failure result must fit a non-void callback return" {
    var i8_node: semantic.TypeNode = .{ .int = .{ .bits = 8, .signed = true } };
    var void_node: semantic.TypeNode = .{ .void = {} };
    const usize_node: semantic.TypeNode = .{ .int = .{ .bits = 64, .is_usize = true, .signed = false } };
    const callback_params = [_]semantic.TypeNode{usize_node};
    const narrow_callback: semantic.TypeNode = .{ .callback = .{
        .has_userdata = true,
        .params = &callback_params,
        .@"return" = &i8_node,
    } };
    const void_callback: semantic.TypeNode = .{ .callback = .{
        .has_userdata = true,
        .params = &callback_params,
        .@"return" = &void_node,
    } };
    const good_params = [_]semantic.Parameter{ .{ .name = "callback", .on_callback_failure = .{ .result = -128 }, .type = narrow_callback }, .{ .name = "userdata", .type = usize_node } };
    const wide_params = [_]semantic.Parameter{.{ .name = "callback", .on_callback_failure = .{ .result = -129 }, .type = narrow_callback }};
    const void_params = [_]semantic.Parameter{.{ .name = "callback", .on_callback_failure = .{ .result = 0 }, .type = void_callback }};
    const good_functions = [_]semantic.SemanticFn{.{ .name = "run", .params = &good_params, .@"return" = .{ .void = {} }, .symbol = "zg_run" }};
    const wide_functions = [_]semantic.SemanticFn{.{ .name = "run", .params = &wide_params, .@"return" = .{ .void = {} }, .symbol = "zg_run" }};
    const void_functions = [_]semantic.SemanticFn{.{ .name = "run", .params = &void_params, .@"return" = .{ .void = {} }, .symbol = "zg_run" }};
    const good: semantic.Semantic = .{ .functions = &good_functions, .package = "cb", .prefix = "zg", .zig_version = "0.16.0" };
    const wide: semantic.Semantic = .{ .functions = &wide_functions, .package = "cb", .prefix = "zg", .zig_version = "0.16.0" };
    const no_result: semantic.Semantic = .{ .functions = &void_functions, .package = "cb", .prefix = "zg", .zig_version = "0.16.0" };
    try validate.semanticDocument(std.testing.allocator, good);
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const wide_issue = (try validate.findIssue(arena.allocator(), wide)).?;
    try std.testing.expectEqualStrings("ZIGO046", wide_issue.code);
    try std.testing.expect(std.mem.containsAtLeast(u8, wide_issue.message, 1, "does not fit"));
    const void_issue = (try validate.findIssue(arena.allocator(), no_result)).?;
    try std.testing.expectEqualStrings("ZIGO046", void_issue.code);
    try std.testing.expect(std.mem.containsAtLeast(u8, void_issue.message, 1, "returns void"));
}

test "callback contracts are refused on non-callback parameters" {
    const scalar: semantic.TypeNode = .{ .int = .{ .bits = 32, .signed = true } };
    const cases = [_]semantic.Parameter{
        .{ .name = "value", .reentrancy = .allowed, .type = scalar },
        .{ .name = "value", .thread = .caller, .type = scalar },
    };
    for (cases) |parameter| {
        var scratch = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer scratch.deinit();
        const document: semantic.Semantic = .{
            .functions = &.{.{
                .name = "watch",
                .params = &.{parameter},
                .@"return" = .{ .void = {} },
                .symbol = "zg_watch",
            }},
            .package = "callbacks",
            .prefix = "zg",
            .zig_version = "0.16.0",
        };
        const issue = (try validate.findIssue(scratch.allocator(), document)) orelse return error.MissingDiagnostic;
        try std.testing.expectEqualStrings("ZIGO025", issue.code);
        try std.testing.expect(std.mem.indexOf(u8, issue.message, "which is not a callback") != null);
    }
}

test "a cancellable function has to name a flag its shim can pass and an error it can report" {
    const flag: semantic.TypeNode = .{ .cancel_flag = {} };
    const rounds: semantic.TypeNode = .{ .int = .{ .bits = 32, .signed = false } };
    const payload = struct {
        var node: semantic.TypeNode = .{ .void = {} };
    };

    const Case = struct {
        function: semantic.SemanticFn,
        message: []const u8,
    };
    const rejected = [_]Case{
        // A name that reaches nothing: the author probably renamed the
        // parameter and left the meta behind.
        .{ .function = .{
            .cancel = "stop",
            .name = "crunch",
            .params = &.{.{ .name = "rounds", .type = rounds }},
            .@"return" = .{ .error_union = .{ .error_set = &.{"Canceled"}, .payload = &payload.node } },
            .symbol = "zg_crunch",
        }, .message = "`.cancel` names `stop`, which is not a parameter of this function" },
        // Named, but not the type the contract is written against.
        .{ .function = .{
            .cancel = "cancel",
            .name = "crunch",
            .params = &.{.{ .cancel = true, .name = "cancel", .type = rounds }},
            .@"return" = .{ .error_union = .{ .error_set = &.{"Canceled"}, .payload = &payload.node } },
            .symbol = "zg_crunch",
        }, .message = "cancellation parameter `cancel` is not a `*const std.atomic.Value(u32)`" },
        // Nothing to say with: a cancelled call has no way to report that it
        // stopped rather than finished.
        .{ .function = .{
            .cancel = "cancel",
            .cancel_error = "Cancelled",
            .name = "crunch",
            .params = &.{.{ .cancel = true, .name = "cancel", .type = flag }},
            .@"return" = .{ .error_union = .{ .error_set = &.{"Empty"}, .payload = &payload.node } },
            .symbol = "zg_crunch",
        }, .message = "a cancellable function must be able to report `error.Cancelled`" },
        // The flag without the meta: the C parameter would be there with no
        // Go `ctx` to raise it.
        .{ .function = .{
            .name = "crunch",
            .params = &.{.{ .name = "cancel", .type = flag }},
            .@"return" = .{ .error_union = .{ .error_set = &.{"Canceled"}, .payload = &payload.node } },
            .symbol = "zg_crunch",
        }, .message = "parameter `cancel` is a cancellation flag but no `.cancel` names it" },
    };
    for (rejected) |case| {
        var scratch = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer scratch.deinit();
        const document: semantic.Semantic = .{
            .functions = &.{case.function},
            .package = "job",
            .prefix = "zg",
            .zig_version = "0.16.0",
        };
        const issue = (try validate.findIssue(scratch.allocator(), document)) orelse return error.MissingDiagnostic;
        try std.testing.expectEqualStrings("ZIGO026", issue.code);
        try std.testing.expectEqualStrings(case.message, issue.message);
    }

    var scratch = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer scratch.deinit();
    const accepted: semantic.Semantic = .{
        .functions = &.{.{
            .cancel = "cancel",
            .name = "crunch",
            .params = &.{
                .{ .name = "rounds", .type = rounds },
                .{ .cancel = true, .name = "cancel", .type = flag },
            },
            .@"return" = .{ .error_union = .{ .error_set = &.{ "Canceled", "Empty" }, .payload = &payload.node } },
            .symbol = "zg_crunch",
        }},
        .package = "job",
        .prefix = "zg",
        .zig_version = "0.16.0",
    };
    try std.testing.expectEqual(@as(?diagnostic.Diagnostic, null), try validate.findIssue(scratch.allocator(), accepted));

    const configured: semantic.Semantic = .{
        .functions = &.{.{
            .cancel = "cancel",
            .cancel_error = "Cancelled",
            .name = "crunch",
            .params = &.{.{ .cancel = true, .name = "cancel", .type = flag }},
            .@"return" = .{ .error_union = .{ .error_set = &.{"Cancelled"}, .payload = &payload.node } },
            .symbol = "zg_crunch",
        }},
        .package = "job",
        .prefix = "zg",
        .zig_version = "0.16.0",
    };
    try std.testing.expectEqual(@as(?diagnostic.Diagnostic, null), try validate.findIssue(scratch.allocator(), configured));
}

test "the userdata contract is refused with a site" {
    var void_node: semantic.TypeNode = .{ .void = {} };
    const usize_node: semantic.TypeNode = .{ .int = .{ .bits = 64, .is_usize = true, .signed = false } };
    const i32_node: semantic.TypeNode = .{ .int = .{ .bits = 32, .signed = true } };
    const no_userdata: semantic.TypeNode = .{ .callback = .{ .has_userdata = false, .params = &.{i32_node}, .@"return" = &void_node } };
    // What reflection produces when `.userdata` points at a non-`usize` slot.
    const wrong_slot: semantic.TypeNode = .{ .callback = .{ .has_userdata = true, .params = &.{ usize_node, i32_node }, .@"return" = &void_node } };
    const good: semantic.TypeNode = .{ .callback = .{ .has_userdata = true, .params = &.{ i32_node, usize_node }, .@"return" = &void_node } };
    const cases = [_]struct { params: []const semantic.Parameter, message: ?[]const u8 }{
        .{ .params = &.{ .{ .name = "callback", .type = no_userdata }, .{ .name = "userdata", .type = usize_node } }, .message = "has no userdata parameter" },
        .{ .params = &.{ .{ .name = "callback", .type = wrong_slot }, .{ .name = "userdata", .type = usize_node } }, .message = "userdata parameter 1 is not `usize`" },
        .{ .params = &.{.{ .name = "callback", .type = good }}, .message = "is not followed by its `usize` userdata parameter" },
        .{ .params = &.{ .{ .name = "callback", .type = good }, .{ .name = "count", .type = i32_node } }, .message = "is not followed by its `usize` userdata parameter" },
        .{ .params = &.{ .{ .name = "callback", .type = good, .userdata = "ctx" }, .{ .name = "count", .type = i32_node } }, .message = "names userdata parameter `ctx`, which the function does not have" },
        .{ .params = &.{ .{ .name = "ctx", .type = i32_node }, .{ .name = "callback", .type = good, .userdata = "ctx" } }, .message = "userdata parameter `ctx` of callback `callback` is not `usize`" },
        .{ .params = &.{ .{ .name = "count", .type = i32_node, .userdata = "ctx" }, .{ .name = "ctx", .type = usize_node } }, .message = "which is not a callback" },
        .{ .params = &.{ .{ .name = "ctx", .type = usize_node }, .{ .name = "callback", .type = good, .userdata = "ctx" } }, .message = null },
        .{ .params = &.{ .{ .name = "callback", .type = good }, .{ .name = "userdata", .type = usize_node } }, .message = null },
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    for (cases) |case| {
        const document: semantic.Semantic = .{
            .functions = &.{.{ .name = "run", .params = case.params, .@"return" = .{ .void = {} }, .symbol = "zg_run" }},
            .package = "cb",
            .prefix = "zg",
            .zig_version = "0.16.0",
        };
        const issue = try validate.findIssue(arena.allocator(), document);
        if (case.message) |message| {
            const found = issue orelse return error.MissingDiagnostic;
            try std.testing.expectEqualStrings("ZIGO055", found.code);
            try std.testing.expectEqualStrings("run", found.site.declaration);
            try std.testing.expect(std.mem.containsAtLeast(u8, found.message, 1, message));
        } else {
            try std.testing.expect(issue == null);
        }
    }
}

/// What a callback signature can carry. Every value crosses the wire as C
/// scalars the shim thunk can adapt: a parameter is a bool, an integer, a
/// float, a registered enum, a packed value, a pointer to a registered
/// handle, or a byte payload (a `[*:0]const u8` string or a `[*]const u8` +
/// `usize` pair, copied into Go memory), and a result is a scalar, enum,
/// packed value, or `void`. A mutable or non-byte slice, an extern struct, an
/// optional, or a by-value handle has no such shape; refusing it up front
/// keeps the emitters from meeting it as an `unreachable`.
pub fn callbackTypeIssue(
    allocator: std.mem.Allocator,
    document: semantic.Semantic,
    function: semantic.SemanticFn,
    parameter: semantic.Parameter,
) !?diagnostic.Diagnostic {
    if (parameter.type != .callback) return null;
    const callback = parameter.type.callback;
    for (callback.params, 0..) |node, index| {
        if (callbackValueSupported(document, node, true)) continue;
        return try callbackTypeDiagnostic(allocator, function, parameter, node, index);
    }
    const result = callback.@"return".*;
    if (result == .void or callbackValueSupported(document, result, false)) return null;
    return try callbackTypeDiagnostic(allocator, function, parameter, result, null);
}

fn callbackValueSupported(document: semantic.Semantic, node: semantic.TypeNode, pointer_allowed: bool) bool {
    return switch (node) {
        .bool, .int, .float, .@"enum" => true,
        .slice => pointer_allowed and semantic.isBytePayload(node),
        .value_struct => semantic.isPackedValue(document.types, node),
        .opaque_ptr => |value| pointer_allowed and !value.by_value,
        else => false,
    };
}

fn callbackTypeDiagnostic(
    allocator: std.mem.Allocator,
    function: semantic.SemanticFn,
    parameter: semantic.Parameter,
    node: semantic.TypeNode,
    index: ?usize,
) !diagnostic.Diagnostic {
    const declaration = try site.functionDeclarationAlloc(allocator, function);
    const shape: []const u8 = switch (node) {
        .slice => |value| if (value.sentinel != null) "a sentinel string" else "a slice",
        .value_struct => "an extern struct",
        .optional => "an optional",
        .opaque_ptr => |value| if (value.by_value) "a handle by value" else "a handle pointer",
        .callback => "a callback",
        .error_union => "an error union",
        .materialized => "a materialized result",
        .io_stream => "a stream",
        else => @tagName(node),
    };
    return .{
        .severity = .@"error",
        .code = "ZIGO057",
        .message = if (index) |position|
            try std.fmt.allocPrint(allocator, "callback `{s}` parameter {d} is {s}, which a callback cannot carry", .{ parameter.name, position, shape })
        else
            try std.fmt.allocPrint(allocator, "callback `{s}` returns {s}, which a callback cannot return", .{ parameter.name, shape }),
        .site = site.functionSiteFor(function, declaration),
        .hint = "callback parameters may be bool, integer, float, registered enum, packed value, a pointer to a registered handle, a `[*:0]const u8` string, or a `[*]const u8` + `usize` byte pair; results the same without pointers and strings, or void",
    };
}

/// The callback value-shape contract over the whole document, ahead of the
/// userdata rule so a signature that cannot cross at all is named first.
pub fn callbackTypeRule(allocator: std.mem.Allocator, document: semantic.Semantic) !?diagnostic.Diagnostic {
    for (document.functions) |function| {
        for (function.params) |parameter| {
            if (try callbackTypeIssue(allocator, document, function, parameter)) |issue| return issue;
        }
    }
    return null;
}

test "a callback carrying a mutable or non-byte slice, or a by-value handle is a ZIGO057" {
    const usize_param: semantic.TypeNode = .{ .int = .{ .bits = 64, .is_usize = true, .signed = false } };
    var void_return: semantic.TypeNode = .{ .void = {} };
    var byte: semantic.TypeNode = .{ .int = .{ .bits = 8, .signed = false } };
    var wide: semantic.TypeNode = .{ .int = .{ .bits = 32, .signed = true } };
    const cases = [_]struct { node: semantic.TypeNode, shape: []const u8 }{
        .{ .node = .{ .slice = .{ .@"const" = false, .element = &byte } }, .shape = "a slice" },
        .{ .node = .{ .slice = .{ .@"const" = true, .element = &wide } }, .shape = "a slice" },
        .{ .node = .{ .opaque_ptr = .{ .by_value = true, .@"const" = true, .nullable = false, .ref = "Stream" } }, .shape = "a handle by value" },
        .{ .node = .{ .value_struct = .{ .ref = "Point" } }, .shape = "an extern struct" },
    };
    for (cases) |case| {
        const callback: semantic.TypeNode = .{ .callback = .{
            .c_callconv = true,
            .has_userdata = true,
            .params = &.{ case.node, usize_param },
            .@"return" = &void_return,
        } };
        const document: semantic.Semantic = .{
            .functions = &.{.{
                .name = "observe",
                .params = &.{ .{ .name = "sink", .type = callback }, .{ .name = "userdata", .type = usize_param } },
                .@"return" = .{ .void = {} },
                .symbol = "ignored",
            }},
            .types = &.{
                .{ .name = "Stream", .kind = .@"opaque", .zig_path = "root.Stream" },
                .{ .name = "Point", .kind = .value_struct, .layout = .@"extern", .zig_path = "root.Point" },
            },
            .package = "hub",
            .prefix = "zg",
            .zig_version = "0.16.0",
        };
        const issue = (try callbackTypeRule(std.testing.allocator, document)).?;
        defer std.testing.allocator.free(issue.message);
        defer std.testing.allocator.free(issue.site.declaration);
        try std.testing.expectEqualStrings("ZIGO057", issue.code);
        try std.testing.expect(std.mem.indexOf(u8, issue.message, case.shape) != null);
    }
}

test "a callback carrying an enum, a handle pointer, a packed value, and byte payloads passes ZIGO057" {
    const usize_param: semantic.TypeNode = .{ .int = .{ .bits = 64, .is_usize = true, .signed = false } };
    var byte: semantic.TypeNode = .{ .int = .{ .bits = 8, .signed = false } };
    var enum_return: semantic.TypeNode = .{ .@"enum" = .{ .ref = "Mode" } };
    const tag: semantic.TypeNode = .{ .int = .{ .bits = 32, .signed = true } };
    const backing: semantic.TypeNode = .{ .int = .{ .bits = 16, .signed = false } };
    const callback: semantic.TypeNode = .{ .callback = .{
        .c_callconv = true,
        .has_userdata = true,
        .params = &.{
            .{ .@"enum" = .{ .ref = "Mode" } },
            .{ .opaque_ptr = .{ .@"const" = false, .nullable = false, .ref = "Stream" } },
            .{ .value_struct = .{ .ref = "Flags" } },
            .{ .slice = .{ .@"const" = true, .element = &byte } },
            .{ .slice = .{ .@"const" = true, .element = &byte, .sentinel = 0, .sentinel_many = true } },
            usize_param,
        },
        .@"return" = &enum_return,
    } };
    const document: semantic.Semantic = .{
        .functions = &.{.{
            .name = "observe",
            .params = &.{ .{ .name = "sink", .type = callback }, .{ .name = "userdata", .type = usize_param } },
            .@"return" = .{ .void = {} },
            .symbol = "ignored",
        }},
        .types = &.{
            .{ .name = "Mode", .kind = .@"enum", .tag_type = tag, .zig_path = "root.Mode" },
            .{ .name = "Stream", .kind = .@"opaque", .zig_path = "root.Stream" },
            .{ .name = "Flags", .kind = .value_struct, .layout = .@"packed", .backing_type = backing, .zig_path = "root.Flags" },
        },
        .package = "hub",
        .prefix = "zg",
        .zig_version = "0.16.0",
    };
    try std.testing.expect((try callbackTypeRule(std.testing.allocator, document)) == null);

    var pointer_return: semantic.TypeNode = .{ .opaque_ptr = .{ .@"const" = false, .nullable = false, .ref = "Stream" } };
    var pointer_result = document;
    const pointer_callback: semantic.TypeNode = .{ .callback = .{
        .c_callconv = true,
        .has_userdata = true,
        .params = &.{usize_param},
        .@"return" = &pointer_return,
    } };
    pointer_result.functions = &.{.{
        .name = "observe",
        .params = &.{ .{ .name = "sink", .type = pointer_callback }, .{ .name = "userdata", .type = usize_param } },
        .@"return" = .{ .void = {} },
        .symbol = "ignored",
    }};
    const issue = (try callbackTypeRule(std.testing.allocator, pointer_result)).?;
    defer std.testing.allocator.free(issue.message);
    defer std.testing.allocator.free(issue.site.declaration);
    try std.testing.expectEqualStrings("ZIGO057", issue.code);
    try std.testing.expect(std.mem.indexOf(u8, issue.message, "returns a handle pointer") != null);
}
