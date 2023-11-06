const std = @import("std");
const Allocator = std.mem.Allocator;

const Server = @This();
pub fn main() !void {
    var instance = try Server.init();
    defer instance.deinit();
    try instance.run();
}

pub const Controllers = @import("controllers.zig");
pub const Templates = @import("templates.zig");

test {
    _ = Controllers;
    _ = Templates;
}

var gpa = std.heap.GeneralPurposeAllocator(.{
    .thread_safe = true,
}){};

inline fn alloc() Allocator {
    return gpa.allocator();
}

const zap = @import("zap");
const Listener = @import("endpoint-listener.zig");

fn init() !Server {
    return .{};
}

fn deinit(self: *Server) void {
    _ = self;
    const has_leaked = gpa.detectLeaks();
    if (has_leaked) std.debug.print("Memory leaks detected!\n", .{});
}

fn run(self: Server) !void {
    _ = self;
    const port = 3000;
    try Listener.init(alloc(), notFound);
    defer Listener.deinit();

    const ctrls = @import("root").Controllers;
    const info: std.builtin.Type = @typeInfo(ctrls);
    const decls = info.Struct.decls;
    inline for (decls) |decl| {
        try Listener.add(@field(ctrls, decl.name).endpoint);
    }

    try Listener.listen(.{
        .port = port,
        .on_request = null, // required here, but overriden by Listener.
        .log = true,
        .public_folder = "wwwroot",
    });

    zap.start(.{
        .threads = 2,
        .workers = 2,
    });
}

fn notFound(req: zap.SimpleRequest) void {
    req.setStatus(zap.StatusCode.not_found);

    const Layout = @import("root").Templates.Layout;
    const data = Layout.Data{ .title = "Not Found!", .content = "<h1>The requested content could not be found.</h1>" };

    var a = alloc();
    const tmpl = Layout.get(a);
    const buf = @import("mustache").allocRender(a, tmpl, data) catch return;
    defer buf.deinit();

    req.sendBody(buf.items) catch return;
}
