pub const dependency = @import("dependency");

pub fn answer() u32 {
    return if (dependency.dependency_marker) 42 else 0;
}
