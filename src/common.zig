const std = @import("std");

pub const c_string = [*:0]const u8;

pub inline fn println(comptime fmt: []const u8, args: anytype) void {
    std.io.getStdOut().writer().print(fmt ++ "\n", args) catch {
        std.debug.panic("Failed to write to stdout!", .{});
    };
}

pub inline fn print(comptime fmt: []const u8, args: anytype) void {
    std.io.getStdOut().writer().print(fmt, args) catch {
        std.debug.panic("Failed to write to stdout!", .{});
    };
}

pub fn write_spaces(n: usize, w: anytype) !void {
    for (0..n) |_| {
        try w.writeByte(' ');
    }
}

pub inline fn sliceFromCString(str: c_string) []const u8 {
    return std.mem.sliceTo(str, 0);
}
