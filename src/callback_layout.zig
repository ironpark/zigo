const std = @import("std");

/// What each native parameter of a callback signature is, and where it lands
/// in the Go-order `params`. A `[*]const u8` immediately followed by a `usize`
/// (that is not the userdata slot) is one byte payload: the pointer carries
/// the `params` entry and the length is folded into it.
pub fn Layout(comptime count: usize) type {
    return struct {
        kinds: [count]enum { value, pair_pointer, pair_length, userdata },
        go_index: [count]usize,
        go_count: usize,
    };
}

pub fn describe(comptime function_info: std.builtin.Type.Fn, comptime userdata_native: ?usize) Layout(function_info.params.len) {
    comptime {
        const count = function_info.params.len;
        var layout: Layout(count) = undefined;
        var go_count: usize = 0;
        var native: usize = 0;
        while (native < count) : (native += 1) {
            if (userdata_native != null and native == userdata_native.?) {
                layout.kinds[native] = .userdata;
                layout.go_index[native] = 0;
                continue;
            }
            const T = function_info.params[native].type orelse {
                layout.kinds[native] = .value;
                layout.go_index[native] = go_count;
                go_count += 1;
                continue;
            };
            const paired = isBytePairPointer(T) and native + 1 < count and
                function_info.params[native + 1].type == usize and
                (userdata_native == null or native + 1 != userdata_native.?);
            if (paired) {
                layout.kinds[native] = .pair_pointer;
                layout.go_index[native] = go_count;
                layout.kinds[native + 1] = .pair_length;
                layout.go_index[native + 1] = go_count;
                go_count += 1;
                native += 1;
                continue;
            }
            layout.kinds[native] = .value;
            layout.go_index[native] = go_count;
            go_count += 1;
        }
        if (userdata_native) |at| layout.go_index[at] = go_count;
        layout.go_count = go_count + @intFromBool(userdata_native != null);
        return layout;
    }
}

/// `[*]const u8` without a sentinel: the pointer half of a byte pair.
fn isBytePairPointer(comptime T: type) bool {
    const info = switch (@typeInfo(T)) {
        .pointer => |value| value,
        else => return false,
    };
    return info.size == .many and info.child == u8 and info.is_const and info.sentinel() == null;
}
