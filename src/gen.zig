const std = @import("std");
const Registry = @import("registry.zig").Registry;
const Container = @import("container.zig").Container;
const Type = @import("type.zig").Type;
const common = @import("common.zig");
const sliceFromCString = common.sliceFromCString;

const stdout = std.io.getStdOut().writer();

const method_rename_map = std.ComptimeStringMap([]const u8, .{
    .{ "error", "_error" },
    .{ "type", "_type" },
    .{ "class", "_class" },
    .{ "self", "_self" },
    .{ "resume", "_resume" },
    .{ "test", "_test" },
    .{ "suspend", "_suspend" },
    .{ "opaque", "_opaque" },
    .{ "null", "_null" },
    .{ "setBufferOffset:atIndex:", "setOffsetOfBuffer:atIndex:" },
    .{ "setVertexBufferOffset:atIndex:", "setOffsetOfVertexBuffer:atIndex:" },
    .{ "setFragmentBufferOffset:atIndex:", "setOffsetOfFragmentBuffer:atIndex:" },
    .{ "setMeshBufferOffset:atIndex:", "setOffsetOfMeshBuffer:atIndex:" },
    .{ "setTileBufferOffset:atIndex:", "setOffsetOfTileBuffer:atIndex:" },
    .{ "setObjectBufferOffset:atIndex:", "setOffsetOfObjectBuffer:atIndex:" },
    .{ "setBufferOffset:attributeStride:atIndex:", "setOffsetOfBuffer:attributeStride:atIndex:" },
    .{ "setVertexBufferOffset:attributeStride:atIndex:", "setOffsetOfVertexBuffer:attributeStride:atIndex:" },
});

const param_rename_map = std.ComptimeStringMap([]const u8, .{
    .{ "error", "an_error" },
    .{ "type", "a_type" },
    .{ "class", "a_class" },
    .{ "self", "the_self" },
    .{ "resume", "_resume" },
    .{ "test", "_test" },
    .{ "suspend", "_suspend" },
    .{ "opaque", "_opaque" },
    .{ "attachments", "_attachments" },
    .{ "null", "_null" },
});

const records_force_opaque = std.ComptimeStringMap(void, .{
    .{"__CFRunLoop"},
    .{"__IOSurface"},
    .{"_xpc_type_s"},
    .{"_NSZone"},
    .{"_MTLPackedFloat3"},
    .{"OpaqueAEDataStorageType"},
    .{"__NSAppleEventManagerSuspension"},
    .{"NSPortMessage"},
});

const blacklisted_interfaces = std.ComptimeStringMap(void, .{
    .{"NSProcessInfoThermalState"},
});

const blacklisted_functions = std.ComptimeStringMap(void, .{
    .{"MTLClearColorMake"},
});

const record_field_rename_map = std.ComptimeStringMap([]const u8, .{
    .{ "align", "alignment" },
});

const enums_to_be_replaced_with_integer_types = std.ComptimeStringMap(void, .{
    .{"MTLTextureUsage"},
});

const mixin_only_containers = std.ComptimeStringMap(void, .{.{"NSObject"}});

pub const Generator = struct {
    r: *Registry,

    const Self = @This();

    pub fn init(self: *Self, registry: *Registry) void {
        self.r = registry;
    }

    pub fn writeSelVarName(m: Container.Method, w: anytype) !void {
        try w.writeAll("sel_");
        for (sliceFromCString(m.name)) |ch| {
            if (ch == ':') {
                try w.writeByte('_');
            } else {
                try w.writeByte(ch);
            }
        }
    }

    pub fn writeSelVarDecl(m: Container.Method, w: anytype) !void {
        try w.writeAll("var ");
        try writeSelVarName(m, w);
        try w.print(" = CachedSelector.init(\"{s}\");\n", .{m.name});
    }

    pub fn writeMethodZigFunctionName(m: Container.Method, w: anytype) !void {
        var name: []const u8 = if (method_rename_map.get(sliceFromCString(m.name))) |str| str else sliceFromCString(m.name);

        var nextIsUpperCase = false;
        for (name) |ch| {
            if (ch != ':') {
                if (nextIsUpperCase) {
                    nextIsUpperCase = false;
                    try w.writeByte(std.ascii.toUpper(ch));
                } else {
                    try w.writeByte(ch);
                }
            } else {
                nextIsUpperCase = true;
            }
        }
    }

    pub fn writeConst(t: *Type, w: anytype) !void {
        switch (t.*) {
            .primitive => |primitive| {
                if (primitive.is_const) {
                    try w.writeAll(" const ");
                }
            },
            else => {},
        }
    }

    pub fn writeZigType(t: *Type, w: anytype) !void {
        switch (t.*) {
            .primitive => |primitive| {
                var name: []const u8 = switch (primitive.kind) {
                    .Void => "void",
                    .Bool => "bool",
                    .UChar => "u8",
                    .UShort => "c_ushort",
                    .UInt => "c_uint",
                    .ULong => "c_ulong",
                    .ULongLong => "c_ulonglong",
                    .UInt128 => "u128",
                    .SChar => "u8",
                    .WChar => "u16",
                    .Short => "c_short",
                    .Int => "c_int",
                    .Long => "c_long",
                    .LongLong => "c_longlong",
                    .Int128 => "i128",
                    .Float => "f32",
                    .Double => "f64",
                    .LongDouble => "c_longdouble",
                    .NullPtr => "?*u8",
                    .Half => "c_half",
                };
                try w.writeAll(name);
            },
            .instancetype => {
                try w.writeAll("*Self");
            },
            .array => |array| {
                if (array.incomplete) {
                    try w.writeAll("[*c]");
                    try writeZigType(array.element_type, w);
                    //try w.writeAll("INCOMPLETE");
                } else {
                    try w.print("[{}]", .{array.size});
                    try writeZigType(array.element_type, w);
                }
            },
            .pointer => |pointer| {
                // if (pointer.is_const) {
                // try w.writeAll("[*c]");
                // } else {
                //try w.writeAll("[*c] ");
                // }

                switch (pointer.pointee.*) {
                    .id, .sel, .class, .instancetype, .interface => {
                        if (pointer.nullability == Type.Pointer.Nullability.nullable) {
                            try w.writeAll(" ?* ");
                        } else {
                            try w.writeAll(" * ");
                        }
                    },
                    .primitive => |primitive| {
                        switch (primitive.kind) {
                            .Void => {
                                if (pointer.nullability == Type.Pointer.Nullability.nullable) {
                                    try w.writeAll(" ?");
                                }
                                if (primitive.is_const) {
                                    try w.writeAll("* const anyopaque ");
                                } else {
                                    try w.writeAll("* anyopaque ");
                                }
                                return;
                            },
                            else => {
                                try w.writeAll(" [*c] ");
                            },
                        }
                    },
                    else => {
                        try w.writeAll(" [*c] ");
                    },
                }

                try writeConst(pointer.pointee, w);
                try writeZigType(pointer.pointee, w);
            },
            .class => |name| {
                _ = name;
                try w.writeAll("Class");
            },
            .sel => {
                try w.writeAll("SEL");
            },
            .id => |maybe_name| {
                if (maybe_name) |name| {
                    try w.print("{s}", .{name});
                } else {
                    try w.writeAll("id");
                }
            },
            .type_param => {
                std.debug.panic("INVALID", .{});
            },
            .enumeration => |name| {
                //var name_slice = sliceFromCString(name);
                //if (enums_to_be_replaced_with_integer_types.has(name_slice[5..])) {
                //    if (self.r.enums.get(name_slice)) |e| {
                //        try self.writeZigType(e.type, w);
                //    } else {
                //        std.debug.panic("Enum not found: {s}", .{name_slice});
                //    }
                //} else {
                try w.print("{s}", .{sliceFromCString(name)[5..]});
                //}
            },
            .block_pointer => |_| {
                try w.writeAll("?*u8");
            },
            .function_proto => |_| {
                try w.writeAll("?*u8");
            },
            .interface => |name| {
                try w.print("{s}", .{name});
            },
            .record => |name| {
                try w.print("{s}", .{name});
            },
            else => {
                try w.writeAll("!void");
            },
        }
    }

    const ContainerKind = enum {
        protocol,
        interface,

        fn mixinName(self: ContainerKind) []const u8 {
            return switch (self) {
                .protocol => "ProtocolMixin",
                .interface => "InterfaceMixin",
            };
        }
    };

    fn paramName(original: [*:0]const u8) []const u8 {
        var str = sliceFromCString(original);
        if (param_rename_map.has(str)) {
            return param_rename_map.get(str).?;
        } else {
            return str;
        }
    }

    fn writeContainer(container: *Container, w: anytype, kind: ContainerKind) !void {
        try w.print("pub fn {s}{s}(comptime Self: type, comptime class_name: [*:0]const u8) type {{\n", .{ container.name, kind.mixinName() });

        if (container.needsToDiscardSelf()) {
            try w.writeAll("_ = Self;\n");
        }

        try w.print("  return struct {{\n", .{});
        try w.print("      var class = CachedClass.init(class_name);\n", .{});

        for (container.methods.items) |method| {
            try writeSelVarDecl(method, w);
            try w.print("      pub fn ", .{});
            try writeMethodZigFunctionName(method, w);
            try w.writeByte('(');

            if (method.is_instance) {
                try w.writeAll("self: *Self, ");
            }

            for (method.params.items) |param| {
                try w.print("__{s}: ", .{paramName(param.name)});
                try writeZigType(param.type, w);
                try w.writeAll(", ");
            }

            try w.writeAll(") ");

            try writeZigType(method.return_type, w);
            try w.writeAll(" {{\n");

            var idtag: []const u8 = if (method.is_instance) "*Self" else "Class";

            // try w.print("           return @as(*const fn({s}, SEL, ) , @ptrCast())();", .{idtag});
            try w.print("           return @as(*const fn({s}, SEL, ", .{idtag});
            for (method.params.items) |param| {
                try writeZigType(param.type, w);
                try w.writeAll(", ");
            }
            try w.print(") callconv(.C) ", .{}); //, @ptrCast(&objc_msgSend)(", .{});
            try writeZigType(method.return_type, w);
            try w.print(", @ptrCast(&objc_msgSend))(", .{});

            if (method.is_instance) {
                try w.writeAll("@ptrCast(self), ");
            } else {
                try w.writeAll("class.get(), ");
            }

            try writeSelVarName(method, w);
            try w.writeAll(".get(), ");
            // try w.writeAll("")

            for (method.params.items) |param| {
                try w.print("__{s}, ", .{paramName(param.name)});
            }

            try w.print(");\n", .{});
            try w.writeAll(" }}\n");
        }

        try w.print("  }};\n", .{});
        try w.print("}}\n\n", .{});

        if (!mixin_only_containers.has(sliceFromCString(container.name))) {
            try w.print("pub const {s} = opaque {{\n", .{container.name});
            try w.print("  const Self = @This();\n", .{});
            try w.print("  pub usingnamespace {s}{s}(Self, \"{s}\");\n", .{ container.name, kind.mixinName(), container.name });

            for (0..container.num_protocols) |i| {
                try w.print("  pub usingnamespace {s}ProtocolMixin(Self, \"{s}\");\n", .{ container.protocols[i], container.name });
            }

            try w.print("  pub usingnamespace NSObjectProtocolMixin(Self, \"{s}\");\n", .{container.name});

            if (container.super_class) |super_class_name| {
                try w.print("  pub usingnamespace {s}InterfaceMixin(Self, \"{s}\");\n", .{ super_class_name, container.name });
            }

            try w.print("}};\n\n", .{});
        }
    }

    pub fn recordFieldName(original: [*:0]const u8) []const u8 {
        var slice = sliceFromCString(original);

        if (record_field_rename_map.get(slice)) |name| {
            return name;
        } else {
            return slice;
        }
    }

    pub fn generate(self: *Self, allocator: std.mem.Allocator) !void {
        var ib = try allocator.alloc(u8, 2 * 1024 * 1024);
        var pb = try allocator.alloc(u8, 2 * 1024 * 1024);
        var eb = try allocator.alloc(u8, 2 * 1024 * 1024);
        var rb = try allocator.alloc(u8, 2 * 1024 * 1024);
        var fb = try allocator.alloc(u8, 1024 * 1024);

        var is = std.io.fixedBufferStream(ib[0..]);
        var ps = std.io.fixedBufferStream(pb[0..]);
        var es = std.io.fixedBufferStream(eb[0..]);
        var rs = std.io.fixedBufferStream(rb[0..]);
        var fs = std.io.fixedBufferStream(fb[0..]);

        var iw = is.writer();
        var pw = ps.writer();
        var ew = es.writer();
        var rw = rs.writer();
        var fw = fs.writer();

        {
            var protocol_it = self.r.protocols.iterator();
            while (protocol_it.next()) |entry| {
                try writeContainer(entry.value_ptr, pw, .protocol);
            }
        }
        {
            var interface_it = self.r.interfaces.iterator();

            while (interface_it.next()) |entry| {
                if (blacklisted_interfaces.has(sliceFromCString(entry.value_ptr.name))) {
                    continue;
                }

                try writeContainer(entry.value_ptr, iw, .interface);
            }
        }
        {
            var enum_it = self.r.enums.iterator();
            while (enum_it.next()) |entry| {
                var e = entry.value_ptr;

                var name_slice = sliceFromCString(e.name)[5..];
                if (enums_to_be_replaced_with_integer_types.has(name_slice)) {
                    try ew.print("pub const {s} = ", .{name_slice});
                    try writeZigType(e.type, ew);
                    try ew.writeAll(";\n\n");

                    for (e.values.items) |value| {
                        try ew.print("pub const {s}: ", .{value.name});

                        try writeZigType(e.type, ew);

                        try ew.writeAll(" = ");

                        if (e.type.isUnsigned()) {
                            try ew.print(" {} ;\n", .{value.value});
                        } else {
                            try ew.print(" {} ;\n", .{value.ivalue});
                        }
                    }
                    continue;
                }

                try ew.print("pub const {s} = enum(", .{sliceFromCString(e.name)[5..]});
                try writeZigType(e.type, ew);
                try ew.writeAll(") {\n");

                for (e.values.items) |value| {
                    if (e.type.isUnsigned()) {
                        try ew.print("  {s} = {},\n", .{ value.name, value.value });
                    } else {
                        try ew.print("  {s} = {},\n", .{ value.name, value.ivalue });
                    }
                }

                try ew.writeAll("};\n\n");
            }
        }
        {
            var it = self.r.records.iterator();

            while (it.next()) |entry| {
                var rec = entry.value_ptr;

                if (records_force_opaque.has(sliceFromCString(rec.name))) {
                    try rw.print("pub const {s} = opaque {{}};\n\n", .{rec.name});
                    continue;
                }

                try rw.print("pub const {s} = extern struct {{\n", .{rec.name});

                for (rec.fields.items) |field| {
                    try rw.print("      {s}: ", .{recordFieldName(field.name)});
                    try writeZigType(field.type, rw);
                    try rw.writeAll(",\n");
                }

                try rw.writeAll("};\n\n");
            }
        }
        {
            var it = self.r.functions.iterator();

            while (it.next()) |entry| {
                var func = entry.value_ptr;

                if (blacklisted_functions.has(funcName(sliceFromCString(func.name)))) {
                    continue;
                }

                try fw.writeAll("pub extern fn ");
                try writeFuncName(sliceFromCString(func.name), fw);
                try fw.writeAll("( ");

                for (func.params.items) |param| {
                    var name = paramName(param.name);
                    try fw.print("{s}: ", .{name});
                    try writeZigType(param.type, fw);
                    try fw.writeAll(", ");
                }
                try fw.writeAll(") ");
                try writeZigType(func.return_type, fw);

                try fw.writeAll(";");
                try fw.writeAll("\n\n");
                // try fw.writeAll("() {} \n\n");
            }
        }

        try stdout.print("{s}", .{preamble});
        try stdout.print("{s}", .{ps.buffer[0..ps.pos]});
        try stdout.print("{s}", .{is.buffer[0..is.pos]});
        try stdout.print("{s}", .{es.buffer[0..es.pos]});
        try stdout.print("{s}", .{rs.buffer[0..rs.pos]});
        try stdout.print("{s}", .{fs.buffer[0..fs.pos]});
    }

    fn funcName(name: []const u8) []const u8 {
        var c: usize = 0;
        for (name) |ch| {
            if (ch == '(') {
                break;
            }
            c += 1;
        }

        return name[0..c];
    }

    fn writeFuncName(name: []const u8, w: anytype) !void {
        for (name) |ch| {
            if (ch == '(') {
                break;
            }

            try w.writeByte(ch);
        }
    }
};

const preamble =
    \\pub const std = @import("std");
    \\pub const id = *opaque {};
    \\pub const SEL = *opaque {};
    \\pub const Class = *opaque {};
    \\pub const Protocol = opaque {};
    \\pub const IMP = *opaque {};
    \\pub const NSZone = opaque {};
    \\pub extern fn objc_msgSend() void;
    \\pub extern fn objc_lookUpClass(name: [*:0]const u8) Class;
    \\pub extern fn objc_getClass(name: [*:0]const u8) id;
    \\pub extern fn sel_registerName(str: [*:0]const u8) SEL;
    \\pub extern fn objc_allocateClassPair(superclass: Class, name: [*:0]const u8, extra_bytes: usize) Class;
    \\pub extern fn class_addMethod(class: Class, sel: SEL, imp: IMP, types: [*:0]const u8) bool;
    \\
    \\pub const NSImage = opaque{};
    \\
    \\pub const CachedClass = struct {
    \\    name: [*:0]const u8,
    \\    class: ?Class = null,
    \\
    \\    pub fn init(name: [*:0]const u8) CachedClass {
    \\        return .{ .name = name };
    \\    }
    \\
    \\    pub fn get(self: *CachedClass) Class {
    \\        if (self.class == null) {
    \\            self.class = objc_lookUpClass(self.name);
    \\        }
    \\
    \\        return self.class.?;
    \\    }
    \\};
    \\
    \\pub const CachedSelector = struct {
    \\    name: [*:0]const u8,
    \\    sel: ?SEL = null,
    \\
    \\    pub fn init(name: [*:0]const u8) CachedSelector {
    \\        return .{ .name = name };
    \\    }
    \\
    \\    pub fn get(self: *CachedSelector) SEL {
    \\        if (self.sel == null) {
    \\            self.sel = sel_registerName(self.name);
    \\        }
    \\
    \\        return self.sel.?;
    \\    }
    \\};
    \\
    \\ pub fn MTLClearColorMake(r: f64, g: f64, b: f64, a: f64) MTLClearColor {return .{.red = r, .green = g, .blue = b, .alpha = a };}
    \\
    \\ pub const NSObject = opaque { 
    \\      const Self = @This(); 
    \\      pub usingnamespace NSObjectProtocolMixin(Self, "NSObject");  
    \\      pub usingnamespace NSObjectInterfaceMixin(Self, "NSObject");  
    \\ };
    \\ //pub const NSPortMessage = opaque{};
    \\
;
