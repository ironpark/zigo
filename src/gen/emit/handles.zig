//! Go handle types and their shared lifecycle runtime.
const std = @import("std");
const abi = @import("abi");
const naming = @import("naming");
const common = @import("common.zig");
const emit = @import("emit.zig");
const public_writers = @import("public_writers.zig");

/// One lifecycle for every handle. Fields are `ptr`, `mu`, `active`,
/// `closed`, and `poison` on any handle, `cleanup` on the ones this binding
/// constructs, and `callbackHandles` only on the ones that retain callbacks.
/// Calls count themselves in and out under `mu`; Close marks the handle and
/// the last one out releases it, so no caller ever waits on another.
/// `cleanup` is the safety net for a handle the caller drops without closing.
pub fn renderGoHandles(allocator: std.mem.Allocator, writer: *std.Io.Writer, program: abi.Program, options: emit.Options) !void {
    const names: LifecycleNames = .of(options);
    for (program.types) |declaration| {
        if (!emit.packageMatches(declaration.package, options.active_package)) continue;
        if (!declaration.isHandle()) continue;
        if (common.isValueOnlyTaggedUnion(program, declaration.name)) continue;
        const handle = common.handleRecord(program, declaration.name);
        const owns_callbacks = handle.retained_callback_slots != 0;
        const dependent_parent = handle.lifecycle.dependent_parent;
        const has_dependent_children = handle.lifecycle.has_dependent_children;
        const can_be_borrowed = handle.lifecycle.can_be_borrowed;
        const returns_borrowed_views = handle.lifecycle.returns_borrowed_views;
        // Owning a constructor is what gives a handle Close and the cleanup net.
        const constructor = handle.lifecycle.constructor;
        const auto_cleanup = constructor != null;
        if (auto_cleanup) {
            try writer.print("// {s} is a caller-owned native handle. Call Close when it is no longer needed.\n", .{declaration.name});
        } else {
            try writer.print("// {s} represents a native Zig handle.\n", .{declaration.name});
        }
        try writer.print("type {s} struct {{\n", .{declaration.name});
        // gofmt aligns a struct's field types on the longest field name, and
        // the goldens are compared unformatted, so the padding is computed
        // from the field set rather than hard-coded per shape.
        const width = fieldNameWidth(&.{ "ptr", "mu", "active", if (has_dependent_children) "children" else "", "closed", "poison", if (dependent_parent != null) "parent" else "", if (can_be_borrowed) "owner" else "", if (auto_cleanup) "cleanup" else "", if (owns_callbacks) "callbackHandles" else "" });
        try writeStructField(writer, "ptr", width, "unsafe.Pointer");
        // `mu` guards the fields below and is never held across a native
        // call: `active` counts the calls inside native, `closed` is what Close
        // sets, and `poison` is the panic that made the handle unusable.
        try writeStructField(writer, "mu", width, "sync.Mutex");
        try writeStructField(writer, "active", width, "int");
        if (has_dependent_children) try writeStructField(writer, "children", width, "int");
        try writeStructField(writer, "closed", width, "bool");
        try writeStructField(writer, "poison", width, "*NativePanicError");
        if (dependent_parent != null) try writeStructField(writer, "parent", width, "zigoChildHandle");
        if (can_be_borrowed) try writeStructField(writer, "owner", width, "zigoHandle");
        if (owns_callbacks) try writeStructField(writer, "callbackHandles", width, "[]zigoCallbackHandle");
        if (auto_cleanup) try writeStructField(writer, "cleanup", width, "runtime.Cleanup");
        try writer.writeAll("}\n\n");
        // The borrowed reference exists only when something hands one out.
        const has_refs = handle.lifecycle.has_borrowed_refs;
        if (has_refs) try writer.print(
            "// {s}Ref is a borrowed {s} reference that remains valid only while its parent is open.\n" ++
                "type {s}Ref struct {{\n\tptr    unsafe.Pointer\n\tparent zigoHandle\n}}\n\n",
            .{ declaration.name, declaration.name, declaration.name },
        );
        // One receiver name per type, matching the methods emitted elsewhere.
        const recv = try common.receiverVariableAlloc(allocator, declaration.name, &.{});
        defer allocator.free(recv);
        if (can_be_borrowed) try writer.print(
            "func newBorrowed{0s}(ptr unsafe.Pointer, owner zigoHandle) *{0s} {{\n" ++
                "\treturn &{0s}{{ptr: ptr, owner: owner}}\n}}\n\n",
            .{declaration.name},
        );
        if (owns_callbacks) try writer.print(
            "func ({0s} *{1s}) zigoCallbackHandle(slot int) zigoCallbackHandle {{\n" ++
                "\t{0s}.mu.Lock()\n\thandle := {0s}.callbackHandles[slot]\n\t{0s}.mu.Unlock()\n\treturn handle\n}}\n\n" ++
                "// zigoReplaceCallbackHandle swaps one generation-time callback slot under the handle lock.\n" ++
                "func ({0s} *{1s}) zigoReplaceCallbackHandle(slot int, handle zigoCallbackHandle) zigoCallbackHandle {{\n" ++
                "\t{0s}.mu.Lock()\n\tprevious := {0s}.callbackHandles[slot]\n\t{0s}.callbackHandles[slot] = handle\n\t{0s}.mu.Unlock()\n" ++
                "\treturn previous\n}}\n\n",
            .{ recv, declaration.name },
        );
        // A call pins the handle open with zigoAcquire and lets go with
        // zigoRelease; `mu` is dropped in between, so nothing that happens
        // inside native can make another goroutine wait on this handle.
        if (can_be_borrowed or dependent_parent != null) {
            try writer.print(
                "// zigoAcquire pins {0s} and its parent open for one native call.\n" ++
                    "func ({0s} *{1s}) zigoAcquire(operation string) (unsafe.Pointer, error) {{\n" ++
                    "\tif {0s} == nil {{\n\t\treturn nil, &HandleError{{Operation: operation}}\n\t}}\n" ++
                    "\t{0s}.mu.Lock()\n",
                .{ recv, declaration.name },
            );
            try writeParentLookup(writer, recv, can_be_borrowed, dependent_parent != null, .block);
            try writer.print(
                "\t{0s}.mu.Unlock()\n" ++
                    "\tif parent != nil {{\n\t\tif _, err := parent.{2s}(operation); err != nil {{\n\t\t\treturn nil, err\n\t\t}}\n\t}}\n" ++
                    "\t{0s}.mu.Lock()\n" ++
                    "\tif {0s}.closed || {0s}.ptr == nil {{\n\t\t{0s}.mu.Unlock()\n\t\tif parent != nil {{\n\t\t\tparent.{3s}()\n\t\t}}\n\t\treturn nil, &HandleError{{Operation: operation}}\n\t}}\n" ++
                    "\tif {0s}.poison != nil {{\n\t\terr := {0s}.poison.{1s}(operation)\n\t\t{0s}.mu.Unlock()\n\t\tif parent != nil {{\n\t\t\tparent.{3s}()\n\t\t}}\n\t\treturn nil, err\n\t}}\n" ++
                    "\t{0s}.active++\n\tptr := {0s}.ptr\n\t{0s}.mu.Unlock()\n\treturn ptr, nil\n}}\n\n",
                .{ recv, names.poisoned, names.acquire, names.release },
            );
        } else {
            try writer.print(
                "// zigoAcquire pins {0s} open for one native call and hands back its pointer;\n" ++
                    "// the call ends with zigoRelease. A nil, closed, or poisoned handle is the error.\n" ++
                    "func ({0s} *{1s}) zigoAcquire(operation string) (unsafe.Pointer, error) {{\n" ++
                    "\tif {0s} == nil {{\n\t\treturn nil, &HandleError{{Operation: operation}}\n\t}}\n" ++
                    "\t{0s}.mu.Lock()\n\tdefer {0s}.mu.Unlock()\n" ++
                    "\tif {0s}.closed || {0s}.ptr == nil {{\n\t\treturn nil, &HandleError{{Operation: operation}}\n\t}}\n" ++
                    "\tif {0s}.poison != nil {{\n\t\treturn nil, {0s}.poison.{2s}(operation)\n\t}}\n" ++
                    "\t{0s}.active++\n\treturn {0s}.ptr, nil\n}}\n\n",
                .{ recv, declaration.name, names.poisoned },
            );
        }
        // The last call out of a closed handle is the one that releases it, so
        // only a handle with Close has anything to do after the decrement.
        try writer.print("func ({0s} *{1s}) zigoRelease() {{\n\tif {0s} == nil {{\n\t\treturn\n\t}}\n\t{0s}.mu.Lock()\n\t{0s}.active--\n", .{ recv, declaration.name });
        if (auto_cleanup) {
            try writeParentLookup(writer, recv, can_be_borrowed, dependent_parent != null, .line);
            try writer.print("\tstate, release := {0s}.zigoTakeLocked()\n\t{0s}.mu.Unlock()\n\tif release {{\n\t\tcleanup{1s}(state)\n\t}}\n", .{ recv, declaration.name });
            if (can_be_borrowed or dependent_parent != null)
                try writer.print("\tif parent != nil {{\n\t\tparent.{s}()\n\t}}\n", .{names.release});
            try writer.writeAll("}\n\n");
        } else {
            // Without Close there is nothing of its own to release, so only a
            // borrowed handle has a parent to let go of.
            if (can_be_borrowed) try writeParentLookup(writer, recv, true, dependent_parent != null, .line);
            try writer.print("\t{0s}.mu.Unlock()\n", .{recv});
            if (can_be_borrowed) try writer.print("\tif parent != nil {{ parent.{s}() }}\n", .{names.release});
            try writer.writeAll("}\n\n");
        }
        try writer.print(
            "// zigoPoison marks {0s} unusable: a Zig panic unwound through native frames\n" ++
                "// without running their defers, so the state behind it is unknown.\n" ++
                "func ({0s} *{1s}) zigoPoison(cause *NativePanicError) {{\n\tif {0s} == nil {{\n\t\treturn\n\t}}\n\t{0s}.mu.Lock()\n",
            .{ recv, declaration.name },
        );
        try writeParentLookup(writer, recv, can_be_borrowed, dependent_parent != null, .line);
        if (dependent_parent == null and !can_be_borrowed) try writer.print("\tdefer {0s}.mu.Unlock()\n", .{recv});
        try writer.print("\tif {0s}.poison == nil {{\n\t\t{0s}.poison = cause\n", .{recv});
        if (auto_cleanup) {
            if (can_be_borrowed)
                try writer.print("\t\tif {0s}.owner == nil {{ {0s}.cleanup.Stop() }}\n", .{recv})
            else
                try writer.print("\t\t{0s}.cleanup.Stop()\n", .{recv});
        }
        try writer.writeAll("\t}\n");
        if (can_be_borrowed or dependent_parent != null)
            try writer.print("\t{0s}.mu.Unlock()\n\tif parent != nil {{\n\t\tparent.{1s}(cause)\n\t}}\n", .{ recv, names.poison });
        try writer.writeAll("}\n\n");
        if (options.shared_lifecycle) try writeSharedLifecycleWrappers(writer, recv, declaration.name, "");

        if (has_dependent_children) {
            if (can_be_borrowed) {
                try writer.print(
                    "// zigoAcquireChild reserves one dependent child on the ultimate owning handle.\n" ++
                        "func ({0s} *{1s}) zigoAcquireChild(operation string) (unsafe.Pointer, zigoChildHandle, error) {{\n" ++
                        "\tif {0s} == nil {{\n\t\treturn nil, nil, &HandleError{{Operation: operation}}\n\t}}\n" ++
                        "\t{0s}.mu.Lock()\n\tparent := {0s}.owner\n\t{0s}.mu.Unlock()\n" ++
                        "\tif parent != nil {{\n" ++
                        "\t\tchildParent, ok := parent.(zigoChildHandle)\n" ++
                        "\t\tif !ok {{\n\t\t\treturn nil, nil, &HandleError{{Operation: operation}}\n\t\t}}\n" ++
                        "\t\t_, reservation, err := childParent.{3s}(operation)\n" ++
                        "\t\tif err != nil {{\n\t\t\treturn nil, nil, err\n\t\t}}\n" ++
                        "\t\t{0s}.mu.Lock()\n" ++
                        "\t\tif {0s}.closed || {0s}.ptr == nil {{\n\t\t\t{0s}.mu.Unlock()\n\t\t\tchildParent.{4s}()\n\t\t\treservation.{5s}()\n\t\t\treturn nil, nil, &HandleError{{Operation: operation}}\n\t\t}}\n" ++
                        "\t\tif {0s}.poison != nil {{\n\t\t\terr := {0s}.poison.{2s}(operation)\n\t\t\t{0s}.mu.Unlock()\n\t\t\tchildParent.{4s}()\n\t\t\treservation.{5s}()\n\t\t\treturn nil, nil, err\n\t\t}}\n" ++
                        "\t\t{0s}.active++\n\t\tptr := {0s}.ptr\n\t\t{0s}.mu.Unlock()\n\t\treturn ptr, reservation, nil\n\t}}\n" ++
                        "\t{0s}.mu.Lock()\n\tdefer {0s}.mu.Unlock()\n" ++
                        "\tif {0s}.closed || {0s}.ptr == nil {{\n\t\treturn nil, nil, &HandleError{{Operation: operation}}\n\t}}\n" ++
                        "\tif {0s}.poison != nil {{\n\t\treturn nil, nil, {0s}.poison.{2s}(operation)\n\t}}\n" ++
                        "\t{0s}.active++\n\t{0s}.children++\n\treturn {0s}.ptr, {0s}, nil\n}}\n\n" ++
                        "func ({0s} *{1s}) zigoDropChild() {{\n\tif {0s} == nil {{\n\t\treturn\n\t}}\n\t{0s}.mu.Lock()\n\t{0s}.children--\n\t{0s}.mu.Unlock()\n}}\n\n",
                    .{ recv, declaration.name, names.poisoned, names.acquire_child, names.release, names.drop_child },
                );
            } else try writer.print(
                "// zigoAcquireChild reserves one dependent child atomically with the call pin.\n" ++
                    "func ({0s} *{1s}) zigoAcquireChild(operation string) (unsafe.Pointer, zigoChildHandle, error) {{\n" ++
                    "\tif {0s} == nil {{\n\t\treturn nil, nil, &HandleError{{Operation: operation}}\n\t}}\n" ++
                    "\t{0s}.mu.Lock()\n\tdefer {0s}.mu.Unlock()\n" ++
                    "\tif {0s}.closed || {0s}.ptr == nil {{\n\t\treturn nil, nil, &HandleError{{Operation: operation}}\n\t}}\n" ++
                    "\tif {0s}.poison != nil {{\n\t\treturn nil, nil, {0s}.poison.{2s}(operation)\n\t}}\n" ++
                    "\t{0s}.active++\n\t{0s}.children++\n\treturn {0s}.ptr, {0s}, nil\n}}\n\n" ++
                    "func ({0s} *{1s}) zigoDropChild() {{\n\tif {0s} == nil {{\n\t\treturn\n\t}}\n\t{0s}.mu.Lock()\n\t{0s}.children--\n\t{0s}.mu.Unlock()\n}}\n\n",
                .{ recv, declaration.name, names.poisoned },
            );
            if (options.shared_lifecycle) try writer.print(
                "// ZigoAcquireChild reserves a dependent child through the shared lifecycle contract.\n" ++
                    "func ({0s} *{1s}) ZigoAcquireChild(operation string) (unsafe.Pointer, lifecycle.ChildHandle, error) {{ return {0s}.zigoAcquireChild(operation) }}\n" ++
                    "// ZigoDropChild releases a dependent-child reservation.\n" ++
                    "func ({0s} *{1s}) ZigoDropChild() {{ {0s}.zigoDropChild() }}\n\n",
                .{ recv, declaration.name },
            );
        }
        // A borrowed reference is only as open as its parent: it pins the
        // parent for the call, and a panic through it poisons the parent.
        if (has_refs) try writer.print(
            "func ({0s} *{1s}Ref) zigoAcquire(operation string) (unsafe.Pointer, error) {{\n" ++
                "\tif {0s} == nil || {0s}.ptr == nil {{\n\t\treturn nil, &HandleError{{Operation: operation}}\n\t}}\n" ++
                "\tif {0s}.parent != nil {{\n\t\tif _, err := {0s}.parent.zigoAcquire(operation); err != nil {{\n\t\t\treturn nil, err\n\t\t}}\n\t}}\n" ++
                "\treturn {0s}.ptr, nil\n}}\n\n" ++
                "func ({0s} *{1s}Ref) zigoRelease() {{\n\tif {0s} != nil && {0s}.parent != nil {{\n\t\t{0s}.parent.zigoRelease()\n\t}}\n}}\n\n" ++
                "func ({0s} *{1s}Ref) zigoPoison(cause *NativePanicError) {{\n\tif {0s} != nil && {0s}.parent != nil {{\n\t\t{0s}.parent.zigoPoison(cause)\n\t}}\n}}\n\n",
            .{ recv, declaration.name },
        );
        if (has_refs and options.shared_lifecycle) try writeSharedLifecycleWrappers(writer, recv, declaration.name, "Ref");
        if (constructor) |owned| {
            const raw_deinit = try common.rawNameForSemanticAlloc(allocator, program, owned.deinit, owned.type) orelse continue;
            defer allocator.free(raw_deinit);
            const private_name = try naming.camelAlloc(allocator, declaration.name);
            defer allocator.free(private_name);
            // The cleanup state copies what has to be released. It must not
            // reach the handle itself, or the handle stays reachable and the
            // cleanup never runs.
            try writer.print("type {s}CleanupState struct {{\n", .{private_name});
            const state_width = fieldNameWidth(&.{ "ptr", if (dependent_parent != null) "parent" else "", if (owns_callbacks) "callbackHandles" else "" });
            try writeStructField(writer, "ptr", state_width, "unsafe.Pointer");
            if (dependent_parent != null) try writeStructField(writer, "parent", state_width, "zigoChildHandle");
            if (owns_callbacks) try writeStructField(writer, "callbackHandles", state_width, "[]zigoCallbackHandle");
            try writer.writeAll("}\n\n");
            try writer.print("func new{s}(ptr unsafe.Pointer", .{declaration.name});
            if (dependent_parent != null) try writer.writeAll(", parent zigoChildHandle");
            if (owns_callbacks) try writer.writeAll(", callbackHandles []zigoCallbackHandle");
            try writer.print(") *{s} {{\n\tvalue := &{s}{{ptr: ptr", .{ declaration.name, declaration.name });
            if (dependent_parent != null) try writer.writeAll(", parent: parent");
            if (owns_callbacks) try writer.writeAll(", callbackHandles: callbackHandles");
            try writer.print("}}\n\tstate := {s}CleanupState{{ptr: ptr", .{private_name});
            if (dependent_parent != null) try writer.writeAll(", parent: parent");
            if (owns_callbacks) try writer.writeAll(", callbackHandles: callbackHandles");
            try writer.print("}}\n\tvalue.cleanup = runtime.AddCleanup(value, cleanup{s}, state)\n\treturn value\n}}\n\n", .{declaration.name});
            try writer.print("func cleanup{s}(state {s}CleanupState) {{\n\tif state.ptr != nil {{\n\t\t", .{ declaration.name, private_name });
            try public_writers.writeRawReferencePrefix(writer, options);
            try writer.print("{s}(state.ptr)\n\t}}\n", .{raw_deinit});
            if (owns_callbacks) try writer.writeAll("\tfor _, handle := range state.callbackHandles {\n\t\tdeleteCallbackHandle(handle)\n\t}\n");
            if (dependent_parent != null) try writer.print("\tif state.parent != nil {{\n\t\tstate.parent.{s}()\n\t}}\n", .{names.drop_child});
            try writer.writeAll("}\n\n");
            // Close only marks the handle. Whoever then finds it closed with
            // no call inside native -- Close itself, or the last zigoRelease --
            // runs the cleanup, so Close never waits and never makes another
            // caller wait. `closed` carries idempotency: a second Close finds
            // it set and returns.
            try writer.print("// Close releases the native {0s} resources. It is safe to call more than once.\n", .{declaration.name});
            if (has_dependent_children)
                try writer.print("// It returns *HandleInUseError while dependent children remain open.\n", .{})
            else
                try writer.print("// The error result is always nil; it exists so {s} satisfies io.Closer.\n", .{declaration.name});
            try writer.print(
                "// Close does not wait: a call still inside native keeps the resources until it\n" ++
                    "// returns, and every call made after Close fails with *HandleError.\n" ++
                    "func ({0s} *{1s}) Close() error {{\n\tif {0s} == nil {{\n\t\treturn nil\n\t}}\n" ++
                    "\t{0s}.mu.Lock()\n\tif {0s}.closed {{\n\t\t{0s}.mu.Unlock()\n\t\treturn nil\n\t}}\n",
                .{ recv, declaration.name },
            );
            if (can_be_borrowed) {
                try writer.print("\tif {0s}.owner != nil {{\n", .{recv});
                try writeInUseCheck(writer, recv, declaration.name, "active", "\t\t");
                try writer.print("\t\t{0s}.closed = true\n\t\t{0s}.ptr = nil\n\t\t{0s}.owner = nil\n\t\t{0s}.mu.Unlock()\n\t\treturn nil\n\t}}\n", .{recv});
            }
            if (has_dependent_children) try writeInUseCheck(writer, recv, declaration.name, "children", "\t");
            if (returns_borrowed_views) try writeInUseCheck(writer, recv, declaration.name, "active", "\t");
            try writer.print(
                "\t{0s}.closed = true\n\t{0s}.cleanup.Stop()\n" ++
                    "\tstate, release := {0s}.zigoTakeLocked()\n\t{0s}.mu.Unlock()\n\tif release {{\n\t\tcleanup{1s}(state)\n\t}}\n" ++
                    "\truntime.KeepAlive({0s})\n\treturn nil\n}}\n\n",
                .{ recv, declaration.name },
            );
            try writer.print(
                "// zigoTakeLocked hands out what is left to release once {0s} is closed and no\n" ++
                    "// call is inside native; mu must be held. A poisoned handle keeps its native\n" ++
                    "// object: releasing state a panic left half-changed could fault, so it leaks.\n" ++
                    "func ({0s} *{1s}) zigoTakeLocked() ({2s}CleanupState, bool) {{\n" ++
                    "\tif !{0s}.closed || {0s}.active != 0 || {0s}.ptr == nil {{\n\t\treturn {2s}CleanupState{{}}, false\n\t}}\n" ++
                    "\tstate := {2s}CleanupState{{ptr: {0s}.ptr",
                .{ recv, declaration.name, private_name },
            );
            if (owns_callbacks) try writer.print(", callbackHandles: {0s}.callbackHandles", .{recv});
            if (dependent_parent != null) try writer.print(", parent: {0s}.parent", .{recv});
            try writer.print("}}\n\t{0s}.ptr = nil\n", .{recv});
            if (owns_callbacks) try writer.print("\t{0s}.callbackHandles = nil\n", .{recv});
            if (dependent_parent != null) try writer.print("\t{0s}.parent = nil\n", .{recv});
            try writer.print("\tif {0s}.poison != nil {{\n\t\tstate.ptr = nil\n\t}}\n\treturn state, true\n}}\n\n", .{recv});
        } else if (can_be_borrowed) {
            try writer.print(
                "// Close detaches this borrowed {1s} view without releasing native resources.\n" ++
                    "func ({0s} *{1s}) Close() error {{\n\tif {0s} == nil {{ return nil }}\n\t{0s}.mu.Lock()\n" ++
                    "\tif {0s}.closed {{ {0s}.mu.Unlock(); return nil }}\n",
                .{ recv, declaration.name },
            );
            try writeInUseCheck(writer, recv, declaration.name, "active", "\t");
            try writer.print("\t{0s}.closed = true\n\t{0s}.ptr = nil\n\t{0s}.owner = nil\n\t{0s}.mu.Unlock()\n\treturn nil\n}}\n\n", .{recv});
        }
    }
}

/// The lifecycle methods a handle calls on its parent: the exported spelling
/// under the shared lifecycle contract, the package-private one otherwise.
const LifecycleNames = struct {
    poisoned: []const u8,
    acquire: []const u8,
    release: []const u8,
    poison: []const u8,
    acquire_child: []const u8,
    drop_child: []const u8,

    fn of(options: emit.Options) LifecycleNames {
        if (options.shared_lifecycle) return .{
            .poisoned = "Poisoned",
            .acquire = "ZigoAcquire",
            .release = "ZigoRelease",
            .poison = "ZigoPoison",
            .acquire_child = "ZigoAcquireChild",
            .drop_child = "ZigoDropChild",
        };
        return .{
            .poisoned = "poisoned",
            .acquire = "zigoAcquire",
            .release = "zigoRelease",
            .poison = "zigoPoison",
            .acquire_child = "zigoAcquireChild",
            .drop_child = "zigoDropChild",
        };
    }
};

/// Binds `parent` to the handle pinned alongside this one. A borrowed handle
/// may have either an owner or a dependency parent; a purely dependent one
/// only ever has the latter. `mu` is held, so the fields are stable.
fn writeParentLookup(
    writer: *std.Io.Writer,
    recv: []const u8,
    can_be_borrowed: bool,
    has_parent: bool,
    fallback: enum { block, line },
) !void {
    if (can_be_borrowed) {
        try writer.print("\tvar parent zigoHandle\n\tparent = {0s}.owner\n", .{recv});
        if (has_parent) switch (fallback) {
            .block => try writer.print("\tif parent == nil {{\n\t\tparent = {0s}.parent\n\t}}\n", .{recv}),
            .line => try writer.print("\tif parent == nil {{ parent = {0s}.parent }}\n", .{recv}),
        };
    } else if (has_parent) try writer.print("\tparent := {0s}.parent\n", .{recv});
}

/// Close refuses while `counter` calls or children are still inside: it
/// unlocks and reports how many, so the caller can retry once they return.
fn writeInUseCheck(writer: *std.Io.Writer, recv: []const u8, type_name: []const u8, counter: []const u8, indent: []const u8) !void {
    try writer.print(
        "{2s}if {0s}.{3s} != 0 {{\n{2s}\t{3s} := {0s}.{3s}\n{2s}\t{0s}.mu.Unlock()\n" ++
            "{2s}\treturn &HandleInUseError{{Operation: \"{1s}.Close\", Children: {3s}}}\n{2s}}}\n",
        .{ recv, type_name, indent, counter },
    );
}

/// The exported methods that make `{type_name}{suffix}` a `lifecycle.Handle`.
fn writeSharedLifecycleWrappers(writer: *std.Io.Writer, recv: []const u8, type_name: []const u8, suffix: []const u8) !void {
    try writer.print(
        "// ZigoAcquire implements the shared lifecycle handle contract.\n" ++
            "func ({0s} *{1s}{2s}) ZigoAcquire(operation string) (unsafe.Pointer, error) {{ return {0s}.zigoAcquire(operation) }}\n" ++
            "// ZigoRelease implements the shared lifecycle handle contract.\n" ++
            "func ({0s} *{1s}{2s}) ZigoRelease() {{ {0s}.zigoRelease() }}\n" ++
            "// ZigoPoison implements the shared lifecycle handle contract.\n" ++
            "func ({0s} *{1s}{2s}) ZigoPoison(cause *NativePanicError) {{ {0s}.zigoPoison(cause) }}\n\n",
        .{ recv, type_name, suffix },
    );
}

/// The column gofmt aligns struct field types on: the longest name plus one
/// space. Empty names stand for fields this handle does not carry.
fn fieldNameWidth(names: []const []const u8) usize {
    var longest: usize = 0;
    for (names) |name| longest = @max(longest, name.len);
    return longest + 1;
}

fn writeStructField(writer: *std.Io.Writer, name: []const u8, width: usize, type_name: []const u8) !void {
    try writer.print("\t{s}", .{name});
    try writer.splatByteAll(' ', width - name.len);
    try writer.print("{s}\n", .{type_name});
}

/// The handle interface and its two pointer checks. Every projection and
/// operation reaches a handle through this, so it lives with the runtime
/// rather than with the handle types themselves.
pub fn renderGoHandleRuntime(writer: *std.Io.Writer, program: abi.Program, options: emit.Options) !void {
    if (!common.programHasOpaqueTypes(program)) return;
    if (options.shared_lifecycle) {
        try writer.writeAll("type zigoHandle = lifecycle.Handle\n\n");
        if (common.programHasChildConstructors(program)) try writer.writeAll("type zigoChildHandle = lifecycle.ChildHandle\n\n");
        try writer.writeAll("func zigoCheckedPointer(operation string, value zigoHandle) (unsafe.Pointer, error) { return lifecycle.CheckedPointer(operation, value) }\n");
        if (options.emitsHelper("zigoOptionalPointer"))
            try writer.writeAll("func zigoOptionalPointer(operation string, absent bool, value zigoHandle) (unsafe.Pointer, error) { return lifecycle.OptionalPointer(operation, absent, value) }\n");
        return writer.writeAll("func zigoPoisonAfterPanic(err error, handles ...zigoHandle) error { return lifecycle.PoisonAfterPanic(err, handles...) }\n\n");
    }
    try writer.writeAll(
        "// zigoHandle is what every handle and borrowed reference offers a generated\n" ++
            "// call: pin it open for the native call, let it go afterwards, and mark it\n" ++
            "// unusable when the call ended in a Zig panic.\n" ++
            "type zigoHandle interface {\n" ++
            "\tzigoAcquire(operation string) (unsafe.Pointer, error)\n" ++
            "\tzigoRelease()\n" ++
            "\tzigoPoison(cause *NativePanicError)\n" ++
            "}\n\n",
    );
    if (common.programHasChildConstructors(program)) try writer.writeAll(
        "type zigoChildHandle interface {\n" ++
            "\tzigoHandle\n" ++
            "\tzigoAcquireChild(operation string) (unsafe.Pointer, zigoChildHandle, error)\n" ++
            "\tzigoDropChild()\n" ++
            "}\n\n",
    );
    try writer.writeAll(
        "// zigoCheckedPointer pins value open for the rest of the call and hands back\n" ++
            "// its native pointer; the caller defers zigoRelease. A nil, closed, or\n" ++
            "// poisoned handle is the error instead, and nothing is pinned.\n" ++
            "func zigoCheckedPointer(operation string, value zigoHandle) (unsafe.Pointer, error) {\n" ++
            "\treturn value.zigoAcquire(operation)\n" ++
            "}\n\n",
    );
    if (options.emitsHelper("zigoOptionalPointer")) try writer.writeAll(
        "func zigoOptionalPointer(operation string, absent bool, value zigoHandle) (unsafe.Pointer, error) {\n" ++
            "\tif absent {\n" ++
            "\t\treturn nil, nil\n" ++
            "\t}\n" ++
            "\treturn zigoCheckedPointer(operation, value)\n" ++
            "}\n\n",
    );
    try writer.writeAll(
        "// zigoPoisonAfterPanic marks every handle a call reached unusable when that\n" ++
            "// call ended in a Zig panic: the panic unwound the native frames without\n" ++
            "// running their defers, so what is behind those handles is unknown. Any\n" ++
            "// other error passes through untouched.\n" ++
            "func zigoPoisonAfterPanic(err error, handles ...zigoHandle) error {\n" ++
            "\tif cause, ok := err.(*NativePanicError); ok {\n" ++
            "\t\tfor _, handle := range handles {\n" ++
            "\t\t\thandle.zigoPoison(cause)\n" ++
            "\t\t}\n" ++
            "\t}\n" ++
            "\treturn err\n" ++
            "}\n\n",
    );
}
