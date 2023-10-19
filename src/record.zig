const std = @import("std");
const common = @import("common.zig");
const c_string = common.c_string;
const Type = @import("type.zig").Type;

pub const Record = struct {
    name: c_string,
    fields: std.ArrayList(Field),

    pub const Field = struct {
        name: c_string,
        type: *Type,
    };

    pub fn init(allocator: std.mem.Allocator, name: c_string) Record {
        return .{
            .name = name,
            .fields = std.ArrayList(Field).init(allocator),
        };
    }

    pub fn addField(self: *Record, field: Field) void {
        self.fields.append(field) catch {
            std.debug.panic("Failed to add field to recotd!", .{});
        };
    }
};
