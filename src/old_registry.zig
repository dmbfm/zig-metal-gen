const std = @import("std");
const common = @import("common.zig");
const c = @cImport({
    @cInclude("clang-c/Index.h");
});

const stdout = std.io.getStdOut().writer();
const c_string = common.c_string;
const print = common.print;
const println = common.println;

const Type = @import("type.zig").Type;
const Container = @import("container.zig").Container;
const Enum = @import("enum.zig").Enum;

pub const Context = struct {
    enumeration: c_string,
    container: union(enum) {
        interface: c_string,
        protocol: c_string,
        none: void,
    },
    method: ?void,

    pub fn init() Context {
        return .{
            .enumeration = "__GLOBAL__",
            .container = .none,
            .method = null,
        };
    }

    pub fn setProtocol(self: *Context, name: c_string) void {
        self.container = .{ .protocol = name };
    }

    pub fn setInterface(self: *Context, name: c_string) void {
        self.container = .{ .interface = name };
    }

    pub fn setEnumeration(self: *Context, name: c_string) void {
        self.enumeration = name;
    }
};

pub const Registry = struct {
    protocol_map: std.StringHashMap(Container),
    interface_map: std.StringHashMap(Container),
    enum_map: std.StringHashMap(Enum),
    allocator: std.mem.Allocator,

    ctx: Context = Context.init(),

    const Self = @This();

    pub fn init(self: *Self, allocator: std.mem.Allocator) void {
        self.protocol_map = std.StringHashMap(Container).init(allocator);
        self.interface_map = std.StringHashMap(Container).init(allocator);
        self.enum_map = std.StringHashMap(Enum).init(allocator);
        self.allocator = allocator;

        // This will hold unnamed global enums
        self.registerEnum("__GLOBAL__", Type.createPrimitive(allocator, Type.Primitive.LongLong));
    }

    pub fn registerProtocol(self: *Self, name: c_string) void {
        var slice = std.mem.sliceTo(name, 0);
        if (self.protocol_map.contains(slice)) {
            std.debug.panic("Protocol '{s}' already registered!", .{name});
        }

        self.protocol_map.put(slice, Container.init(self.allocator, name)) catch {
            std.debug.panic("Failed to register protocol '{s}' ", .{name});
        };
    }

    pub fn registerInterface(self: *Self, name: c_string) void {
        var slice = std.mem.sliceTo(name, 0);

        if (self.interface_map.contains(slice)) {
            std.debug.panic("Interface '{s}' already registered!", .{name});
        }

        self.interface_map.put(slice, Container.init(self.allocator, name)) catch {
            std.debug.panic("Failed to register Interface '{s}' ", .{name});
        };
    }

    pub fn registerEnum(self: *Self, name: c_string, enum_type: *Type) void {
        var slice = std.mem.sliceTo(name, 0);

        // These are unnamed enums that will be stored under the __GLOBAL__ name.
        if (std.mem.startsWith(u8, slice, "enum (")) {
            return;
        }

        if (self.enum_map.contains(slice)) {
            return;
            //std.debug.panic("Interface '{s}' already registered!", .{name});
        }

        self.enum_map.put(slice, Enum.init(self.allocator, name, enum_type)) catch {
            std.debug.panic("Failed to register Interface '{s}' ", .{name});
        };
    }

    pub fn addEnumValue(self: *Self, value: Enum.Value) void {
        var name = std.mem.sliceTo(self.ctx.enumeration, 0);

        var e = self.enum_map.getPtr(name) orelse {
            std.debug.panic("Enum '{s}' not found!", .{name});
        };

        e.addValue(value);
    }

    pub fn addMethod(self: *Self, method: Container.Method) void {
        var container = switch (self.ctx.container) {
            .interface => |name| self.interface_map.getPtr(std.mem.sliceTo(name, 0)),
            .protocol => |name| self.protocol_map.getPtr(std.mem.sliceTo(name, 0)),
            else => {
                std.debug.panic("Invalid context: expected Interface or Protocol, found: (Method name: {s})", .{method.name});
            },
        } orelse {
            std.debug.panic("Container not found!", .{});
        };

        container.addMethod(method);
    }

    pub fn print(self: Self) void {
        {
            var it = self.protocol_map.iterator();

            //try stdout.print("PROTOCOLS:\n", .{});
            println("PROTOCOLS:", .{});
            while (it.next()) |entry| {
                var p = entry.value_ptr;
                println("\t'{s}({})'", .{ p.name, p.methods.items.len });
                for (p.methods.items) |method| {
                    println("\t\t {s}", .{method.name});
                }
            }
        }

        {
            var it = self.interface_map.iterator();
            println("INTERFACES:", .{});
            while (it.next()) |entry| {
                var p = entry.value_ptr;
                println("\t'{s}'", .{p.name});

                for (p.methods.items) |method| {
                    println("\t\t {s}", .{method.name});
                }
            }
        }

        {
            var it = self.enum_map.iterator();
            println("ENUMS:", .{});
            while (it.next()) |entry| {
                var e = entry.value_ptr;
                println("\t'{s} ({s})'", .{ e.name, "" });

                for (e.values.items) |val| {
                    println("\t\t{s} = {} ({})", .{ val.name, val.value, val.ivalue });
                }
            }
        }
    }

    pub fn build(self: *Self, path: c_string) void {
        var idx = c.clang_createIndex(0, 0);

        var tu = c.clang_parseTranslationUnit(idx, path, null, 0, null, 0, c.CXTranslationUnit_IncludeAttributedTypes);
        var cursor = c.clang_getTranslationUnitCursor(tu);
        _ = c.clang_visitChildren(cursor, &visitor, @ptrCast(self));
    }
};

fn visitor(cursor: c.CXCursor, parent: c.CXCursor, data: c.CXClientData) callconv(.C) c.CXChildVisitResult {
    _ = parent;
    var registry: *Registry = @ptrCast(@alignCast(data));

    switch (cursor.kind) {

        // Protocols
        c.CXCursor_ObjCProtocolDecl => {
            var name = c.clang_getCString(c.clang_getCursorDisplayName(cursor));

            registry.registerProtocol(name);
            registry.ctx.setProtocol(name);

            return c.CXChildVisit_Recurse;
        },

        // Interfaces
        c.CXCursor_ObjCInterfaceDecl => {
            var name = c.clang_getCString(c.clang_getCursorDisplayName(cursor));

            registry.registerInterface(name);
            registry.ctx.setInterface(name);

            return c.CXChildVisit_Recurse;
        },

        // Methods
        c.CXCursor_ObjCInstanceMethodDecl, c.CXCursor_ObjCClassMethodDecl => {
            var name = c.clang_getCString(c.clang_getCursorDisplayName(cursor));

            var is_instance = (cursor.kind == c.CXCursor_ObjCInstanceMethodDecl);

            //println("method: {s}", .{name});

            registry.addMethod(.{
                .name = name,
                .is_instance = is_instance,
                .return_type = &Type._void,
                .param_types = std.ArrayList(*Type).init(registry.allocator),
            });

            var rt = c.clang_getCursorResultType(cursor);
            _ = rt;
            // dump_type(rt);

            var n: usize = @intCast(c.clang_Cursor_getNumArguments(cursor));
            // println("n = {}", .{n});

            for (0..n) |i| {
                var ac = c.clang_Cursor_getArgument(cursor, @intCast(i));
                var at = c.clang_getCursorType(ac);
                _ = at;
                // dump_type(at);
            }
        },

        // Enums
        c.CXCursor_EnumDecl => {
            var name = c.clang_getCString(c.clang_getCursorDisplayName(cursor));
            var enum_type = c.clang_getEnumDeclIntegerType(cursor);
            var enum_type_string = c.clang_getCString(c.clang_getTypeSpelling(enum_type));
            _ = enum_type_string;

            // Store un-named enums under the __GLOBAL__ name.
            if (std.mem.startsWith(u8, std.mem.sliceTo(name, 0), "enum (")) {
                registry.ctx.setEnumeration("__GLOBAL__");
            } else {
                registry.registerEnum(name, &Type._ulonglong); //enum_type_string);
                registry.ctx.setEnumeration(name);
            }

            return c.CXChildVisit_Recurse;
        },

        // Enum values
        c.CXCursor_EnumConstantDecl => {
            var name = c.clang_getCString(c.clang_getCursorDisplayName(cursor));
            var ivalue = c.clang_getEnumConstantDeclValue(cursor);
            var value = c.clang_getEnumConstantDeclUnsignedValue(cursor);

            registry.addEnumValue(.{ .name = name, .value = @intCast(value), .ivalue = @intCast(ivalue) });
        },

        else => {},
    }

    return c.CXChildVisit_Continue;
}

fn dump_type(t: c.CXType) void {
    var type_name_str = c.clang_getTypeSpelling(t);
    var type_name = c.clang_getCString(type_name_str);
    defer c.clang_disposeString(type_name_str);

    var kind_name_str = c.clang_getTypeKindSpelling(t.kind);
    var kind_name = c.clang_getCString(kind_name_str);
    defer c.clang_disposeString(kind_name_str);

    switch (t.kind) {
        c.CXType_Void,
        c.CXType_Bool,
        c.CXType_Char_U,
        c.CXType_UChar,
        c.CXType_Char16,
        c.CXType_Char32,
        c.CXType_UShort,
        c.CXType_UInt,
        c.CXType_ULong,
        c.CXType_ULongLong,
        c.CXType_UInt128,
        c.CXType_Char_S,
        c.CXType_SChar,
        c.CXType_WChar,
        c.CXType_Short,
        c.CXType_Int,
        c.CXType_Long,
        c.CXType_LongLong,
        c.CXType_Int128,
        c.CXType_Float,
        c.CXType_Double,
        c.CXType_LongDouble,
        c.CXType_NullPtr,
        c.CXType_Float128,
        c.CXType_Half,
        c.CXType_Float16,
        c.CXType_ShortAccum,
        c.CXType_Accum,
        c.CXType_LongAccum,
        c.CXType_UShortAccum,
        c.CXType_UAccum,
        c.CXType_ULongAccum,
        c.CXType_BFloat16,
        c.CXType_Ibm128,
        => {
            println("[dump_type]: simple type: {s} [{s}]", .{ type_name, kind_name });
        },

        c.CXType_Invalid => {
            println("[dump_type]: CXType_Invalid", .{});
        },
        c.CXType_Unexposed => {
            println("[dump_type]: Unexposed: {s} [{s}]", .{ type_name, kind_name });
        },
        c.CXType_Overload,
        c.CXType_Dependent,
        //c.CXType_FirstBuiltin,
        //c.CXType_LastBuiltin,
        c.CXType_Complex,
        c.CXType_FunctionNoProto,
        c.CXType_Vector,
        c.CXType_VariableArray,
        c.CXType_DependentSizedArray,
        c.CXType_MemberPointer,
        c.CXType_Auto,
        c.CXType_Pipe,
        c.CXType_OCLImage1dRO,
        c.CXType_OCLImage1dArrayRO,
        c.CXType_OCLImage1dBufferRO,
        c.CXType_OCLImage2dRO,
        c.CXType_OCLImage2dArrayRO,
        c.CXType_OCLImage2dDepthRO,
        c.CXType_OCLImage2dArrayDepthRO,
        c.CXType_OCLImage2dMSAARO,
        c.CXType_OCLImage2dArrayMSAARO,
        c.CXType_OCLImage2dMSAADepthRO,
        c.CXType_OCLImage2dArrayMSAADepthRO,
        c.CXType_OCLImage3dRO,
        c.CXType_OCLImage1dWO,
        c.CXType_OCLImage1dArrayWO,
        c.CXType_OCLImage1dBufferWO,
        c.CXType_OCLImage2dWO,
        c.CXType_OCLImage2dArrayWO,
        c.CXType_OCLImage2dDepthWO,
        c.CXType_OCLImage2dArrayDepthWO,
        c.CXType_OCLImage2dMSAAWO,
        c.CXType_OCLImage2dArrayMSAAWO,
        c.CXType_OCLImage2dMSAADepthWO,
        c.CXType_OCLImage2dArrayMSAADepthWO,
        c.CXType_OCLImage3dWO,
        c.CXType_OCLImage1dRW,
        c.CXType_OCLImage1dArrayRW,
        c.CXType_OCLImage1dBufferRW,
        c.CXType_OCLImage2dRW,
        c.CXType_OCLImage2dArrayRW,
        c.CXType_OCLImage2dDepthRW,
        c.CXType_OCLImage2dArrayDepthRW,
        c.CXType_OCLImage2dMSAARW,
        c.CXType_OCLImage2dArrayMSAARW,
        c.CXType_OCLImage2dMSAADepthRW,
        c.CXType_OCLImage2dArrayMSAADepthRW,
        c.CXType_OCLImage3dRW,
        c.CXType_OCLSampler,
        c.CXType_OCLEvent,
        c.CXType_OCLQueue,
        c.CXType_OCLReserveID,
        c.CXType_OCLIntelSubgroupAVCMcePayload,
        c.CXType_OCLIntelSubgroupAVCImePayload,
        c.CXType_OCLIntelSubgroupAVCRefPayload,
        c.CXType_OCLIntelSubgroupAVCSicPayload,
        c.CXType_OCLIntelSubgroupAVCMceResult,
        c.CXType_OCLIntelSubgroupAVCImeResult,
        c.CXType_OCLIntelSubgroupAVCRefResult,
        c.CXType_OCLIntelSubgroupAVCSicResult,
        c.CXType_OCLIntelSubgroupAVCImeResultSingleReferenceStreamout,
        c.CXType_OCLIntelSubgroupAVCImeResultDualReferenceStreamout,
        c.CXType_OCLIntelSubgroupAVCImeSingleReferenceStreamin,
        c.CXType_OCLIntelSubgroupAVCImeDualReferenceStreamin,
        //c.CXType_OCLIntelSubgroupAVCImeResultSingleRefStreamout,
        //c.CXType_OCLIntelSubgroupAVCImeResultDualRefStreamout,
        //c.CXType_OCLIntelSubgroupAVCImeSingleRefStreamin,
        //c.CXType_OCLIntelSubgroupAVCImeDualRefStreamin,
        c.CXType_ExtVector,
        c.CXType_Atomic,
        c.CXType_BTFTagAttributed,
        c.CXType_LValueReference,
        c.CXType_RValueReference,
        => {
            std.debug.panic("Unsupported type: {s} [{s}]", .{ type_name, kind_name });
        },

        c.CXType_IncompleteArray => {
            var size = c.clang_getArraySize(t);
            println("[dump_type][INCOMPLETE_ARRAY[{}]]: {s} [{s}]", .{ size, type_name, kind_name });
        },

        c.CXType_ConstantArray => {
            var size = c.clang_getArraySize(t);
            println("[dump_type][CONSTANT_ARRAY[{}]]: {s} [{s}]", .{ size, type_name, kind_name });
            var et = c.clang_getArrayElementType(t);
            dump_type(et);
        },

        c.CXType_ObjCObjectPointer => {
            println("[dump_type][OBJC_POINTER]: {s} [{s}]", .{ type_name, kind_name });

            var pt = c.clang_getPointeeType(t);
            dump_type(pt);
        },

        c.CXType_ObjCInterface => {
            var n = c.clang_Type_getNumObjCTypeArgs(t);
            println("[dump_type][OBJC_INTERFACE] {s} [{s}] num_type_args: {}", .{ type_name, kind_name, n });
        },

        c.CXType_ObjCObject => {
            var n: usize = @intCast(c.clang_Type_getNumObjCTypeArgs(t));
            println("[dump_type][OBJC_OBJECT] {s} [{s}] num_type_args: {}", .{ type_name, kind_name, n });

            var bt = c.clang_Type_getObjCObjectBaseType(t);
            dump_type(bt);

            for (0..n) |i| {
                var ta = c.clang_Type_getObjCTypeArg(t, @intCast(i));
                dump_type(ta);
            }

            var num_protocols: usize = @intCast(c.clang_Type_getNumObjCProtocolRefs(t));
            for (0..num_protocols) |i| {
                var tp = c.clang_Type_getObjCProtocolDecl(t, @intCast(i));

                if (tp.kind != c.CXCursor_ObjCProtocolDecl) {
                    std.debug.panic("Expetect protocol declaration!", .{});
                }

                println("[dump_type][OBJC_OBJECT][PROTOCOL]{s}", .{c.clang_getCString(c.clang_getCursorDisplayName(tp))});
            }
        },
        c.CXType_ObjCId => {
            println("[dump_type][OBJC_ID] {s} [{s}]", .{ type_name, kind_name });
        },
        c.CXType_ObjCClass => {
            println("[dump_type][OBJC_CLASS] {s} [{s}]", .{ type_name, kind_name });
        },
        c.CXType_ObjCSel => {
            println("[dump_type][OBJC_SEL] {s} [{s}]", .{ type_name, kind_name });
        },
        c.CXType_ObjCTypeParam => {
            println("[dump_type][OBJC_TYPE_PARAM] {s} [{s}]", .{ type_name, kind_name });
        },

        c.CXType_Pointer => {
            println("[dump_type][POINTER] {s} [{s}]", .{ type_name, kind_name });

            var pt = c.clang_getPointeeType(t);
            dump_type(pt);
        },
        c.CXType_BlockPointer => {
            println("[dump_type][BLOCK_POINTER] {s} [{s}]", .{ type_name, kind_name });

            var pt = c.clang_getPointeeType(t);
            dump_type(pt);
        },

        c.CXType_Record => {
            println("[dump_type][RECORD] {s} [{s}]", .{ type_name, kind_name });

            var tdc = c.clang_getTypeDeclaration(t);
            println("[dump_type][RECORD][DECL]: {s}", .{c.clang_getCString(c.clang_getCursorDisplayName(tdc))});

            _ = c.clang_visitChildren(tdc, &dump_struct_visitor, null);
        },
        c.CXType_Elaborated => {
            println("[dump_type][ELABORATED] {s} [{s}]", .{ type_name, kind_name });
            var cursor = c.clang_getTypeDeclaration(t);
            var ct = c.clang_getCursorType(cursor);
            dump_type(ct);
        },
        c.CXType_Attributed => {
            var nullability = c.clang_Type_getNullability(t);
            var n: []const u8 = switch (nullability) {
                c.CXTypeNullability_NonNull => "nonull",
                c.CXTypeNullability_Invalid => "invalid",
                c.CXTypeNullability_Nullable => "nullable",
                c.CXTypeNullability_Unspecified => "unspecified",
                c.CXTypeNullability_NullableResult => "nullable_result",
                else => "",
            };
            println("[dump_type][ATTRIBUTED] {s} [{s}] nullability: {s}", .{ type_name, kind_name, n });

            var at = c.clang_Type_getModifiedType(t);
            dump_type(at);
        },
        c.CXType_Enum => {
            println("[dump_type][ENUM] {s} [{s}]", .{ type_name, kind_name });
            var cursor = c.clang_getTypeDeclaration(t);
            _ = c.clang_visitChildren(cursor, &dump_enum_visitor, null);
        },
        c.CXType_Typedef => {
            var typedef_name_str = c.clang_getTypedefName(t);
            defer c.clang_disposeString(typedef_name_str);
            println("[dump_type][TYPEDEF] {s} [{s}] typedefName = {s}", .{ type_name, kind_name, c.clang_getCString(typedef_name_str) });
            var cursor = c.clang_getTypeDeclaration(t);
            var ct = c.clang_getTypedefDeclUnderlyingType(cursor);
            dump_type(ct);
        },

        c.CXType_FunctionProto => {
            println("[dump_type][FUNCTION_PROTOTYPE] {s} [{s}]", .{ type_name, kind_name });
            var rt = c.clang_getResultType(t);
            dump_type(rt);

            var n: usize = @intCast(c.clang_getNumArgTypes(t));
            for (0..n) |i| {
                var at = c.clang_getArgType(t, @intCast(i));
                dump_type(at);
            }
        },
        else => {
            std.debug.panic("Unknown type: {s} [{s}]", .{ type_name, kind_name });
        },
    }
}

fn dump_enum_visitor(cursor: c.CXCursor, parent: c.CXCursor, data: c.CXClientData) callconv(.C) c.CXChildVisitResult {
    _ = data;
    _ = parent;
    switch (cursor.kind) {
        c.CXCursor_EnumConstantDecl => {
            var name = c.clang_getCString(c.clang_getCursorDisplayName(cursor));
            var ivalue = c.clang_getEnumConstantDeclValue(cursor);
            var value = c.clang_getEnumConstantDeclUnsignedValue(cursor);
            println("[dump_print][enum value]:{s} = {} ({})", .{ name, value, ivalue });
        },
        else => {},
    }

    return c.CXChildVisit_Continue;
}

fn dump_struct_visitor(cursor: c.CXCursor, parent: c.CXCursor, data: c.CXClientData) callconv(.C) c.CXChildVisitResult {
    _ = data;
    _ = parent;

    println("!!!!!!!", .{});
    println("-->{s}", .{c.clang_getCString(c.clang_getCursorDisplayName(cursor))});

    switch (cursor.kind) {
        c.CXCursor_FieldDecl => {
            var t = c.clang_getCursorType(cursor);
            dump_type(t);
            // println("FIELD!", .{});
        },
        else => {},
    }

    return c.CXChildVisit_Continue;
}
