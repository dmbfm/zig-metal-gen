const std = @import("std");
const registry = @import("registry.zig");
const Registry = registry.Registry;
const common = @import("common.zig");
const c_string = common.c_string;
const Generator = @import("gen.zig").Generator;

pub fn functionFilterFn(name: []const u8) bool {
    return std.mem.startsWith(u8, name, "MTL");
}

pub fn protocolFilterFn(name: []const u8) bool {
    return std.mem.startsWith(u8, name, "MTL") or std.mem.startsWith(u8, name, "NS");
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var r: Registry = undefined;

    r.init(arena.allocator(), .{
        .function_filter_fn = &functionFilterFn,
        .protocol_filter_fn = &protocolFilterFn,
        .interface_filter_fn = &protocolFilterFn,
    });

    r.build("entry.m");
    // r.print();

    var gen: Generator = undefined;
    gen.init(&r);
    try gen.generate(arena.allocator());
}

test {
    _ = @import("type.zig");
    _ = @import("enum.zig");
    _ = @import("container.zig");
}
