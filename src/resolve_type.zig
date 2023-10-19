const std = @import("std");
const common = @import("common.zig");
const c_string = common.c_string;
const Enum = @import("enum.zig").Enum;
const Record = @import("record.zig").Record;
const Container = @import("container.zig").Container;
const sliceFromCString = common.sliceFromCString;
const print = common.print;
const println = common.println;
const Type = @import("type.zig").Type;
const c = @import("c.zig");
const Registry = @import("registry.zig").Registry;

const ResolveTypeContext = struct {
    allocator: std.mem.Allocator,
    registry: ?*Registry = null,
    enumeration: ?*Enum = null,
    record: ?*Record = null,
};

pub fn resolveType(allocator: std.mem.Allocator, r: *Registry, t: c.CXType) *Type {
    var type_name_str = c.clang_getTypeSpelling(t);
    var type_name = c.clang_getCString(type_name_str);
    // defer c.clang_disposeString(type_name_str);

    var kind_name_str = c.clang_getTypeKindSpelling(t.kind);
    var kind_name = c.clang_getCString(kind_name_str);
    // defer c.clang_disposeString(kind_name_str);

    var is_const = c.clang_isConstQualifiedType(t) != 0;

    switch (t.kind) {
        c.CXType_Void => {
            return if (is_const) &Type._const_void else &Type._void;
        },
        c.CXType_Bool => {
            return if (is_const) &Type._const_bool else &Type._bool;
        },
        c.CXType_UChar => {
            return if (is_const) &Type._const_uchar else &Type._uchar;
        },
        c.CXType_UShort => {
            return if (is_const) &Type._const_ushort else &Type._ushort;
        },
        c.CXType_UInt => {
            return if (is_const) &Type._const_uint else &Type._uint;
        },
        c.CXType_ULong => {
            return if (is_const) &Type._const_ulong else &Type._ulong;
        },
        c.CXType_ULongLong => {
            return if (is_const) &Type._const_ulonglong else &Type._ulonglong;
        },
        c.CXType_UInt128 => {
            return if (is_const) &Type._const_uint128 else &Type._uint128;
        },
        c.CXType_SChar, c.CXType_Char_S => {
            return if (is_const) &Type._const_schar else &Type._schar;
        },
        c.CXType_WChar => {
            return if (is_const) &Type._const_wchar else &Type._wchar;
        },
        c.CXType_Short => {
            return if (is_const) &Type._const_short else &Type._short;
        },
        c.CXType_Int => {
            return if (is_const) &Type._const_int else &Type._int;
        },
        c.CXType_Long => {
            return if (is_const) &Type._const_long else &Type._long;
        },
        c.CXType_LongLong => {
            return if (is_const) &Type._const_longlong else &Type._longlong;
        },
        c.CXType_Int128 => {
            return if (is_const) &Type._const_int128 else &Type._int128;
        },
        c.CXType_Float => {
            return if (is_const) &Type._const_float else &Type._float;
        },
        c.CXType_Double => {
            return if (is_const) &Type._const_double else &Type._double;
        },
        c.CXType_LongDouble => {
            return if (is_const) &Type._const_longdouble else &Type._longdouble;
        },
        c.CXType_NullPtr => {
            return if (is_const) &Type._const_null_ptr else &Type._null_ptr;
        },
        c.CXType_Half => {
            return if (is_const) &Type._const_half else &Type._half;
        },

        c.CXType_Invalid => {
            std.debug.panic("Invalid type!", .{});
        },

        c.CXType_Unexposed => {
            var mt = c.clang_Type_getModifiedType(t);
            return resolveType(allocator, r, mt);
        },

        c.CXType_IncompleteArray, c.CXType_ConstantArray => {
            var size = c.clang_getArraySize(t);
            var et = c.clang_getArrayElementType(t);

            if (size < 0) {
                size = 0;
            }

            var incomplete = t.kind == c.CXType_IncompleteArray;

            var arr = Type.createArray(allocator, resolveType(allocator, r, et), incomplete, @intCast(size));
            if (is_const) {
                arr.array.is_const = true;
            }
            return arr;
        },

        c.CXType_Pointer, c.CXType_ObjCObjectPointer => {
            var pt = c.clang_getPointeeType(t);
            var result = Type.createPointer(allocator, resolveType(allocator, r, pt), .none);
            if (is_const) {
                // @panic("???????");
                result.pointer.is_const = true;
            }
            return result;
        },

        c.CXType_ObjCInterface => {
            // std.log.info("name = {s}", .{type_name});
            return Type.createInterface(allocator, type_name); //createObjCInterfaceObject(allocator, type_name, &[_]*Type{});
        },

        c.CXType_ObjCObject => {
            // println("CXType_ObjCObject: {s}", .{type_name});
            // c.clang_Type_getc
            var base_type = resolveType(allocator, r, c.clang_Type_getObjCObjectBaseType(t));
            var num_protocols: usize = @intCast(c.clang_Type_getNumObjCProtocolRefs(t));

            switch (base_type.*) {
                .id => {
                    if (num_protocols == 1) {
                        var tp = c.clang_Type_getObjCProtocolDecl(t, 0);
                        var protocol_name = c.clang_getCString(c.clang_getCursorDisplayName(tp));
                        return Type.createIdProtocol(allocator, protocol_name);
                    } else {
                        return base_type;
                    }
                },
                .sel => {
                    return base_type;
                },

                .class => {
                    return base_type;
                },

                .interface => {
                    return base_type;
                },

                else => {
                    std.debug.panic("{?}", .{base_type.*});
                },
            }
        },

        c.CXType_ObjCId => {
            //var cursor = c.clang_getdec(t);
            //var extends = c.clang_getCursorExtent(cursor);
            //var toks: [*c]c.CXToken = undefined;
            //var num_toks: c_uint = 0;
            //c.clang_tokenize(r.tu, extends, &toks, &num_toks);
            //std.log.info("n = {}", .{num_toks});
            //for (0..@intCast(num_toks)) |i| {
            //    std.log.info("tok[{}] = {s}", .{
            //        i,
            //        c.clang_getCString(c.clang_getTokenSpelling(r.tu, toks[i])),
            //    });
            //}

            return Type.createId(allocator);
        },

        c.CXType_ObjCSel => {
            return Type.createSel(allocator);
        },

        c.CXType_ObjCClass => {
            return Type.createClass(allocator, type_name);
        },

        // c.CXType_ObjCObjectPointer => {
        // println("[dump_type][OBJC_POINTER]: {s} [{s}]", .{ type_name, kind_name });
        // },

        c.CXType_Attributed => {
            var clang_nullability = c.clang_Type_getNullability(t);
            var nullability: Type.Pointer.Nullability = switch (clang_nullability) {
                c.CXTypeNullability_NonNull => .nonnull,
                c.CXTypeNullability_Invalid => .none,
                c.CXTypeNullability_Nullable => .nullable,
                c.CXTypeNullability_Unspecified => .none,
                c.CXTypeNullability_NullableResult => .nullable,
                else => .none,
            };

            var at = c.clang_Type_getModifiedType(t);
            var resolved_type = resolveType(allocator, r, at);

            switch (resolved_type.*) {
                .pointer => |*pointer| {
                    pointer.nullability = nullability;
                },
                else => {},
            }

            return resolved_type;
        },

        c.CXType_Enum => {
            var cursor = c.clang_getTypeDeclaration(t);
            var enum_type = resolveType(allocator, r, c.clang_getEnumDeclIntegerType(cursor));

            if (!r.hasEnum(sliceFromCString(type_name))) {
                var enumeration = Enum.init(allocator, type_name, enum_type);

                var ctx = ResolveTypeContext{ .allocator = allocator, .enumeration = &enumeration };
                _ = c.clang_visitChildren(
                    cursor,
                    &enum_visitor,
                    @ptrCast(&ctx),
                );

                r.addEnum(enumeration);
            }

            return Type.createEnumeration(allocator, type_name);
        },

        c.CXType_Elaborated => {
            var cursor = c.clang_getTypeDeclaration(t);
            var ct = c.clang_getCursorType(cursor);
            return resolveType(allocator, r, ct);
        },

        c.CXType_Typedef => {
            if (std.mem.eql(u8, sliceFromCString(type_name), "instancetype")) {
                return &Type._instancetype;
            }

            var cursor = c.clang_getTypeDeclaration(t);
            var ct = c.clang_getTypedefDeclUnderlyingType(cursor);
            return resolveType(allocator, r, ct);
        },

        c.CXType_Record => {
            var decl = c.clang_getTypeDeclaration(t);
            var decl_name = c.clang_getCString(c.clang_getCursorDisplayName(decl));

            // std.log.info("RECORD: {s} ", .{decl_name});

            if (!r.hasRecord(sliceFromCString(decl_name))) {
                var record = Record.init(allocator, decl_name);
                var ctx = ResolveTypeContext{
                    .allocator = allocator,
                    .record = &record,
                    .registry = r,
                };
                _ = c.clang_visitChildren(
                    decl,
                    &record_visitor,
                    @ptrCast(&ctx),
                );
                r.addRecord(record);
            }

            return Type.createRecord(allocator, decl_name);
        },

        c.CXType_FunctionProto => {
            var rt = c.clang_getResultType(t);
            var result_type = resolveType(allocator, r, rt);

            var n: usize = @intCast(c.clang_getNumArgTypes(t));

            if (n > Type.max_func_params) {
                std.debug.panic("[CXType_FunctionProto]: More than {} params!", .{Type.max_func_params});
            }

            var params: [Type.max_func_params]*Type = undefined;

            for (0..n) |i| {
                var at = c.clang_getArgType(t, @intCast(i));
                params[i] = resolveType(allocator, r, at);
            }

            return Type.createFunctionProto(allocator, result_type, params[0..n]);
        },

        c.CXType_ObjCTypeParam => {
            // std.log.info("TypeParam: {s}", .{type_name});
            return Type.createId(allocator);
        },

        c.CXType_BlockPointer => {
            var pt = c.clang_getPointeeType(t);
            var fproto_type = resolveType(allocator, r, pt);
            return Type.createBlockPointer(allocator, fproto_type.function_proto);
        },

        else => {
            std.debug.panic("NOT IMPLEMENTEd: {s}, {s}", .{ type_name, kind_name });
            return &Type._unimplemented;
        },
    }

    return &Type._unimplemented;
}

fn record_visitor(cursor: c.CXCursor, _: c.CXCursor, data: c.CXClientData) callconv(.C) c.CXChildVisitResult {
    var ctx: *ResolveTypeContext = @ptrCast(@alignCast(data));

    switch (cursor.kind) {
        c.CXCursor_FieldDecl => {
            var t = c.clang_getCursorType(cursor);
            ctx.record.?.addField(.{
                .name = c.clang_getCString(c.clang_getCursorDisplayName(cursor)),
                .type = resolveType(ctx.allocator, ctx.registry.?, t),
            });
        },
        else => {},
    }

    return c.CXChildVisit_Continue;
}

fn enum_visitor(cursor: c.CXCursor, _: c.CXCursor, data: c.CXClientData) callconv(.C) c.CXChildVisitResult {
    var ctx: *ResolveTypeContext = @ptrCast(@alignCast(data));

    switch (cursor.kind) {
        c.CXCursor_EnumConstantDecl => {
            var name = c.clang_getCString(c.clang_getCursorDisplayName(cursor));
            var ivalue = c.clang_getEnumConstantDeclValue(cursor);
            var value = c.clang_getEnumConstantDeclUnsignedValue(cursor);

            ctx.enumeration.?.addValue(.{
                .name = name,
                .value = value,
                .ivalue = ivalue,
            });
        },
        else => {},
    }

    return c.CXChildVisit_Continue;
}
