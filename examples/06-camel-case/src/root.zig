pub fn statusCode(retry_count: u32) u32 {
    return 200 + retry_count;
}

test "CamelCase package example" {
    const std = @import("std");
    try std.testing.expectEqual(@as(u32, 203), statusCode(3));
}
