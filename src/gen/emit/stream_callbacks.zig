//! Stream callback contracts and backend-specific ABI entry points.
//! Handle registries stay in callbacks.zig; library calls stay in purego.zig.
const std = @import("std");
const abi = @import("abi");
const common = @import("common.zig");
const emit = @import("emit.zig");

pub fn renderStreamRead(writer: *std.Io.Writer) !void {
    try writer.writeAll(
        "// readStream preserves terminal errors and bounds retries for empty reads.\n" ++
            "func readStream(reader io.Reader, buffer []byte, terminal *error) (int, error) {\n" ++
            "\tif *terminal != nil { return 0, *terminal }\n" ++
            "\tfor attempt := 0; attempt < 100; attempt++ {\n" ++
            "\t\tn, err := reader.Read(buffer)\n" ++
            "\t\tif n < 0 || n > len(buffer) { n, err = 0, io.ErrShortBuffer }\n" ++
            "\t\tif err != nil { *terminal = err }\n" ++
            "\t\tif n != 0 || err != nil { return n, err }\n" ++
            "\t}\n\t*terminal = io.ErrNoProgress\n\treturn 0, *terminal\n}\n\n",
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
pub fn renderCgoStreamTrampolines(allocator: std.mem.Allocator, writer: *std.Io.Writer, program: abi.Program, options: emit.Options) !void {
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
                "\tn, err := readStream(state.Reader, unsafe.Slice((*byte)(unsafe.Pointer(p0)), int(p1)), &state.readTerminal)\n" ++
                // A short read is not an end: only a zero count with nothing
                // more to come is, and only io.EOF says so. Any other error is
                // the caller's to see.
                "\tif err != nil && err != io.EOF {{ state.recordErr(err) }}\n" ++
                "\tif n > 0 {{\n\t\treturn C.int32_t(n)\n\t}}\n" ++
                "\tif err == io.EOF {{\n\t\treturn C.int32_t(0)\n\t}}\n" ++
                "\treturn C.int32_t(-1)\n}}\n\n",
            .{ name, prefix },
        );
    }
}

/// The two fixed purego dispatchers a stream parameter is called back through.
/// They mirror the cgo trampolines exactly -- same result codes, same rules
/// about short writes and end of stream -- because the shim adapter above them
/// is the same code on both backends.
pub fn writeStreamDispatchers(writer: *std.Io.Writer, program: abi.Program) !void {
    if (common.programHasStreamDirection(program, .writer)) try writer.writeAll(
        "\t\tstreamWriterPointer = purego.NewCallback(func(p0 unsafe.Pointer, p1 uintptr, p2 uintptr) (result uintptr) {\n" ++
            "\t\t\tentry, stored, ok := acquireCallback(p2)\n" ++
            "\t\t\tif !ok { return callbackResult(-4) }\n" ++
            "\t\t\tdefer releaseCallback(entry)\n" ++
            "\t\t\tdefer func() { if value := recover(); value != nil { entry.record(value); result = callbackResult(-3) } }()\n" ++
            "\t\t\tn, err := stored.(io.Writer).Write(unsafe.Slice((*byte)(p0), int(p1)))\n" ++
            "\t\t\tif err == nil && n != int(p1) { err = io.ErrShortWrite }\n" ++
            "\t\t\tif err != nil { entry.recordErr(err); return callbackResult(-1) }\n" ++
            "\t\t\treturn callbackResult(0)\n" ++
            "\t\t})\n",
    );
    if (common.programHasStreamDirection(program, .reader)) try writer.writeAll(
        "\t\tstreamReaderPointer = purego.NewCallback(func(p0 unsafe.Pointer, p1 uintptr, p2 uintptr) (result uintptr) {\n" ++
            "\t\t\tentry, stored, ok := acquireCallback(p2)\n" ++
            "\t\t\tif !ok { return callbackResult(-4) }\n" ++
            "\t\t\tdefer releaseCallback(entry)\n" ++
            "\t\t\tdefer func() { if value := recover(); value != nil { entry.record(value); result = callbackResult(-3) } }()\n" ++
            "\t\t\tn, err := readStream(stored.(io.Reader), unsafe.Slice((*byte)(p0), int(p1)), &entry.readTerminal)\n" ++
            "\t\t\tif err != nil && err != io.EOF { entry.recordErr(err) }\n" ++
            "\t\t\tif n > 0 { return callbackResult(int32(n)) }\n" ++
            "\t\t\tif err == io.EOF { return callbackResult(0) }\n" ++
            "\t\t\treturn callbackResult(-1)\n" ++
            "\t\t})\n",
    );
}
