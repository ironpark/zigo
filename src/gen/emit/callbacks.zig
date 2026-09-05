//! Callback plumbing for both backends: the cgo trampolines and error
//! storage, and the purego callback registry.
const std = @import("std");
const abi = @import("abi");
const semantic = @import("semantic");
const naming = @import("naming");
const common = @import("common.zig");
const emit = @import("emit.zig");
const public_writers = @import("public_writers.zig");
const purego = @import("purego.zig");
const lower = @import("lower");

pub fn renderPuregoCallbackRegistry(allocator: std.mem.Allocator, writer: *std.Io.Writer, program: abi.Program, options: emit.Options) !void {
    const prefix = if (options.raw_colocated) "zigoRaw" else "";
    const has_streams = common.programHasStreams(program);
    const has_callback_errors = common.programHasCallbackErrors(program);
    const has_callback_cancellation = common.programHasCallbackCancellation(program);
    try writer.writeAll(
        "type callbackEntry struct {\n\tmu sync.Mutex\n\tcond *sync.Cond\n\tvalue any\n\tclosing bool\n\tactive int\n\tpanicked bool\n\tpanicValue any\n\tpanicStack []byte\n",
    );
    // Only a binding that can be handed a Go error -- by a stream or by a
    // `go_error` callback -- carries the field, so a registry that cannot be
    // is byte for byte what it always was.
    if (has_streams or has_callback_errors) try writer.writeAll("\tgoErr error\n");
    if (has_callback_cancellation) try writer.writeAll("\tcancel atomic.Pointer[uint32]\n");
    try writer.writeAll(
        "}\n\n" ++
            "// callbackRegistry maps a userdata token to its entry without a global lock,\n// mirroring the sync.Map behind runtime/cgo.Handle on the cgo backend.\n// Delete races an in-flight acquire safely through the entry's closing flag:\n// an acquire either takes active++ before closing is set, in which case\n// DeleteCallbackHandle waits for it to drain, or it observes closing and\n// reports the token as gone.\nvar callbackRegistry sync.Map // uintptr -> *callbackEntry\nvar nextCallbackToken atomic.Uint64\nvar activeCallbackHandles atomic.Int64\n\n",
    );
    if (has_callback_cancellation) try writer.writeAll("var callbackCancelFlags sync.Map // uintptr -> *uint32\n\n");
    try writer.print("// {s}NewCallbackHandle stores a callback value and returns its native userdata token.\nfunc {s}NewCallbackHandle(value any) uintptr {{\n", .{ prefix, prefix });
    try writer.writeAll("\tentry := &callbackEntry{value: value}\n\tentry.cond = sync.NewCond(&entry.mu)\n\ttoken := uintptr(nextCallbackToken.Add(1))\n\tif token == 0 { token = uintptr(nextCallbackToken.Add(1)) }\n\tcallbackRegistry.Store(token, entry)\n\tactiveCallbackHandles.Add(1)\n\treturn token\n}\n\n");
    try writer.print("// {s}DeleteCallbackHandle releases a callback token after in-flight calls finish.\nfunc {s}DeleteCallbackHandle(token uintptr) {{\n", .{ prefix, prefix });
    try writer.writeAll("\tif token == 0 { return }\n\tstored, loaded := callbackRegistry.LoadAndDelete(token)\n\tif !loaded { return }\n\tentry := stored.(*callbackEntry)\n\tentry.mu.Lock()\n\tentry.closing = true\n\tfor entry.active != 0 { entry.cond.Wait() }\n\tentry.value = nil\n\tentry.mu.Unlock()\n\tactiveCallbackHandles.Add(-1)\n}\n\n");
    try writer.print("// {s}ActiveCallbackHandleCount reports the number of live callback tokens.\nfunc {s}ActiveCallbackHandleCount() int64 {{ return activeCallbackHandles.Load() }}\n\n", .{ prefix, prefix });
    if (has_callback_cancellation) try writer.print(
        "// {0s}SetCallbackCancel attaches a call-scoped cancellation flag to token.\n" ++
            "func {0s}SetCallbackCancel(token uintptr, flag *uint32) {{\n\tif flag == nil {{ callbackCancelFlags.Delete(token) }} else {{ callbackCancelFlags.Store(token, flag) }}\n\tstored, loaded := callbackRegistry.Load(token)\n\tif loaded {{ stored.(*callbackEntry).cancel.Store(flag) }}\n}}\n\n" ++
            "func tripCallbackCancel(token uintptr) {{\n\tif stored, loaded := callbackCancelFlags.Load(token); loaded {{ atomic.StoreUint32(stored.(*uint32), 1) }}\n}}\n\n" ++
            "func (entry *callbackEntry) tripCancel() {{\n\tif flag := entry.cancel.Load(); flag != nil {{ atomic.StoreUint32(flag, 1) }}\n}}\n\n",
        .{prefix},
    );
    try writer.writeAll("// record keeps the first panic a callback raised until the generated caller takes it.\nfunc (entry *callbackEntry) record(value any) {\n");
    if (has_callback_cancellation) try writer.writeAll("\tentry.tripCancel()\n");
    try writer.writeAll("\tentry.mu.Lock()\n\tdefer entry.mu.Unlock()\n\tif entry.panicked { return }\n\tentry.panicked = true\n\tentry.panicValue = value\n\tentry.panicStack = debug.Stack()\n}\n\n");
    if (has_streams or has_callback_errors) {
        try writer.writeAll("// recordErr keeps the first error the Go side reported -- a stream that failed\n// to write or read, or a callback that returned one -- until the generated\n// caller takes it. Later crossings are not asked: once a stream has failed the\n// adapter stops using it.\nfunc (entry *callbackEntry) recordErr(err error) {\n");
        if (has_callback_cancellation) try writer.writeAll("\tentry.tripCancel()\n");
        try writer.writeAll("\tentry.mu.Lock()\n\tdefer entry.mu.Unlock()\n\tif entry.goErr == nil { entry.goErr = err }\n}\n\n");
    }
    if (has_streams) {
        try writer.print("// {0s}TakeStreamError returns and clears the error the Go stream behind token reported.\nfunc {0s}TakeStreamError(token uintptr) (error, bool) {{\n", .{prefix});
        try writer.writeAll("\tstored, loaded := callbackRegistry.Load(token)\n\tif !loaded { return nil, false }\n\tentry := stored.(*callbackEntry)\n\tentry.mu.Lock()\n\tdefer entry.mu.Unlock()\n\tif entry.goErr == nil { return nil, false }\n\terr := entry.goErr\n\tentry.goErr = nil\n\treturn err, true\n}\n\n");
    }
    if (has_callback_errors) {
        try writer.print("// {0s}TakeCallbackError returns and clears the error the Go callback behind token returned.\nfunc {0s}TakeCallbackError(token uintptr) (error, bool) {{\n", .{prefix});
        try writer.writeAll("\tstored, loaded := callbackRegistry.Load(token)\n\tif !loaded { return nil, false }\n\tentry := stored.(*callbackEntry)\n\tentry.mu.Lock()\n\tdefer entry.mu.Unlock()\n\tif entry.goErr == nil { return nil, false }\n\terr := entry.goErr\n\tentry.goErr = nil\n\treturn err, true\n}\n\n");
    }
    try writer.print("// {s}TakeCallbackPanic returns and clears the panic the callback behind token recorded.\nfunc {s}TakeCallbackPanic(token uintptr) (any, []byte, bool) {{\n", .{ prefix, prefix });
    try writer.writeAll("\tstored, loaded := callbackRegistry.Load(token)\n\tif !loaded { return nil, nil, false }\n\tentry := stored.(*callbackEntry)\n\tentry.mu.Lock()\n\tdefer entry.mu.Unlock()\n\tif !entry.panicked { return nil, nil, false }\n\tvalue, stack := entry.panicValue, entry.panicStack\n\tentry.panicValue, entry.panicStack, entry.panicked = nil, nil, false\n\treturn value, stack, true\n}\n\n");
    try writer.writeAll("func acquireCallback(token uintptr) (*callbackEntry, any, bool) {\n\tstored, loaded := callbackRegistry.Load(token)\n\tif !loaded { return nil, nil, false }\n\tentry := stored.(*callbackEntry)\n\tentry.mu.Lock()\n\tif entry.closing { entry.mu.Unlock(); return nil, nil, false }\n\tentry.active++\n\tvalue := entry.value\n\tentry.mu.Unlock()\n\treturn entry, value, true\n}\n\nfunc releaseCallback(entry *callbackEntry) {\n\tentry.mu.Lock()\n\tentry.active--\n\tif entry.closing && entry.active == 0 { entry.cond.Broadcast() }\n\tentry.mu.Unlock()\n}\n\n");

    if (programHasWideningCallbackResult(program) or has_streams or has_callback_errors) try writer.writeAll(
        "// callbackResult widens a signed 32-bit callback result to the uintptr\n" ++
            "// every dispatcher must return. The native caller declares the callback as\n" ++
            "// returning int32_t and reads only the low word, so the value round-trips.\n" ++
            "func callbackResult(value int32) uintptr { return uintptr(uint32(value)) }\n\n",
    );
    const count = uniqueCallbackSignatureCount(program);
    for ([_]semantic.StreamDirection{ .writer, .reader }) |direction| {
        if (!common.programHasStreamDirection(program, direction)) continue;
        try writer.print("var stream{s}Pointer uintptr\n", .{common.streamHandleName(direction)});
    }
    try writer.print("var callbackPointers [{d}]uintptr\nvar callbackDispatchersOnce sync.Once\n\nfunc ensureCallbackDispatchers() {{\n\tcallbackDispatchersOnce.Do(func() {{\n", .{count});
    var signature_index: usize = 0;
    for (program.functions) |function| {
        for (function.origin.params, 0..) |parameter, parameter_index| {
            if (parameter.type != .callback or !isFirstCallbackSignatureAt(program, function.origin, parameter_index)) continue;
            try writer.print("\t\tcallbackPointers[{d}] = purego.NewCallback(func(", .{signature_index});
            const callback = parameter.type.callback;
            for (callback.params, 0..) |callback_parameter, index| {
                if (index != 0) try writer.writeAll(", ");
                try writer.print("p{d} ", .{index});
                // A float parameter arrives as its IEEE-754 bit pattern in an
                // integer of the same width; the shim thunk converted it so the
                // Windows callback compiler never sees a floating-point argument.
                if (callback_parameter == .float)
                    try writer.print("uint{d}", .{callback_parameter.float.bits})
                else
                    try public_writers.writeRawGoType(writer, program, callback_parameter);
            }
            // Every dispatcher returns uintptr, including the ones whose Zig
            // callback returns nothing. Windows compiles callbacks through
            // `syscall.NewCallback`, which rejects any function that does not
            // have exactly one pointer-sized result; a narrower result is not
            // an option, and a void one even less so. The C caller reads only
            // the low word, so an int32 result survives the widening on both
            // supported architectures, and a void callback's value is ignored.
            try writer.writeAll(") (result uintptr) {\n");
            const userdata_index = callback.params.len - 1;
            try writer.print("\t\t\tentry, stored, ok := acquireCallback(uintptr(p{d}))\n\t\t\tif !ok {{ ", .{userdata_index});
            if (has_callback_cancellation) try writer.print("tripCallbackCancel(uintptr(p{d})); ", .{userdata_index});
            try writer.writeAll("return ");
            try writeCallbackFailureValue(writer, callback.@"return".*, false, callbackFailureResult(program, parameter));
            try writer.writeAll(" }\n\t\t\tdefer releaseCallback(entry)\n");
            // Recovered after the entry is acquired so the panic has somewhere
            // to be recorded; nothing before this point can panic.
            try writer.writeAll("\t\t\tdefer func() { if value := recover(); value != nil { entry.record(value); result = ");
            try writeCallbackFailureValue(writer, callback.@"return".*, true, callbackFailureResult(program, parameter));
            try writer.writeAll(" } }()\n");
            const widens = callbackResultWidens(callback.@"return".*);
            // A `go_error` signature stores a Go function with a wider result,
            // so the assertion has to name that type instead. One dispatcher
            // serves the whole signature, and `go_error` is a property of the
            // signature rather than of one parameter, so there is exactly one
            // stored type to name.
            const go_error = common.callbackSignatureHasGoError(program, callback);
            try writer.writeAll("\t\t\tcallback := stored.(func(");
            for (callback.params[0..userdata_index], 0..) |callback_parameter, index| {
                if (index != 0) try writer.writeAll(", ");
                try public_writers.writeRawGoType(writer, program, callback_parameter);
            }
            try writer.writeByte(')');
            if (go_error) {
                try writer.writeAll(" (");
                try public_writers.writeRawGoType(writer, program, callback.@"return".*);
                try writer.writeAll(", error)");
            } else if (callback.@"return".* != .void) {
                try writer.writeByte(' ');
                try public_writers.writeRawGoType(writer, program, callback.@"return".*);
            }
            try writer.writeAll(")\n\t\t\t");
            if (go_error) try writer.writeAll("value, err := ");
            if (!go_error and widens) try writer.writeAll("return callbackResult(");
            try writer.writeAll("callback(");
            for (callback.params[0..userdata_index], 0..) |callback_parameter, index| {
                if (index != 0) try writer.writeAll(", ");
                if (callback_parameter == .float)
                    try writer.print("math.Float{d}frombits(p{d})", .{ callback_parameter.float.bits, index })
                else
                    try writer.print("p{d}", .{index});
            }
            try writer.writeAll(")");
            if (go_error) {
                // Without a declared domain fallback, `-5` is the Go error,
                // distinct from `-3` (panic) and `-4` (deleted token).
                try writer.writeAll("\n\t\t\tif err != nil { entry.recordErr(err); return ");
                if (callbackFailureResult(program, parameter)) |fallback|
                    try writer.print("callbackResult({d})", .{fallback})
                else
                    try writer.writeAll("callbackResult(-5)");
                try writer.writeAll(" }\n\t\t\treturn callbackResult(value)");
            } else if (widens) {
                try writer.writeAll(")");
            } else {
                try writer.writeAll("\n\t\t\treturn 0");
            }
            try writer.writeAll("\n\t\t})\n");
            signature_index += 1;
        }
    }
    try purego.writeStreamDispatchers(writer, program);
    try writer.writeAll("\t})\n}\n\n");
    for ([_]semantic.StreamDirection{ .writer, .reader }) |direction| {
        if (!common.programHasStreamDirection(program, direction)) continue;
        const name = common.streamHandleName(direction);
        try writer.print(
            "// {0s}Stream{1s}CallbackPointer returns the permanent dispatcher every {2s} stream is called back through.\n" ++
                "func {0s}Stream{1s}CallbackPointer() uintptr {{ ensureCallbackDispatchers(); return stream{1s}Pointer }}\n",
            .{ prefix, name, if (direction == .writer) "io.Writer" else "io.Reader" },
        );
    }
    for (0..count) |index|
        try writer.print("// {s}CallbackPointer{d} returns the permanent dispatcher for callback ABI signature {d}.\nfunc {s}CallbackPointer{d}() uintptr {{ ensureCallbackDispatchers(); return callbackPointers[{d}] }}\n", .{ prefix, index, index, prefix, index, index });
    try writer.print("// {s}CallbackDispatcherCount reports the number of unique callback ABI dispatchers.\nfunc {s}CallbackDispatcherCount() int {{ ensureCallbackDispatchers(); return len(callbackPointers) }}\n", .{ prefix, prefix });
    try writer.writeByte('\n');
    _ = allocator;
}

/// The signed 32-bit result is the callback ABI that carries the historical
/// sentinels. An explicit domain fallback may also name another scalar shape.
fn callbackResultWidens(node: semantic.TypeNode) bool {
    return node == .int and node.int.signed and node.int.bits == 32;
}

fn writeCallbackFailureValue(writer: *std.Io.Writer, node: semantic.TypeNode, panic_value: bool, fallback: ?i128) !void {
    if (fallback) |value| {
        if (callbackResultWidens(node))
            try writer.print("callbackResult({d})", .{value})
        else
            try writer.print("uintptr({d})", .{value});
        return;
    }
    if (callbackResultWidens(node))
        try writer.writeAll(if (panic_value) "callbackResult(-3)" else "callbackResult(-4)")
    else
        try writer.writeAll("0");
}

pub fn callbackFailureResult(program: abi.Program, parameter: semantic.Parameter) ?i128 {
    const failure = semantic.callbackFailure(program.types, parameter) orelse return null;
    return failure.result;
}

/// True when any callback carries a float parameter, and so any dispatcher has
/// to rebuild one from its bits.
pub fn programHasFloatCallbackParam(program: abi.Program) bool {
    for (program.functions) |function| {
        for (function.origin.params) |parameter| {
            if (parameter.type != .callback) continue;
            if (common.callbackHasFloatParam(parameter.type.callback)) return true;
        }
    }
    return false;
}

/// True when any callback signature returns the signed 32-bit ABI, which is
/// the only one whose dispatcher needs the widening helper.
fn programHasWideningCallbackResult(program: abi.Program) bool {
    for (program.functions) |function| {
        for (function.origin.params) |parameter| {
            if (parameter.type != .callback) continue;
            if (callbackResultWidens(parameter.type.callback.@"return".*)) return true;
        }
    }
    return false;
}

fn uniqueCallbackSignatureCount(program: abi.Program) usize {
    var count: usize = 0;
    for (program.functions) |function| {
        for (function.origin.params, 0..) |parameter, parameter_index| {
            if (parameter.type == .callback and isFirstCallbackSignatureAt(program, function.origin, parameter_index)) count += 1;
        }
    }
    return count;
}

pub fn callbackSignatureIndex(program: abi.Program, wanted: semantic.Parameter) usize {
    var index: usize = 0;
    for (program.functions) |function| {
        for (function.origin.params, 0..) |parameter, parameter_index| {
            if (parameter.type != .callback or !isFirstCallbackSignatureAt(program, function.origin, parameter_index)) continue;
            if (lower.callbackSignatureEqual(parameter.type.callback, wanted.type.callback) and
                callbackFailureResult(program, parameter) == callbackFailureResult(program, wanted)) return index;
            index += 1;
        }
    }
    unreachable;
}

fn isFirstCallbackSignatureAt(program: abi.Program, origin: *const semantic.SemanticFn, parameter_index: usize) bool {
    const wanted = origin.params[parameter_index];
    for (program.functions) |function| {
        for (function.origin.params, 0..) |parameter, candidate_index| {
            if (function.origin == origin and candidate_index == parameter_index) return true;
            if (parameter.type == .callback and lower.callbackSignatureEqual(parameter.type.callback, wanted.type.callback) and
                callbackFailureResult(program, parameter) == callbackFailureResult(program, wanted)) return false;
        }
    }
    unreachable;
}

/// The one place a Go error crossing back from a callback or a stream is
/// kept. Both live on the same `CallbackState` field: the storage rule is the
/// same either way -- the first error wins and the generated caller takes it
/// once the native call has returned -- and only the name of the taker says
/// which side the caller is asking about.
fn renderCgoCallbackErrorStorage(writer: *std.Io.Writer, program: abi.Program, prefix: []const u8) !void {
    const has_streams = common.programHasStreams(program);
    const has_callback_errors = common.programHasCallbackErrors(program);
    if (!has_streams and !has_callback_errors) return;
    try writer.print(
        "// recordErr keeps the first error the Go side reported -- a stream that\n" ++
            "// failed to write or read, or a callback that returned one -- until the\n" ++
            "// generated caller takes it. Later crossings are not asked: once a stream\n" ++
            "// has failed the adapter stops using it.\n" ++
            "func (state *{0s}CallbackState) recordErr(err error) {{\n{1s}\tstate.mu.Lock()\n\tdefer state.mu.Unlock()\n\tif state.err == nil {{\n\t\tstate.err = err\n\t}}\n}}\n\n",
        .{ prefix, if (common.programHasCallbackCancellation(program)) "\tstate.tripCancel()\n" else "" },
    );
    if (has_streams) try writer.print(
        "// {0s}TakeStreamError returns and clears the error the Go stream behind handle reported.\n" ++
            "func {0s}TakeStreamError(handle cgo.Handle) (error, bool) {{\n\tstate := handle.Value().(*{0s}CallbackState)\n\tstate.mu.Lock()\n\tdefer state.mu.Unlock()\n\tif state.err == nil {{\n\t\treturn nil, false\n\t}}\n\terr := state.err\n\tstate.err = nil\n\treturn err, true\n}}\n\n",
        .{prefix},
    );
    if (has_callback_errors) try writer.print(
        "// {0s}TakeCallbackError returns and clears the error the Go callback behind handle returned.\n" ++
            "func {0s}TakeCallbackError(handle cgo.Handle) (error, bool) {{\n\tstate := handle.Value().(*{0s}CallbackState)\n\tstate.mu.Lock()\n\tdefer state.mu.Unlock()\n\tif state.err == nil {{\n\t\treturn nil, false\n\t}}\n\terr := state.err\n\tstate.err = nil\n\treturn err, true\n}}\n\n",
        .{prefix},
    );
}

/// The cgo trampolines. Each recovers a panic in the Go callback -- a panic
/// cannot unwind native frames -- and records it on the callback's state so
/// the generated caller can rethrow it once the native call has returned.
/// The two fixed `//export` trampolines a stream parameter is called back
/// through. They are not user callbacks: the signature is the generator's, one
/// per direction for the whole binding, so the shim can bind them by name and
/// carry only the userdata token across the C signature.
///
/// A Go error is recorded rather than returned: the native side has no channel
/// for it beyond "this failed", so the value is kept on the state and the
/// public wrapper hands it back after the call. A panic takes the existing
/// `-3` path, and the adapter never calls back into a frame that raised one.
fn renderCgoStreamTrampolines(allocator: std.mem.Allocator, writer: *std.Io.Writer, program: abi.Program, options: emit.Options) !void {
    const prefix = if (options.raw_colocated) "zigoRaw" else "";
    if (common.programHasStreamDirection(program, .writer)) {
        const name = try common.streamTrampolineNameAlloc(allocator, program, .writer);
        defer allocator.free(name);
        try writer.print(
            "//export {0s}\n" ++
                "func {0s}(p0 *C.uint8_t, p1 C.size_t, p2 C.size_t) (result C.int32_t) {{\n" ++
                "\tstate := cgo.Handle(p2).Value().(*{1s}CallbackState)\n" ++
                "\tdefer func() {{\n\t\tif value := recover(); value != nil {{\n\t\t\tstate.record(value)\n\t\t\tresult = C.int32_t(-3)\n\t\t}}\n\t}}()\n" ++
                "\tn, err := state.Writer.Write(unsafe.Slice((*byte)(unsafe.Pointer(p0)), int(p1)))\n" ++
                "\tif err == nil && n != int(p1) {{\n\t\terr = io.ErrShortWrite\n\t}}\n" ++
                "\tif err != nil {{\n\t\tstate.recordErr(err)\n\t\treturn C.int32_t(-1)\n\t}}\n" ++
                "\treturn C.int32_t(0)\n}}\n\n",
            .{ name, prefix },
        );
    }
    if (common.programHasStreamDirection(program, .reader)) {
        const name = try common.streamTrampolineNameAlloc(allocator, program, .reader);
        defer allocator.free(name);
        try writer.print(
            "//export {0s}\n" ++
                "func {0s}(p0 *C.uint8_t, p1 C.size_t, p2 C.size_t) (result C.int32_t) {{\n" ++
                "\tstate := cgo.Handle(p2).Value().(*{1s}CallbackState)\n" ++
                "\tdefer func() {{\n\t\tif value := recover(); value != nil {{\n\t\t\tstate.record(value)\n\t\t\tresult = C.int32_t(-3)\n\t\t}}\n\t}}()\n" ++
                "\tn, err := state.Reader.Read(unsafe.Slice((*byte)(unsafe.Pointer(p0)), int(p1)))\n" ++
                // A short read is not an end: only a zero count with nothing
                // more to come is, and only io.EOF says so. Any other error is
                // the caller's to see.
                "\tif n > 0 {{\n\t\treturn C.int32_t(n)\n\t}}\n" ++
                "\tif err == nil || err == io.EOF {{\n\t\treturn C.int32_t(0)\n\t}}\n" ++
                "\tstate.recordErr(err)\n\treturn C.int32_t(-1)\n}}\n\n",
            .{ name, prefix },
        );
    }
}

pub fn renderRawCallbacks(allocator: std.mem.Allocator, writer: *std.Io.Writer, program: abi.Program, options: emit.Options) !void {
    if (!common.programHasCallbacks(program)) return;
    const prefix = if (options.raw_colocated) "zigoRaw" else "";
    const has_streams = common.programHasStreams(program);
    const has_callback_cancellation = common.programHasCallbackCancellation(program);
    const has_callback_failure_result = common.programHasCallbackFailureResult(program);
    try writer.print(
        "// {0s}CallbackState carries one Go callback across the native boundary, and\n" ++
            "// the panic it raises there until the generated caller rethrows it. The\n" ++
            "// trampoline has to recover: a panic cannot unwind native frames.\n" ++
            "type {0s}CallbackState struct {{\n\tFn       any\n{1s}\tmu       sync.Mutex\n\tvalue    any\n\tstack    []byte\n\tpanicked bool\n{2s}{3s}}}\n\n",
        .{
            prefix,
            if (has_streams) "\tWriter   io.Writer\n\tReader   io.Reader\n" else "",
            if (has_streams or common.programHasCallbackErrors(program)) "\terr      error\n" else "",
            if (has_callback_cancellation) "\tcancel   atomic.Pointer[uint32]\n" else "",
        },
    );
    if (has_callback_cancellation) try writer.print(
        "var callbackCancelFlags sync.Map // uintptr -> *uint32\n\n" ++
            "// {0s}SetCallbackCancel attaches a call-scoped cancellation flag to handle.\n" ++
            "func {0s}SetCallbackCancel(handle cgo.Handle, flag *uint32) {{\n\tif flag == nil {{ callbackCancelFlags.Delete(uintptr(handle)) }} else {{ callbackCancelFlags.Store(uintptr(handle), flag) }}\n\thandle.Value().(*{0s}CallbackState).cancel.Store(flag)\n}}\n\n" ++
            "func tripCallbackCancel(handle uintptr) {{\n\tif stored, loaded := callbackCancelFlags.Load(handle); loaded {{ atomic.StoreUint32(stored.(*uint32), 1) }}\n}}\n\n" ++
            "func (state *{0s}CallbackState) tripCancel() {{\n\tif flag := state.cancel.Load(); flag != nil {{ atomic.StoreUint32(flag, 1) }}\n}}\n\n",
        .{prefix},
    );
    if (has_callback_cancellation or has_callback_failure_result) try writer.print(
        "func callbackState(handle cgo.Handle) (state *{0s}CallbackState, ok bool) {{\n\tdefer func() {{ if recover() != nil {{ state, ok = nil, false }} }}()\n\tstate, ok = handle.Value().(*{0s}CallbackState)\n\treturn state, ok\n}}\n\n",
        .{prefix},
    );
    try writer.print(
        "func (state *{0s}CallbackState) record(value any) {{\n{1s}\tstate.mu.Lock()\n\tdefer state.mu.Unlock()\n\tif state.panicked {{\n\t\treturn\n\t}}\n\tstate.panicked = true\n\tstate.value = value\n\tstate.stack = debug.Stack()\n}}\n\n" ++
            "// {0s}TakeCallbackPanic returns and clears the panic the callback behind handle recorded.\n" ++
            "func {0s}TakeCallbackPanic(handle cgo.Handle) (any, []byte, bool) {{\n\tstate := handle.Value().(*{0s}CallbackState)\n\tstate.mu.Lock()\n\tdefer state.mu.Unlock()\n\tif !state.panicked {{\n\t\treturn nil, nil, false\n\t}}\n\tvalue, stack := state.value, state.stack\n\tstate.value, state.stack, state.panicked = nil, nil, false\n\treturn value, stack, true\n}}\n\n",
        .{
            prefix,
            if (has_callback_cancellation) "\tstate.tripCancel()\n" else "",
        },
    );
    try renderCgoCallbackErrorStorage(writer, program, prefix);
    if (has_streams) try renderCgoStreamTrampolines(allocator, writer, program, options);
    for (program.functions) |function| {
        for (function.origin.params, 0..) |parameter, parameter_index| {
            if (parameter.type != .callback) continue;
            const callback = parameter.type.callback;
            if (!callback.has_userdata or callback.params.len == 0) return error.CallbackRequiresUserdata;
            const name = try common.callbackTrampolineNameAlloc(allocator, function, parameter_index);
            defer allocator.free(name);
            try writer.print("//export {s}\nfunc {s}(", .{ name, name });
            for (callback.params, 0..) |callback_parameter, index| {
                if (index != 0) try writer.writeAll(", ");
                try writer.print("p{d} C.", .{index});
                try common.writeCgoType(writer, common.semanticScalar(program, callback_parameter));
            }
            if (callback.@"return".* == .void) {
                try writer.writeByte(')');
            } else {
                try writer.writeAll(") (result C.");
                try common.writeCgoType(writer, common.semanticScalar(program, callback.@"return".*));
                try writer.writeByte(')');
            }
            try writer.writeAll(" {\n");
            if (has_callback_cancellation or has_callback_failure_result) {
                try writer.print("\tstate, ok := callbackState(cgo.Handle(p{d}))\n\tif !ok {{\n", .{callback.params.len - 1});
                if (has_callback_cancellation) try writer.print("\t\ttripCallbackCancel(uintptr(p{d}))\n", .{callback.params.len - 1});
                if (callback.@"return".* != .void) {
                    try writer.writeAll("\t\treturn C.");
                    try common.writeCgoType(writer, common.semanticScalar(program, callback.@"return".*));
                    try writer.writeByte('(');
                    if (callbackFailureResult(program, parameter)) |fallback|
                        try writer.print("{d}", .{fallback})
                    else if (callbackResultWidens(callback.@"return".*))
                        try writer.writeAll("-4")
                    else
                        try writer.writeByte('0');
                    try writer.writeAll(")\n");
                } else {
                    try writer.writeAll("\t\treturn\n");
                }
                try writer.writeAll("\t}\n");
            } else {
                try writer.print("\tstate := cgo.Handle(p{d}).Value().(*{s}CallbackState)\n", .{ callback.params.len - 1, prefix });
            }
            try writer.writeAll("\tdefer func() {\n\t\tif value := recover(); value != nil {\n\t\t\tstate.record(value)\n");
            if (callback.@"return".* != .void) {
                if (callbackFailureResult(program, parameter)) |fallback| {
                    try writer.writeAll("\t\t\tresult = C.");
                    try common.writeCgoType(writer, common.semanticScalar(program, callback.@"return".*));
                    try writer.print("({d})\n", .{fallback});
                } else if (callback.@"return".* == .int and callback.@"return".int.signed and callback.@"return".int.bits == 32) {
                    try writer.writeAll("\t\t\tresult = C.int32_t(-3)\n");
                } else {
                    try writer.writeAll("\t\t\tresult = 0\n");
                }
            }
            const go_error = common.callbackHasGoError(program, parameter);
            try writer.writeAll("\t\t}\n\t}()\n\tcallback := state.Fn.(func(");
            const value_count = callback.params.len - 1;
            for (callback.params[0..value_count], 0..) |callback_parameter, index| {
                if (index != 0) try writer.writeAll(", ");
                try public_writers.writeRawGoType(writer, program, callback_parameter);
            }
            try writer.writeByte(')');
            if (go_error) {
                try writer.writeAll(" (");
                try public_writers.writeRawGoType(writer, program, callback.@"return".*);
                try writer.writeAll(", error)");
            } else if (callback.@"return".* != .void) {
                try writer.writeByte(' ');
                try public_writers.writeRawGoType(writer, program, callback.@"return".*);
            }
            try writer.writeAll(")\n\t");
            if (go_error) {
                try writer.writeAll("value, err := ");
            } else if (callback.@"return".* != .void) {
                try writer.writeAll("return C.");
                try common.writeCgoType(writer, common.semanticScalar(program, callback.@"return".*));
                try writer.writeByte('(');
            }
            try writer.writeAll("callback(");
            for (callback.params[0..value_count], 0..) |callback_parameter, index| {
                if (index != 0) try writer.writeAll(", ");
                try public_writers.writeRawGoType(writer, program, callback_parameter);
                try writer.print("(p{d})", .{index});
            }
            try writer.writeAll(")");
            if (!go_error) {
                if (callback.@"return".* != .void) try writer.writeByte(')');
                try writer.writeAll("\n}\n\n");
                continue;
            }
            // The error costs the result: the callback's declared fallback,
            // or `-5` by default, says that the Go side failed. The value the
            // callback computed is not the one the native caller reads.
            try writer.writeAll("\n\tif err != nil {\n\t\tstate.recordErr(err)\n\t\treturn C.");
            try common.writeCgoType(writer, common.semanticScalar(program, callback.@"return".*));
            if (callbackFailureResult(program, parameter)) |fallback|
                try writer.print("({d})\n", .{fallback})
            else
                try writer.writeAll("(-5)\n");
            try writer.writeAll("\t}\n\treturn C.");
            try common.writeCgoType(writer, common.semanticScalar(program, callback.@"return".*));
            try writer.writeAll("(value)\n}\n\n");
        }
    }
}
