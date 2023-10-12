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

allocator: Allocator,

pub fn init(a: Allocator) !Server {
    return .{
        .allocator = a,
    };
}

pub fn deinit(self: *Server) void {
    _ = self;
}

pub fn run(self: Server) !void {
    const port = 3000;
    try Listener.init(self.allocator, notFound);
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
    req.sendBody(@embedFile("content/static/404.html")) catch return;
}

fn buildEndpoints() !void {
    const controllers = [_]type{
        @import("controllers/index.zig"),
    };

    inline for (controllers) |c| {
        try Listener.add(c.getEndpoint());
    }
}
