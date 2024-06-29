const C = @import("_common.zig");

const std = @import("std");
const koino = @import("koino");

pub const path = "/story";

pub fn get(ctx: C.HttpContext) !void {
    const a = ctx.allocator;
    var body = std.ArrayList(u8).init(a);
    defer body.deinit();
    const body_writer = body.writer().any();

    var p = try koino.parser.Parser.init(a, .{});
    defer p.deinit();
    try p.feed(
        \\# Hello, World!
        \\
        \\You're reading markdown!
        \\
        \\Isn't that cool?
    );
    var doc = try p.finish();
    defer doc.deinit();

    try koino.html.print(body_writer, a, .{}, doc);
    std.debug.print("Rendered: {s}\n", .{body.items});

    const Layout = C.Templates.Layout;
    const data = Layout.Data{ .title = "Finally!", .content = body.items };
    try ctx.renderBody(Layout, data);
}

test {
    const a = std.testing.allocator;
    var body = std.ArrayList(u8).init(a);
    defer body.deinit();
    const body_writer = body.writer().any();

    var p = try koino.parser.Parser.init(a, .{});
    defer p.deinit();
    try p.feed(
        \\# Hello, World!
        \\
        \\You're reading markdown!
        \\
        \\Isn't that cool?
    );
    var doc = try p.finish();
    defer doc.deinit();

    try koino.html.print(body_writer, a, .{}, doc);
    std.debug.print("Result: {s}\n", .{body.items});
}
