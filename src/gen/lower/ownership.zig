//! Ownership decisions shared by lowering and validation. This module has no
//! emitter dependency; records borrow the semantic tables and lowering arena.
const std = @import("std");
const abi = @import("abi");
const semantic = @import("semantic");

pub fn constructorForDeinit(constructors: []const semantic.Constructor, function: semantic.SemanticFn) ?semantic.Constructor {
    const receiver = function.receiver orelse return null;
    for (constructors) |constructor| {
        if (std.mem.eql(u8, constructor.type, receiver) and std.mem.eql(u8, constructor.deinit, function.name)) return constructor;
    }
    return null;
}

pub fn constructorForType(constructors: []const semantic.Constructor, type_name: []const u8) ?semantic.Constructor {
    for (constructors) |constructor| if (std.mem.eql(u8, constructor.type, type_name)) return constructor;
    return null;
}

/// The constructed handle type a caller-owned function returns, when it is one.
pub fn ownedOpaqueReturn(constructors: []const semantic.Constructor, function: semantic.SemanticFn) ?[]const u8 {
    if (function.ownership != .caller) return null;
    const node = function.@"return".errorPayload();
    if (node != .opaque_ptr) return null;
    if (constructorForType(constructors, node.opaque_ptr.ref) == null) return null;
    return node.opaque_ptr.ref;
}

/// The function `name` (a `.release` value) resolves to, when it is one a
/// generated release call can go through: it returns `void` and exposes
/// exactly one parameter. An injected argument is not part of the signature
/// the call has to match -- the shim fills it in, so a `fn(gpa, slice) void`
/// frees exactly the same slice a `fn(slice) void` does. This is the one rule
/// both lowering and validation apply.
pub fn releaseTarget(functions: []const semantic.SemanticFn, name: []const u8) ?abi.ReleaseTarget {
    for (functions, 0..) |candidate, index| {
        if (!std.mem.eql(u8, candidate.name, name)) continue;
        if (candidate.@"return" != .void) return null;
        var found: ?semantic.Parameter = null;
        for (candidate.params) |parameter| {
            if (parameter.injected != null) continue;
            if (found != null) return null;
            found = parameter;
        }
        return .{ .index = index, .function = candidate, .parameter = found orelse return null };
    }
    return null;
}

/// The element of a slice result that would need a release target, or null
/// when the function returns something else. This is the ownership question,
/// not the calling-convention one: a caller-owned C-string return counts
/// here because it still has to be freed, even though `sliceReturnElement`
/// excludes it. Optional and error-union wrappers do not change who owns the
/// underlying slice.
pub fn releasableSliceReturnElement(function: semantic.SemanticFn) ?semantic.TypeNode {
    const payload = function.@"return".errorPayload();
    const slice = if (payload == .optional) payload.optional.child.* else payload;
    return if (slice == .slice) slice.slice.element.* else null;
}

/// Who owns the result of `function` once the call returns. Runs on a
/// validated document: a `.release` that resolves to nothing, or a caller
/// owned pointer with no constructor, has already been reported, so both
/// fall through to `.none` here rather than being decided again.
/// `source_functions` is the table before checked promotion, the one the
/// release rule was validated against: promotion gives a release method a
/// synthetic error union the rule would otherwise refuse.
pub fn ownershipOf(
    document: semantic.Semantic,
    source_functions: []const semantic.SemanticFn,
    functions: []const abi.AbiFn,
    handles: []const abi.AbiOpaque,
    lowered: abi.AbiFn,
) abi.Ownership {
    const function = lowered.origin.*;
    const payload = function.@"return".errorPayload();
    const fallible = function.@"return" == .error_union;
    if (function.returnsBorrowedHandle()) {
        if (payload == .opaque_ptr) return .{ .borrowed_view = .{ .type_name = payload.opaque_ptr.ref } };
        return .none;
    }
    if (ownedOpaqueReturn(document.constructors, function)) |type_name| {
        // The destructor is the type's own deinit method, so only a method
        // on this receiver can be one.
        var destructor: ?[]const u8 = null;
        for (functions) |candidate| {
            if (!std.mem.eql(u8, candidate.origin.receiver orelse continue, type_name)) continue;
            if (constructorForDeinit(document.constructors, candidate.origin.*) != null) destructor = candidate.symbol;
        }
        const handle = handleNamed(handles, type_name);
        return .{ .handle = .{
            .type_name = type_name,
            .destructor = destructor,
            .boxed = function.boxed == .create,
            .child_of_receiver = function.childOfReceiver(),
            .retained_slots = if (handle) |value| value.retained_callback_slots else 0,
        } };
    }
    const byte: semantic.TypeNode = .{ .int = .{ .bits = 8, .signed = false } };
    if (function.ownership == .caller) {
        const release = releaseTarget(source_functions, function.release orelse return .none) orelse return .none;
        var receiver_c_name: ?[]const u8 = null;
        if (release.function.receiver) |receiver| {
            if (handleNamed(handles, receiver)) |handle| receiver_c_name = handle.c_name;
        }
        const materialized: ?struct { layout: usize, fallible: bool } = if (lowered.materialized_return) |value|
            .{ .layout = value.layout, .fallible = value.fallible }
        else if (lowered.materialized_out) |value|
            .{ .layout = value.layout, .fallible = value.fallible }
        else
            null;
        if (materialized) |value| return .{ .buffer = .{
            .element = byte,
            .release = release.index,
            .release_receiver_c_name = receiver_c_name,
            .materialized = value.layout,
            .fallible = value.fallible,
        } };
        const element = releasableSliceReturnElement(function) orelse return .none;
        return .{ .buffer = .{
            .element = element,
            .release = release.index,
            .release_receiver_c_name = receiver_c_name,
            .narrow = abi.narrowInt(element) != null,
            .absent = payload == .optional,
            .fallible = fallible,
        } };
    }
    const element = releasableSliceReturnElement(function) orelse return .none;
    return .{ .borrowed_copy = .{
        .element = if (lowered.ret_string == .c_string) byte else element,
        .text = lowered.ret_string,
        .absent = payload == .optional,
        .fallible = fallible,
    } };
}

fn handleNamed(handles: []const abi.AbiOpaque, name: []const u8) ?abi.AbiOpaque {
    var found: ?abi.AbiOpaque = null;
    for (handles) |handle| if (std.mem.eql(u8, handle.name, name)) {
        found = handle;
    };
    return found;
}

/// What each parameter of `function` does with memory across the call,
/// indexed by semantic parameter index.
pub fn paramOwnershipOf(allocator: std.mem.Allocator, document: semantic.Semantic, function: semantic.SemanticFn) ![]const abi.ParamOwnership {
    const table = try allocator.alloc(abi.ParamOwnership, function.params.len);
    // A release target receives the buffer it frees exactly as the library
    // handed it out, so the staging pass that would widen it is off.
    const stages_narrow = document.allocator != null and !isReleaseTarget(document.functions, function);
    for (function.params, 0..) |parameter, index| {
        table[index] = if (parameter.type == .callback and parameter.retention == .retained)
            .retained_token
        else if (parameter.type == .io_stream)
            .stream
        else if (abi.materializedOutParameter(parameter) != null or
            (stages_narrow and abi.narrowSliceElement(parameter.type) != null))
            .staged_copy
        else
            .transient;
    }
    return table;
}

pub fn recordOwnership(
    allocator: std.mem.Allocator,
    document: semantic.Semantic,
    source_functions: []const semantic.SemanticFn,
    functions: []abi.AbiFn,
    handles: []const abi.AbiOpaque,
) !void {
    for (functions) |*lowered| {
        lowered.ownership = ownershipOf(document, source_functions, functions, handles, lowered.*);
        lowered.param_ownership = try paramOwnershipOf(allocator, document, lowered.origin.*);
    }
}

/// Whether this function is some other function's declared release target.
pub fn isReleaseTarget(functions: []const semantic.SemanticFn, function: semantic.SemanticFn) bool {
    for (functions) |candidate| {
        const release = candidate.release orelse continue;
        if (std.mem.eql(u8, release, function.name)) return true;
    }
    return false;
}

fn dependentParentType(program: abi.Program, type_name: []const u8) ?[]const u8 {
    for (program.functions) |function| {
        if (!function.origin.childOfReceiver()) continue;
        const constructor = semantic.constructorForInit(program.constructors, function.origin.*) orelse continue;
        if (!std.mem.eql(u8, constructor.type, type_name)) continue;
        return function.origin.receiver;
    }
    return null;
}

fn typeHasDependentChildren(program: abi.Program, type_name: []const u8) bool {
    return typeHasDependentChildrenWithin(program, type_name, program.types.len + 1);
}

fn typeHasDependentChildrenWithin(program: abi.Program, type_name: []const u8, remaining: usize) bool {
    if (remaining == 0) return false;
    for (program.functions) |function| {
        if (function.origin.childOfReceiver() and
            std.mem.eql(u8, function.origin.receiver orelse "", type_name)) return true;
    }
    for (program.functions) |function| {
        const origin = function.origin.*;
        if (!returnsBorrowedView(origin) or
            !std.mem.eql(u8, origin.receiver orelse "", type_name)) continue;
        const node = origin.@"return".errorPayload();
        if (typeHasDependentChildrenWithin(program, node.opaque_ptr.ref, remaining - 1)) return true;
    }
    return false;
}

fn typeHasBorrowedRefs(program: abi.Program, type_name: []const u8) bool {
    for (program.functions) |function| {
        const origin = function.origin.*;
        if (!returnsBorrowedOpaque(origin) or returnsBorrowedView(origin)) continue;
        const node = origin.@"return".errorPayload();
        if (std.mem.eql(u8, node.opaque_ptr.ref, type_name)) return true;
    }
    for (program.projections) |projection| {
        if (projection.kind != .payload) continue;
        const field = projection.field orelse continue;
        const payload = field.type orelse continue;
        if (payload == .opaque_ptr and std.mem.eql(u8, payload.opaque_ptr.ref, type_name)) return true;
    }
    return false;
}

fn typeCanBeBorrowed(program: abi.Program, type_name: []const u8) bool {
    for (program.functions) |function| {
        const origin = function.origin.*;
        if (!returnsBorrowedView(origin)) continue;
        const node = origin.@"return".errorPayload();
        if (std.mem.eql(u8, node.opaque_ptr.ref, type_name)) return true;
    }
    return false;
}

fn typeReturnsBorrowedViews(program: abi.Program, type_name: []const u8) bool {
    for (program.functions) |function| {
        if (returnsBorrowedView(function.origin.*) and
            std.mem.eql(u8, function.origin.receiver orelse "", type_name)) return true;
    }
    return false;
}

fn returnsBorrowedOpaque(function: semantic.SemanticFn) bool {
    return function.@"return".errorPayload() == .opaque_ptr and function.ownership == .borrowed;
}

fn returnsBorrowedView(function: semantic.SemanticFn) bool {
    return returnsBorrowedOpaque(function) and function.returnsBorrowedHandle();
}

/// Complete type-level facts after functions and union projections are lowered.
/// These belong to Program.handles, not the ABI scalar's typedef-only copies.
pub fn recordHandleLifecycles(program: abi.Program, handles: []abi.AbiOpaque) void {
    for (handles) |*handle| {
        handle.lifecycle = .{
            .constructor = constructorForType(program.constructors, handle.name),
            .dependent_parent = dependentParentType(program, handle.name),
            .has_dependent_children = typeHasDependentChildren(program, handle.name),
            .has_borrowed_refs = typeHasBorrowedRefs(program, handle.name),
            .can_be_borrowed = typeCanBeBorrowed(program, handle.name),
            .returns_borrowed_views = typeReturnsBorrowedViews(program, handle.name),
        };
    }
}
