const std = @import("std");
const layout_fmt = @embedFile("content/layout.html");

const Allocator = std.mem.Allocator;
const Buffer = std.ArrayList(u8);
const Request = @import("zap").SimpleRequest;

pub fn renderToRequest(r: Request, a: Allocator, data: anytype) !void {
    var buffer = Buffer.init(a);
    defer buffer.deinit();
    var writer = buffer.writer();
    try std.fmt.format(writer, layout_fmt, data);
    try r.sendBody(buffer.items);
}
