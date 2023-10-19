const std = @import("std");
const gen = @import("out.zig");
const b = @import("block.zig");

extern fn NSLog(fmt: *gen.NSString, ...) void;

fn f(s: *gen.NSString, stop: *bool) void {
    _ = stop;
    _ = s;

    std.log.info("does it work?", .{});
}

const S = struct {
    count: usize = 100,

    pub fn f(self: *S, s: *gen.NSString, stop: *bool) void {
        _ = stop;
        _ = s;
        std.log.info("count = {}", .{self.count});
    }
};

pub fn main() !void {
    std.log.info("Hello!", .{});
    var s = gen.NSString.stringWithUTF8String("hello%@");
    defer s.release();

    var s2 = gen.NSString.stringWithUTF8String(", world!");
    defer s2.release();

    var dev = gen.MTLCreateSystemDefaultDevice();

    if (dev == null) {
        std.log.info("Device is null!!!", .{});
    }
    var col = gen.MTLClearColorMake(1, 0, 0, 1);
    _ = col;

    NSLog(s, s2);

    // var bl = b.BlockLiteral2(void, *gen.NSString, *bool).init(&f);

    var bl = b.BlockLiteral2(void, *gen.NSString, *bool).init(&f);

    var counter = S{};
    var bldata = b.BlockLiteralUserData2(void, *gen.NSString, *bool, S).init(&S.f, &counter);

    // var bl2 = b.BlockLiteralUserData2(void, *gen.NSString, *bool, void).init(&S.f, void);

    //
    // var bl2 = b.create_block_literal_2(void, *gen.NSString, *bool, &f);
    // _ = bl2;
    //
    s.enumerateLinesUsingBlock(@ptrCast(&bl));
    s.enumerateLinesUsingBlock(@ptrCast(&bldata));
}
