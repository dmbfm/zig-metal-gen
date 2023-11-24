const std = @import("std");
const common = @import("common.zig");
const sliceFromCString = common.sliceFromCString;
const c_string = common.c_string;
const Type = @import("type.zig").Type;

pub const Container = struct {
    name: c_string,
    methods: std.ArrayList(Method),
    super_class: ?c_string = null,
    protocols: [max_protocols]c_string = undefined,
    num_protocols: usize = 0,

    pub const max_protocols = 16;

    pub const Method = struct {
        name: c_string,
        is_instance: bool,
        return_type: *Type,
        params: std.ArrayList(Param),
        pub const Param = struct {
            name: c_string,
            type: *Type,
        };

        pub fn init(allocator: std.mem.Allocator, name: c_string, is_instance: bool, return_type: *Type) Method {
            return .{
                .name = name,
                .is_instance = is_instance,
                .return_type = return_type,
                .params = std.ArrayList(Param).init(allocator),
            };
        }

        pub fn addParam(self: *Method, param: Param) void {
            return self.params.append(param) catch {
                std.debug.panic("Failed to add parameter to method!", .{});
            };
        }

        pub fn write(self: Method, writer: anytype) !void {
            const s = if (self.is_instance) "-" else "+";
            try writer.print("{s} {s}", .{ s, self.name });
            try self.return_type.print(writer);
        }
    };

    pub fn init(allocator: std.mem.Allocator, name: c_string) Container {
        return .{
            .name = name,
            .methods = std.ArrayList(Method).init(allocator),
        };
    }

    pub fn addMethod(self: *Container, method: Method) void {
        for (self.methods.items) |m| {
            if (std.mem.eql(u8, sliceFromCString(m.name), sliceFromCString(method.name))) {
                return;
            }
        }

        self.methods.append(method) catch {
            std.debug.panic("Faile to add method to container!", .{});
        };
    }

    pub fn addConformingProtocol(self: *Container, protocol_name: c_string) void {
        for (0..self.num_protocols) |i| {
            if (std.mem.eql(u8, sliceFromCString(self.protocols[i]), sliceFromCString(protocol_name))) {
                return;
            }
        }

        if (self.num_protocols >= max_protocols) {
            std.debug.panic("Max protocols reached!", .{});
        }

        self.protocols[self.num_protocols] = protocol_name;
        self.num_protocols += 1;
    }

    pub fn setSuperClass(self: *Container, super_class_name: c_string) void {
        if (self.super_class != null) {
            std.debug.panic("Superclass was already set!", .{});
        }

        self.super_class = super_class_name;
    }

    pub fn instanceMethodCound(self: *Container) usize {
        var c: usize = 0;
        for (self.methods.items) |m| {
            if (m.is_instance) {
                c += 1;
            }
        }
        return c;
    }

    pub fn needsToDiscardSelf(self: *Container) bool {
        var usesSelf = false;
        for (self.methods.items) |m| {
            switch (m.return_type.*) {
                .instancetype => {
                    usesSelf = true;
                    break;
                },
                else => {},
            }

            for (m.params.items) |param| {
                switch (param.type.*) {
                    .instancetype => {
                        usesSelf = true;
                        break;
                    },
                    else => {},
                }
            }
        }

        return !usesSelf and (self.instanceMethodCound() == 0);
    }

    pub fn print(self: *Container, level: usize, writer: anytype) !void {
        var w = writer;

        // var s: []const u8 = if (self.is_instance) "-" else "+";
        try w.writeByte('\n');
        try common.write_spaces(level, w);
        try w.print("Container: {s}\n", .{self.name});
        for (self.methods.items) |m| {
            try m.print(level + 1, w);
        }
    }
};

test {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const c = Container.init(arena.allocator(), "MyProtocol");
    _ = c;
}
