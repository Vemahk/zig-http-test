const std = @import("std");
const Allocator = std.mem.Allocator;

const Server = @This();

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{
        .thread_safe = true,
    }){};

    {
        var instance = try Server.init(gpa.allocator());
        defer instance.deinit();
        try instance.run();
    }

    const has_leaked = gpa.detectLeaks();
    if (has_leaked) std.debug.print("Memory leaks detected!\n", .{});
}

const zap = @import("zap");
const Listener = @import("endpoint-listener.zig");

var allocator: ?Allocator = null;

pub fn init(a: Allocator) !Server {
    allocator = a;
    return .{};
}

pub fn deinit(self: *Server) void {
    _ = self;
}

pub fn run(self: Server) !void {
    _ = self;
    const port = 3000;
    try Listener.init(allocator.?, notFound);
    defer Listener.deinit();
    try buildEndpoints();
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
    const Layout = @import("templates/layout.zig");
    const tmpl = Layout.Template.get(allocator.?) catch return;
    var buf = std.ArrayList(u8).init(allocator.?);
    defer buf.deinit();
    const writer = buf.writer();
    //TODO: add no-html-encode option.
    tmpl.render(Layout.Data{ .title = "Not Found!", .content = "<h1>The requested content could not be found.</h1>" }, writer) catch return;
    req.sendBody(buf.items) catch return;
}

fn buildEndpoints() !void {
    const controllers = [_]type{
        @import("controllers/index.zig"),
    };

    inline for (controllers) |c| {
        try Listener.add(c.getEndpoint());
    }
}
