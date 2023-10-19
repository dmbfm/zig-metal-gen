const std = @import("std");
const common = @import("common.zig");
const c_string = common.c_string;
const Type = @import("type.zig").Type;

pub const Enum = struct {
    name: c_string,
    type: *Type,
    values: std.ArrayList(Value),

    pub const Value = struct {
        name: c_string,
        value: u64,
        ivalue: i64,
    };

    pub fn init(allocator: std.mem.Allocator, name: c_string, enum_type: *Type) Enum {
        return .{
            .name = name,
            .type = enum_type,
            .values = std.ArrayList(Value).init(allocator),
        };
    }

    pub fn addValue(self: *Enum, val: Value) void {
        self.values.append(val) catch {
            std.debug.panic("Failed to add enum value!", .{});
        };
    }

    pub fn print(self: *Enum, level: usize, writer: anytype) !void {
        var w = writer;
        try w.writeByte('\n');
        try common.write_spaces(level, w);
        try w.print("\n{s} Enum: {s}\n", .{self.name});
        for (self.values.items) |val| {
            try w.print("{s} \t {s} = {} ({})\n", .{ level + 1, val.name, val.value, val.ivalue });
        }
    }
};

test {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var e = Enum.init(arena.allocator(), "SomeEnum", Type.createPrimitive(arena.allocator(), Type.Primitive.LongLong));
    e.addValue(.{
        .name = "SomeEnumValue",
        .value = 1,
        .ivalue = 1,
    });
}
