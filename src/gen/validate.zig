const semantic = @import("semantic");

pub fn semanticDocument(document: semantic.Semantic) !void {
    if (document.ir_version != 1) return error.UnsupportedIrVersion;
    if (document.package.len == 0 or document.prefix.len == 0) return error.InvalidName;
    for (document.functions) |function| {
        if (function.name.len == 0) return error.InvalidName;
        for (function.params) |parameter| try scalar(parameter.type);
        try scalar(function.@"return");
    }
}

fn scalar(node: semantic.TypeNode) !void {
    switch (node) {
        .void, .bool => {},
        .int => |value| if (value.bits == 0 or value.bits > 64) return error.UnsupportedIntegerWidth,
        .float => |value| if (value.bits != 32 and value.bits != 64) return error.UnsupportedFloatWidth,
        else => return error.UnsupportedType,
    }
}
