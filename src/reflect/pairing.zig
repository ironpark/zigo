//! Constructor claims shared by reflection and package closure.
const std = @import("std");
const semantic = @import("semantic");

/// One half of a `.constructs`/`.destroys` claim, and the function that made
/// it.
pub const Pairing = struct {
    index: usize,
    kind: enum { constructs, destroys },
    name: ?[]const u8 = null,
    type: []const u8,
};

/// Records one constructor pair: the document gains the pairing, Go groups the
/// constructor under the type it makes, and the storage a boxed constructor
/// allocated becomes the destructor's to free.
pub fn pair(
    allocator: std.mem.Allocator,
    constructors: *std.ArrayList(semantic.Constructor),
    functions: []semantic.SemanticFn,
    init_index: usize,
    deinit_index: usize,
    type_name: []const u8,
    explicit_name: ?[]const u8,
) !void {
    const constructor = &functions[init_index];
    try constructors.append(allocator, .{
        .deinit = functions[deinit_index].name,
        .init = constructor.name,
        .name = explicit_name,
        .type = type_name,
    });
    // Go groups the constructor under the type it makes; the Zig call path
    // stays where the function is actually declared, so a root-level
    // `newTerminal` is still called as `target.newTerminal`.
    if (!std.mem.eql(u8, constructor.namespace orelse "", type_name)) constructor.go_owner = type_name;
    constructor.ownership = .caller;
    // The storage the shim allocated is the shim's to free, so the paired
    // destructor runs the Zig `deinit` and then destroys it.
    if (constructor.boxed == .create) functions[deinit_index].boxed = .destroy;
}

/// The index of the function that claimed this half of a type's pairing.
pub fn findPairing(pairings: []const Pairing, kind: @FieldType(Pairing, "kind"), type_name: []const u8) ?usize {
    for (pairings) |claim| {
        if (claim.kind == kind and std.mem.eql(u8, claim.type, type_name)) return claim.index;
    }
    return null;
}
