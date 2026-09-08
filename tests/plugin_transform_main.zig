const std = @import("std");
const generator = @import("generator");
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    try std.Io.Dir.cwd().createDirPath(init.io, args[1]);
    var output = try std.Io.Dir.cwd().openDir(init.io, args[1], .{});
    defer output.close(init.io);
    try generator.generate(init.arena.allocator(), init.io, @embedFile("plugin_transform/semantic.json"), output, .{
        .package = "custom",
        .prefix = "zg",
        .go_module = "example.com/custom",
        .backend = if (std.mem.eql(u8, args[2], "cgo")) .cgo else .purego,
        .include_dir = "${SRCDIR}/../..",
        .ldflags_override = "",
        .configurations = &.{.{ .name = "CONTRACT", .json = "{\"customize\":true}" }},
    });
    try output.writeFile(init.io, .{ .sub_path = "go.mod", .data = "module example.com/custom\n\ngo 1.24\n\nrequire github.com/ebitengine/purego v0.10.2\n" });
    try output.writeFile(init.io, .{ .sub_path = "custom/roundtrip_test.go", .data = @embedFile("plugin_transform/roundtrip_test.go") });
    try output.writeFile(init.io, .{ .sub_path = "custom/load_test.go", .data = if (std.mem.eql(u8, args[2], "cgo"))
        "package custom\nfunc loadTestLibrary(_ string) error { return nil }\n"
    else
        "package custom\nimport \"path/filepath\"\nfunc loadTestLibrary(path string) error { if !filepath.IsAbs(path) { path = filepath.Join(\"..\", path) }; return LoadLibrary(path) }\n" });
}
