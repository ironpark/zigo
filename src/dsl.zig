//! The DSL and literal schema share one authoring model.
pub const scope = @import("author.zig").scope;
pub const package = @import("author.zig").package;
pub const interface = @import("author.zig").interface;
pub const session = @import("author.zig").session;
pub const Selector = @import("author.zig").Selector;
pub const features = @import("features.zig");

pub const param = @import("param.zig");
pub const result = @import("result.zig");
