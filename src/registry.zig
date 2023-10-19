const std = @import("std");
const common = @import("common.zig");
const c_string = common.c_string;
const Enum = @import("enum.zig").Enum;
const Function = @import("function.zig").Function;
const Container = @import("container.zig").Container;
const sliceFromCString = common.sliceFromCString;
// const print = common.print;
const println = common.println;
const Type = @import("type.zig").Type;
const c = @import("c.zig");
const Record = @import("record.zig").Record;
const resolveType = @import("resolve_type.zig").resolveType;

pub const Registry = struct {
    enums: std.StringHashMap(Enum),
    records: std.StringHashMap(Record),
    protocols: std.StringHashMap(Container),
    interfaces: std.StringHashMap(Container),
    functions: std.StringHashMap(Function),
    container_context: ContainerContext = .none,
    options: Options,
    allocator: std.mem.Allocator,
    tu: c.CXTranslationUnit = undefined,

    const Self = @This();

    const ContainerContext = union(enum) {
        interface: []const u8,
        protocol: []const u8,
        none: void,
    };

    const FunctionFilterFn = fn (name: []const u8) bool;
    const ContainerFilterFn = fn (name: []const u8) bool;

    const Options = struct {
        function_filter_fn: ?*const FunctionFilterFn,
        protocol_filter_fn: ?*const ContainerFilterFn,
        interface_filter_fn: ?*const ContainerFilterFn,
    };

    pub fn init(self: *Self, allocator: std.mem.Allocator, options: Options) void {
        self.options = options;
        self.allocator = allocator;
        self.records = std.StringHashMap(Record).init(allocator);
        self.enums = std.StringHashMap(Enum).init(allocator);
        self.protocols = std.StringHashMap(Container).init(allocator);
        self.interfaces = std.StringHashMap(Container).init(allocator);
        self.functions = std.StringHashMap(Function).init(allocator);
    }

    pub fn addFunction(self: *Self, f: Function) void {
        self.functions.put(sliceFromCString(f.name), f) catch {
            std.debug.panic("Failed to add function: {s}", .{f.name});
        };
    }

    pub fn addRecord(self: *Self, rec: Record) void {
        self.records.put(sliceFromCString(rec.name), rec) catch {
            std.debug.panic("Failed to add record: {s}", .{rec.name});
        };
    }

    pub fn hasRecord(self: *Self, name: []const u8) bool {
        return self.records.getPtr(name) != null;
    }

    pub fn addEnum(self: *Self, the_enum: Enum) void {
        self.enums.put(sliceFromCString(the_enum.name), the_enum) catch {
            std.debug.panic("Failed to add enum: {s}", .{the_enum.name});
        };
    }

    pub fn hasEnum(self: *Self, name: []const u8) bool {
        return self.enums.getPtr(name) != null;
    }

    pub fn addProtocol(self: *Self, protocol: Container) void {
        self.protocols.put(sliceFromCString(protocol.name), protocol) catch {
            std.debug.panic("Failed to add protocol: {s}", .{protocol.name});
        };
        self.container_context = .{ .protocol = sliceFromCString(protocol.name) };
    }

    pub fn addInterface(self: *Self, interface: Container) void {
        var slice = sliceFromCString(interface.name);

        if (self.interfaces.get(slice) == null) {
            self.interfaces.put(slice, interface) catch {
                std.debug.panic("Failed to add interface: {s}", .{interface.name});
            };
        }

        self.container_context = .{ .interface = slice };
    }

    pub fn addMethod(self: *Self, method: Container.Method) void {
        switch (self.container_context) {
            .interface => |name| {
                var ptr = self.interfaces.getPtr(name) orelse {
                    std.debug.panic("[addMethod]: Interface '{s}' not found!", .{name});
                };
                ptr.addMethod(method);
            },
            .protocol => |name| {
                var ptr = self.protocols.getPtr(name) orelse {
                    std.debug.panic("[addMethod]: Protocol '{s}' not found!", .{name});
                };
                ptr.addMethod(method);
            },
            else => {
                std.debug.panic("[addMethod]: Container context is none when adding method '{s}'", .{method.name});
            },
        }
    }

    pub fn setSuperClass(self: *Self, super_class_name: c_string) void {
        switch (self.container_context) {
            .interface => |name| {
                var ptr = self.interfaces.getPtr(name) orelse {
                    std.debug.panic("[addMethod]: Interface '{s}' not found!", .{name});
                };
                ptr.setSuperClass(super_class_name);
            },
            .protocol => |name| {
                var ptr = self.protocols.getPtr(name) orelse {
                    std.debug.panic("[addMethod]: Interface '{s}' not found!", .{name});
                };
                ptr.setSuperClass(super_class_name);
            },
            .none => {
                std.debug.panic("No context!", .{});
            },
        }
    }

    pub fn addConformingProtocol(self: *Self, protcol_name: c_string) void {
        switch (self.container_context) {
            .interface => |name| {
                var ptr = self.interfaces.getPtr(name) orelse {
                    std.debug.panic("[addMethod]: Interface '{s}' not found!", .{name});
                };
                ptr.addConformingProtocol(protcol_name);
            },
            .protocol => |name| {
                var ptr = self.protocols.getPtr(name) orelse {
                    std.debug.panic("[addMethod]: Interface '{s}' not found!", .{name});
                };
                ptr.addConformingProtocol(protcol_name);
            },
            .none => {
                std.debug.panic("No context!", .{});
            },
        }
    }

    pub fn build(self: *Self, path: c_string) void {
        var index = c.clang_createIndex(0, 0);

        self.tu = c.clang_parseTranslationUnit(index, path, null, 0, null, 0, c.CXTranslationUnit_IncludeAttributedTypes);
        //self.tu = c.clang_parseTranslationUnit(index, path, &[_][*:0]const u8{"-objcmt-migrate-instancetype"}, 1, null, 0, c.CXTranslationUnit_IncludeAttributedTypes);
        // self.tu = c.clang_parseTranslationUnit(index, path, &[_][*:0]const u8{ "-arch", "arm64", "-isysroot", "/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS17.0.sdk" }, 4, null, 0, c.CXTranslationUnit_IncludeAttributedTypes);
        // self.tu = c.clang_parseTranslationUnit(index, path, &[_][*:0]const u8{ "-isysroot", "/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS17.0.sdk" }, 2, null, 0, c.CXTranslationUnit_IncludeAttributedTypes);
        // _ = tu;
        var cursor = c.clang_getTranslationUnitCursor(self.tu);
        _ = c.clang_visitChildren(cursor, &main_visitor, @ptrCast(self));
    }

    fn protocolHandler(self: *Self, cursor: c.CXCursor, parent: c.CXCursor) c.CXChildVisitResult {
        std.debug.assert(cursor.kind == c.CXCursor_ObjCProtocolDecl);
        _ = parent;

        var name = c.clang_getCString(c.clang_getCursorDisplayName(cursor));

        if (self.options.protocol_filter_fn) |filter_fn| {
            if (!filter_fn(sliceFromCString(name))) {
                return c.CXChildVisit_Continue;
            }
        }

        var n = c.clang_Cursor_getNumTemplateArguments(cursor);
        // c.clang_Type_getNumTemplateArguments(T: CXType)
        var t = c.clang_getCursorType(cursor);
        _ = t;
        // var n = c.clang_Type_getNumObjCTypeArgs(t);
        if (n > 0) {
            std.log.info("num = {}", .{n});
        }

        var container = Container.init(self.allocator, name);
        self.addProtocol(container);

        _ = c.clang_visitChildren(cursor, &container_visitor, @ptrCast(self));

        //return c.CXChildVisit_Recurse;
        return c.CXChildVisit_Continue;
    }

    fn dumpCursorType(cursor: c.CXCursor) void {
        var t = c.clang_getCursorType(cursor);
        var rt = c.clang_getCursorResultType(cursor);

        println("dump_type: {s}, {s}, {s}", .{
            c.clang_getCString(c.clang_getTypeSpelling(t)),
            c.clang_getCString(c.clang_getTypeKindSpelling(t.kind)),
            c.clang_getCString(c.clang_getTypeSpelling(rt)),
        });
    }

    fn interfaceHandler(self: *Self, cursor: c.CXCursor, parent: c.CXCursor) c.CXChildVisitResult {
        std.debug.assert(cursor.kind == c.CXCursor_ObjCInterfaceDecl or cursor.kind == c.CXCursor_ObjCCategoryDecl);
        // c.clang_categor
        _ = parent;
        // c.clang_
        //
        var name = c.clang_getCString(c.clang_getCursorDisplayName(cursor));

        if (cursor.kind == c.CXCursor_ObjCCategoryDecl) {
            var ex = c.clang_getCursorExtent(cursor);

            var toks: [*c]c.CXToken = undefined;
            var num_toks: c_uint = 0;
            c.clang_tokenize(self.tu, ex, &toks, &num_toks);

            if (num_toks < 3) {
                std.debug.panic("Expected > 3 tokens for a category declaration!", .{});
            }

            var tok = toks[2];
            // var base_interface_name = c.clang_getCString(c.clang_getTokenSpelling(self.tu, tok));
            name = c.clang_getCString(c.clang_getTokenSpelling(self.tu, tok));

            // println("{s} -> base_interface_name: {s}", .{ name, base_interface_name });
            // name = base_interface_name;
        }

        if (self.options.interface_filter_fn) |filter_fn| {
            if (!filter_fn(sliceFromCString(name))) {
                return c.CXChildVisit_Continue;
            }
        }

        var container = Container.init(self.allocator, name);
        self.addInterface(container);

        _ = c.clang_visitChildren(cursor, &container_visitor, @ptrCast(self));

        //return c.CXChildVisit_Recurse;
        return c.CXChildVisit_Continue;
    }

    fn enumHandler(self: *Self, cursor: c.CXCursor, parent: c.CXCursor) c.CXChildVisitResult {
        std.debug.assert(cursor.kind == c.CXCursor_EnumDecl);
        _ = parent;
        _ = self;
        return c.CXChildVisit_Continue;
    }

    fn functionHandler(self: *Self, cursor: c.CXCursor, parent: c.CXCursor) c.CXChildVisitResult {
        std.debug.assert(cursor.kind == c.CXCursor_FunctionDecl);
        _ = parent;

        var name = c.clang_getCString(c.clang_getCursorDisplayName(cursor));
        // std.log.info("fname = {s}", .{name});

        if (self.options.function_filter_fn) |filter_fn| {
            if (!filter_fn(sliceFromCString(name))) {
                return c.CXChildVisit_Continue;
            }
        }

        // c.clang_name

        var rt = c.clang_getCursorResultType(cursor);
        var result_type = resolveType(self.allocator, self, rt);
        var f = Function.init(self.allocator, name, result_type);

        var n: usize = @intCast(c.clang_Cursor_getNumArguments(cursor));
        for (0..n) |i| {
            var ag = c.clang_Cursor_getArgument(cursor, @intCast(i));
            // std.log.info("pname = {s}", .{c.clang_getCString(c.clang_getCursorDisplayName(ag))});
            var agt = c.clang_getCursorType(ag);
            var arg_type = resolveType(self.allocator, self, agt);
            f.addParam(.{
                .name = c.clang_getCString(c.clang_getCursorDisplayName(ag)),
                .type = arg_type,
            });
        }

        self.addFunction(f);

        return c.CXChildVisit_Continue;
    }

    fn methodHandler(self: *Self, cursor: c.CXCursor, parent: c.CXCursor, isClass: bool) c.CXChildVisitResult {
        std.debug.assert(cursor.kind == c.CXCursor_ObjCClassMethodDecl or cursor.kind == c.CXCursor_ObjCInstanceMethodDecl);
        _ = parent;

        var name = c.clang_getCString(c.clang_getCursorDisplayName(cursor));

        // c.clang_result
        var cursor_return_type = c.clang_getCursorResultType(cursor);
        var return_type = resolveType(self.allocator, self, cursor_return_type);
        var method = Container.Method.init(self.allocator, name, !isClass, return_type);

        var n: usize = @intCast(c.clang_Cursor_getNumArguments(cursor));
        for (0..n) |i| {
            var argument_cursor = c.clang_Cursor_getArgument(cursor, @intCast(i));
            var argument_name = c.clang_getCString(c.clang_getCursorDisplayName(argument_cursor));
            var argument_type = resolveType(self.allocator, self, c.clang_getCursorType(argument_cursor));
            method.addParam(.{
                .name = argument_name,
                .type = argument_type,
            });
        }

        self.addMethod(method);

        return c.CXChildVisit_Continue;
    }

    fn superClassHandler(self: *Self, cursor: c.CXCursor, parent: c.CXCursor) c.CXChildVisitResult {
        std.debug.assert(cursor.kind == c.CXCursor_ObjCSuperClassRef);
        _ = parent;

        var name = c.clang_getCString(c.clang_getCursorDisplayName(cursor));
        self.setSuperClass(name);

        return c.CXChildVisit_Continue;
    }

    fn protocolRefHandler(self: *Self, cursor: c.CXCursor, parent: c.CXCursor) c.CXChildVisitResult {
        std.debug.assert(cursor.kind == c.CXCursor_ObjCProtocolRef);
        _ = parent;

        var name = c.clang_getCString(c.clang_getCursorDisplayName(cursor));

        if (std.mem.eql(u8, sliceFromCString(name), "entry.m")) {
            return c.CXChildVisit_Continue;
        }

        //var ctx_name: []const u8 = switch (self.container_context) {
        //    .protocol => |str| str,
        //    .interface => |str| str,
        //    .none => "none!",
        //};

        //std.log.info("PR: {s}<{s}>", .{ ctx_name, name });
        // var name = c.clang_getCString(c.clang_getCursorDisplayName(cursor));
        self.addConformingProtocol(name);

        return c.CXChildVisit_Continue;
    }

    fn container_visitor(cursor: c.CXCursor, parent: c.CXCursor, data: c.CXClientData) callconv(.C) c.CXChildVisitResult {
        var self: *Registry = @ptrCast(@alignCast(data));

        return switch (cursor.kind) {
            c.CXCursor_FunctionDecl => self.functionHandler(cursor, parent),
            c.CXCursor_ObjCClassMethodDecl => self.methodHandler(cursor, parent, true),
            c.CXCursor_ObjCInstanceMethodDecl => self.methodHandler(cursor, parent, false),
            c.CXCursor_ObjCProtocolRef => self.protocolRefHandler(cursor, parent),
            c.CXCursor_ObjCSuperClassRef => self.superClassHandler(cursor, parent),
            //else => blk: {
            //    var name = c.clang_getCString(c.clang_getCursorDisplayName(cursor));
            //    var kind = c.clang_getCString(c.clang_getCursorKindSpelling(cursor.kind));
            //    println("ELSE:{s} [{s}]", .{ name, kind });

            //    break :blk c.CXChildVisit_Continue;
            //},
            else => c.CXChildVisit_Continue,
        };
    }

    fn main_visitor(cursor: c.CXCursor, parent: c.CXCursor, data: c.CXClientData) callconv(.C) c.CXChildVisitResult {
        var self: *Registry = @ptrCast(@alignCast(data));

        return switch (cursor.kind) {
            c.CXCursor_ObjCProtocolDecl => self.protocolHandler(cursor, parent),
            c.CXCursor_ObjCInterfaceDecl => self.interfaceHandler(cursor, parent),
            c.CXCursor_ObjCCategoryDecl => self.interfaceHandler(cursor, parent),
            c.CXCursor_FunctionDecl => self.functionHandler(cursor, parent),
            //else => blk: {
            //    var name = c.clang_getCString(c.clang_getCursorDisplayName(cursor));
            //    var kind = c.clang_getCString(c.clang_getCursorKindSpelling(cursor.kind));
            //    println("MAIN_ELSE:{s} [{s}]", .{ name, kind });

            //    break :blk c.CXChildVisit_Continue;
            //},

            else => c.CXChildVisit_Continue,
        };
    }

    pub fn print(self: *Self) void {
        {
            println("PROTOCOLS:", .{});
            var it = self.protocols.iterator();
            while (it.next()) |e| {
                var p = e.value_ptr;
                println("   Protocol: '{s}'", .{p.name});
                if (p.super_class) |super_class_name| {
                    println("       SUPER: {s}", .{super_class_name});
                }
                for (0..p.num_protocols) |i| {
                    println("       CONFORMING: {s}", .{p.protocols[i]});
                }
                for (p.methods.items) |m| {
                    m.write(std.io.getStdOut().writer()) catch {
                        std.debug.panic("print", .{});
                    };

                    for (m.params.items) |param| {
                        common.print("({s}: ", .{param.name});
                        param.type.print(std.io.getStdOut().writer()) catch {
                            std.debug.panic("print", .{});
                        };
                        common.print(")", .{});
                    }

                    println("", .{});
                }
            }
        }
        {
            println("INTERFACES:", .{});
            var it = self.interfaces.iterator();
            while (it.next()) |e| {
                var p = e.value_ptr;
                println("   Interface: '{s}'", .{p.name});
                if (p.super_class) |super_class_name| {
                    println("       SUPER: {s}", .{super_class_name});
                }
                for (0..p.num_protocols) |i| {
                    println("       CONFORMING: {s}", .{p.protocols[i]});
                }

                for (p.methods.items) |m| {
                    //common.print("       method: name: {s}, return_type: ", .{m.name});
                    m.write(std.io.getStdOut().writer()) catch {
                        std.debug.panic("print", .{});
                    };
                    println("", .{});
                }
            }
        }
        {
            println("ENUMS:", .{});
            var it = self.enums.iterator();
            while (it.next()) |e| {
                var p = e.value_ptr;
                common.print("   Enum: '{s}'", .{p.name});
                p.type.print(std.io.getStdOut().writer()) catch {
                    std.debug.panic("print", .{});
                };
                println("", .{});
                for (p.values.items) |val| {
                    println("       {s} = {} ({})", .{ val.name, val.value, val.ivalue });
                }
            }
        }
        {
            println("RECORDS:", .{});
            var it = self.records.iterator();
            while (it.next()) |e| {
                var rec = e.value_ptr;
                println("   Record: '{s}'", .{rec.name});

                for (rec.fields.items) |field| {
                    common.print("       Field: {s} -- ", .{field.name});
                    field.type.print(std.io.getStdOut().writer()) catch {
                        std.debug.panic("print", .{});
                    };
                    println("", .{});
                }
            }
        }
        {
            println("FUNCTIONS:", .{});
            var it = self.functions.iterator();
            while (it.next()) |e| {
                var f = e.value_ptr;
                println("   Function: {s}", .{f.name});
                common.print("       RT: ", .{});
                f.return_type.print(std.io.getStdOut().writer()) catch {
                    std.debug.panic("print", .{});
                };
                println("", .{});

                for (f.params.items) |param| {
                    common.print("       PARAM: {s}: ", .{param.name});
                    param.type.print(std.io.getStdOut().writer()) catch {
                        std.debug.panic("print", .{});
                    };
                    println("", .{});
                }
            }
        }
    }
};
