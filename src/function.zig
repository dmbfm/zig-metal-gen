const std = @import("std");
const common = @import("common.zig");
const c_string = common.c_string;
const Type = @import("type.zig").Type;

pub const Function = struct {
    name: c_string,
    return_type: *Type,
    params: std.ArrayList(Param),

    pub const Param = struct {
        name: c_string,
        type: *Type,
    };

    pub fn init(
        allocator: std.mem.Allocator,
        name: c_string,
        return_type: *Type,
    ) Function {
        return .{
            .name = name,
            .return_type = return_type,
            .params = std.ArrayList(Param).init(allocator),
        };
    }

    pub fn addParam(self: *Function, param: Param) void {
        self.params.append(param) catch {
            std.debug.panic("[Function.addParam]: Failed to add parameter!", .{});
        };
    }
};
