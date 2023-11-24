const std = @import("std");
const common = @import("common.zig");
const c_string = common.c_string;
const Allocator = std.mem.Allocator;

// Represents the type of an entity. This does not store
// actual information about complex types, such as Protocols,
// interfaces, enumerations, structs, etc. It only stores their
// names. Actual declaration data will be stored in the Registry.
//
// This does not implement any type of RAII/de-allocations. Ideally
// should be used with an arena that the caller de-initializes.
pub const Type = union(enum) {
    primitive: Primitive,
    array: Array,
    pointer: Pointer,
    class: c_string,
    sel: void,
    id: ?c_string,
    type_param: c_string,
    enumeration: c_string,
    block_pointer: FunctionProto,
    function_proto: FunctionProto,
    interface: c_string,
    record: c_string,
    instancetype: void,
    unimplemented: void,

    pub var _instancetype: Type = .instancetype;

    pub var _void: Type = .{ .primitive = .{ .kind = .Void } };
    pub var _ulonglong: Type = .{ .primitive = .{ .kind = .ULongLong } };
    pub var _longlong: Type = .{ .primitive = .{ .kind = .LongLong } };
    pub var _bool: Type = .{ .primitive = .{ .kind = .Bool } };
    pub var _int: Type = .{ .primitive = .{ .kind = .Int } };
    pub var _uchar: Type = .{ .primitive = .{ .kind = .UChar } };
    pub var _ushort: Type = .{ .primitive = .{ .kind = .UShort } };
    pub var _uint: Type = .{ .primitive = .{ .kind = .UInt } };
    pub var _ulong: Type = .{ .primitive = .{ .kind = .ULong } };
    pub var _uint128: Type = .{ .primitive = .{ .kind = .UInt128 } };
    pub var _schar: Type = .{ .primitive = .{ .kind = .SChar } };
    pub var _wchar: Type = .{ .primitive = .{ .kind = .WChar } };
    pub var _short: Type = .{ .primitive = .{ .kind = .Short } };
    pub var _long: Type = .{ .primitive = .{ .kind = .Long } };
    pub var _int128: Type = .{ .primitive = .{ .kind = .Int128 } };
    pub var _float: Type = .{ .primitive = .{ .kind = .Float } };
    pub var _double: Type = .{ .primitive = .{ .kind = .Double } };
    pub var _longdouble: Type = .{ .primitive = .{ .kind = .LongDouble } };
    pub var _null_ptr: Type = .{ .primitive = .{ .kind = .NullPtr } };
    pub var _half: Type = .{ .primitive = .{ .kind = .Half } };
    pub var _unimplemented: Type = .unimplemented;

    pub var _const_void: Type = .{ .primitive = .{ .kind = .Void, .is_const = true } };
    pub var _const_ulonglong: Type = .{ .primitive = .{ .kind = .ULongLong, .is_const = true } };
    pub var _const_longlong: Type = .{ .primitive = .{ .kind = .LongLong, .is_const = true } };
    pub var _const_bool: Type = .{ .primitive = .{ .kind = .Bool, .is_const = true } };
    pub var _const_int: Type = .{ .primitive = .{ .kind = .Int, .is_const = true } };
    pub var _const_uchar: Type = .{ .primitive = .{ .kind = .UChar, .is_const = true } };
    pub var _const_ushort: Type = .{ .primitive = .{ .kind = .UShort, .is_const = true } };
    pub var _const_uint: Type = .{ .primitive = .{ .kind = .UInt, .is_const = true } };
    pub var _const_ulong: Type = .{ .primitive = .{ .kind = .ULong, .is_const = true } };
    pub var _const_uint128: Type = .{ .primitive = .{ .kind = .UInt128, .is_const = true } };
    pub var _const_schar: Type = .{ .primitive = .{ .kind = .SChar, .is_const = true } };
    pub var _const_wchar: Type = .{ .primitive = .{ .kind = .WChar, .is_const = true } };
    pub var _const_short: Type = .{ .primitive = .{ .kind = .Short, .is_const = true } };
    pub var _const_long: Type = .{ .primitive = .{ .kind = .Long, .is_const = true } };
    pub var _const_int128: Type = .{ .primitive = .{ .kind = .Int128, .is_const = true } };
    pub var _const_float: Type = .{ .primitive = .{ .kind = .Float, .is_const = true } };
    pub var _const_double: Type = .{ .primitive = .{ .kind = .Double, .is_const = true } };
    pub var _const_longdouble: Type = .{ .primitive = .{ .kind = .LongDouble, .is_const = true } };
    pub var _const_null_ptr: Type = .{ .primitive = .{ .kind = .NullPtr, .is_const = true } };
    pub var _const_half: Type = .{ .primitive = .{ .kind = .Half, .is_const = true } };
    pub var _const_unimplemented: Type = .unimplemented;

    pub const PrimitiveKind = enum {
        Void,
        Bool,
        UChar,
        UShort,
        UInt,
        ULong,
        ULongLong,
        UInt128,
        SChar,
        WChar,
        Short,
        Int,
        Long,
        LongLong,
        Int128,
        Float,
        Double,
        LongDouble,
        NullPtr,
        Half,
    };

    pub const Primitive = struct {
        kind: PrimitiveKind,
        is_const: bool = false,
    };

    pub const max_func_params = 12;
    pub const max_type_params = 4;

    pub const FunctionProto = struct {
        return_type: *Type,
        parameters: [max_func_params]*Type,
        num_parameters: usize,
    };

    pub const Array = struct {
        element_type: *Type,
        incomplete: bool,
        size: usize,
        is_const: bool = false,
    };

    pub const Pointer = struct {
        pointee: *Type,
        nullability: Nullability = .none,
        is_const: bool = false,

        pub const Nullability = enum {
            nullable,
            nonnull,
            none,
        };
    };

    pub fn isUnsigned(self: *Type) bool {
        return switch (self.*) {
            .primitive => |prim| switch (prim.kind) {
                .UInt, .UChar, .UShort, .ULong, .ULongLong, .UInt128 => true,
                else => false,
            },
            else => false,
        };
    }
    fn allocFailType(allocator: Allocator) *Type {
        return allocator.create(Type) catch {
            std.debug.panic("Failed to allocate Type!", .{});
        };
    }

    pub fn createPrimitive(allocator: Allocator, kind: PrimitiveKind, is_const: bool) *Type {
        const t = allocFailType(allocator);
        t.* = .{ .primitive = .{ .kind = kind, .is_const = is_const } };
        return t;
    }

    pub fn createArray(allocator: Allocator, element_type: *Type, incomplete: bool, size: usize) *Type {
        const t = allocFailType(allocator);
        t.* = .{ .array = Array{
            .element_type = element_type,
            .incomplete = incomplete,
            .size = size,
        } };
        return t;
    }

    pub fn createPointer(allocator: Allocator, pointee: *Type, nullability: Pointer.Nullability) *Type {
        const t = allocFailType(allocator);
        t.* = .{ .pointer = Pointer{ .pointee = pointee, .nullability = nullability } };
        return t;
    }

    pub fn createInterface(allocator: Allocator, name: c_string) *Type {
        const t = allocFailType(allocator);
        t.* = .{ .interface = name };
        return t;
    }

    pub fn createClass(allocator: Allocator, name: c_string) *Type {
        const t = allocFailType(allocator);
        t.* = .{ .class = name };
        return t;
    }

    pub fn createSel(allocator: Allocator) *Type {
        const t = allocFailType(allocator);
        t.* = .sel;
        return t;
    }

    pub fn createId(allocator: Allocator) *Type {
        const t = allocFailType(allocator);
        t.* = .{ .id = null };
        return t;
    }

    pub fn createIdProtocol(allocator: Allocator, protocol_name: c_string) *Type {
        const t = allocFailType(allocator);
        t.* = .{ .id = protocol_name };
        return t;
    }

    pub fn createTypeParam(allocator: Allocator, name: c_string) *Type {
        const t = allocFailType(allocator);
        t.* = .{ .type_param = name };
        return t;
    }

    pub fn createEnumeration(allocator: Allocator, name: c_string) *Type {
        const t = allocFailType(allocator);
        t.* = .{ .enumeration = name };
        return t;
    }

    pub fn createRecord(allocator: Allocator, name: c_string) *Type {
        const t = allocFailType(allocator);
        t.* = .{ .record = name };
        return t;
    }

    pub fn createInstancetype(allocator: Allocator) *Type {
        const t = allocFailType(allocator);
        t.* = .instancetype;
        return t;
    }

    pub fn createBlockPointer(allocator: Allocator, function_proto: FunctionProto) *Type {
        const t = allocFailType(allocator);
        t.* = .{ .block_pointer = function_proto };
        return t;
    }

    pub fn createFunctionProto(allocator: Allocator, return_type: *Type, params: []const *Type) *Type {
        if (params.len > max_func_params) {
            std.debug.panic("[createBlockPointer]: Max params exceeded!", .{});
        }

        var t = allocFailType(allocator);

        t.* = .{ .function_proto = .{
            .return_type = return_type,
            .parameters = undefined,
            .num_parameters = 0,
        } };

        var c: usize = 0;
        for (params) |param| {
            t.function_proto.parameters[c] = param;
            c += 1;
        }

        t.function_proto.num_parameters = params.len;

        return t;
    }
    //
    // pub fn displayName(self: *Type) [*:0]const u8 {
    //     return switch (self.*) {
    //         .primitive => |kind| switch (kind) {
    //             .Void => "void",
    //             .Bool => "bool",
    //             .UChar => "uchar",
    //             .UShort => "ushort",
    //             .UInt => "uint",
    //             .ULong => "ulong",
    //             .ULongLong => "ulonglong",
    //             .UInt128 => "uint128",
    //             .SChar => "schar",
    //             .WChar => "wcar",
    //             .Short => "short",
    //             .Int => "int",
    //             .Long => "long",
    //             .LongLong => "longlong",
    //             .Int128 => "int128",
    //             .Float => "float",
    //             .Double => "double",
    //             .LongDouble => "longdouble",
    //             .NullPtr => "nullptr",
    //             .Half => "half",
    //             //else => "unknown!",
    //         },
    //         .array => |array| "ARRAY " ++ array.element_type.displayName(),
    //         else => "Unknown Type",
    //     };
    // }

    pub fn print(self: *Type, w: anytype) !void {
        switch (self.*) {
            .primitive => |primitive| {
                const name: []const u8 = switch (primitive.kind) {
                    .Void => "void",
                    .Bool => "bool",
                    .UChar => "uchar",
                    .UShort => "ushort",
                    .UInt => "uint",
                    .ULong => "ulong",
                    .ULongLong => "ulonglong",
                    .UInt128 => "uint128",
                    .SChar => "schar",
                    .WChar => "wcar",
                    .Short => "short",
                    .Int => "int",
                    .Long => "long",
                    .LongLong => "longlong",
                    .Int128 => "int128",
                    .Float => "float",
                    .Double => "double",
                    .LongDouble => "longdouble",
                    .NullPtr => "nullptr",
                    .Half => "half",
                    //else => "unknown!",
                };
                try w.print("[[ {s} ", .{name});
                if (primitive.is_const) {
                    try w.print("(const)", .{});
                }
                try w.print(" ]]", .{});
            },
            .array => |array| {
                try w.print("[[ ARRAY ]] -> ", .{});
                try array.element_type.print(w);
            },
            .pointer => |pointer| {
                try w.print("[[ POINTER ", .{});
                switch (pointer.nullability) {
                    .nonnull => {
                        try w.print(" (nonnull) ", .{});
                    },
                    .nullable => {
                        try w.print(" (nullable) ", .{});
                    },
                    else => {},
                }
                try w.print("]] -> ", .{});
                try pointer.pointee.print(w);
            },

            .class => |name| {
                try w.print("[[ CLASS {s}]]", .{name});
            },

            .sel => {
                try w.print("[[ SEL  ]]", .{});
            },

            .id => |name| {
                if (name) |name_str| {
                    try w.print("[[ ID<{s}>]]", .{name_str});
                } else {
                    try w.print("[[ ID ]]", .{});
                }
            },

            .type_param => |name| {
                try w.print("[[ TYPE_PARAM {s}]]", .{name});
            },

            .enumeration => |name| {
                try w.print("[[ ENUMERATION {s}]]", .{name});
            },

            .record => |name| {
                try w.print("[[ RECORD {s}]]", .{name});
            },

            .block_pointer => {
                try w.print("[[ BLOCK_POINTER ]]", .{});
            },

            .function_proto => {
                try w.print("[[ FUNCTION_POINTER ]]", .{});
            },

            .interface => |name| {
                try w.print("[[ INTERFACE {s}]]", .{name});
            },

            .instancetype => {
                try w.print("[[ INSTANCETYPE ]]", .{});
            },

            .unimplemented => {
                try w.print("[[ UNIMPLEMENTED ]]", .{});
            },
        }
    }
};

test {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    // try common.write_spaces(1, std.io.getStdErr().writer());

    const t = Type.createPrimitive(arena.allocator(), .Int);
    // try t.print(0, std.io.getStdErr().writer());

    const arr = Type.createArray(arena.allocator(), t, false, 10);
    _ = arr;
    // try arr.print(1, std.io.getStdErr().writer());

    const ptr = Type.createPointer(arena.allocator(), t, .nullable);
    _ = ptr;

    const obj_id_prot = Type.createObjCIdProtocolObject(arena.allocator(), "MTLDevice");
    _ = obj_id_prot;

    const obj_interface = Type.createObjCInterfaceObject(arena.allocator(), &[_]*Type{
        Type.createTypeParam(arena.allocator(), "ObjecType"),
        Type.createInterface(arena.allocator(), "NSString"),
    });

    try std.testing.expectEqual(obj_interface.object.interface.num_type_args, 2);

    const class = Type.createClass(arena.allocator(), "Class");
    _ = class;

    const sel = Type.createSel(arena.allocator());
    _ = sel;

    const enumeration = Type.createEnumeration(arena.allocator(), "Enumeration");
    _ = enumeration;

    const bp = Type.createBlockPointer(arena.allocator(), t, &[_]*Type{t});
    try std.testing.expectEqual(bp.block_pointer.num_parameters, 1);

    const fp = Type.createFunctionProto(arena.allocator(), t, &[_]*Type{t});
    try std.testing.expectEqual(fp.function_proto.num_parameters, 1);
}
