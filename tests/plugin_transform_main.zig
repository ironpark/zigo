const std = @import("std");
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    try std.Io.Dir.cwd().createDirPath(init.io, args[1]);
    var output = try std.Io.Dir.cwd().openDir(init.io, args[1], .{});
    defer output.close(init.io);
    const result = try std.process.run(init.arena.allocator(), init.io, .{ .argv = &.{
        args[3],           "generate",                                                           "--semantic",    args[4],           "--output",    args[1],
        "--package",       "custom",                                                             "--prefix",      "zg",              "--go-module", "example.com/custom",
        "--backend",       args[2],                                                              "--include-dir", "${SRCDIR}/../..", "--ldflags",   "-lm",
        "--plugin-config", "{\"CONTRACT\":{\"customize\":true},\"OUTPUTS\":{\"enabled\":true}}",
    } });
    if (result.term != .exited or result.term.exited != 0) {
        std.debug.print("{s}", .{result.stderr});
        return error.GenerationFailed;
    }
    const tag = try output.readFileAlloc(init.io, "build_tag.go", init.arena.allocator(), .limited(1024));
    if (!std.mem.eql(u8, tag, "//go:build ignore\n\n")) return error.ArtifactWasFormatted;
    try output.writeFile(init.io, .{ .sub_path = "go.mod", .data = "module example.com/custom\n\ngo 1.24\n\nrequire github.com/ebitengine/purego v0.10.2\n" });
    try output.writeFile(init.io, .{ .sub_path = "custom/roundtrip_test.go", .data = @embedFile("plugin_transform/roundtrip_test.go") });
    try output.writeFile(init.io, .{ .sub_path = "custom/load_test.go", .data = if (std.mem.eql(u8, args[2], "cgo"))
        "package custom\nfunc loadTestLibrary(_ string) error { return nil }\n"
    else
        "package custom\nimport \"path/filepath\"\nfunc loadTestLibrary(path string) error { if !filepath.IsAbs(path) { path = filepath.Join(\"..\", path) }; return LoadLibrary(path) }\n" });
}
