const std = @import("std");
const zap = @import("zap");
const utils = @import("utils");

const Endpoint = @import("endpoint.zig").Endpoint;

fn notFound(req: zap.SimpleRequest) void {
    req.setStatus(zap.StatusCode.not_found);
    req.sendBody(@embedFile("content/static/404.html")) catch return;
}

const Listener = @import("endpoint-listener.zig");

fn buildEndpoints() !void {
    try Listener.add(@import("controllers/index.zig"));
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{
        .thread_safe = true,
    }){};
    var allocator = gpa.allocator();

    {
        const port = 3000;
        Listener.init(allocator, .{
            .port = port,
            .on_request = notFound,
            .log = true,
            .public_folder = "wwwroot",
        });
        defer Listener.deinit();
        try buildEndpoints();
        try Listener.listen();

        zap.start(.{
            .threads = 2,
            .workers = 2,
        });
    }

    const has_leaked = gpa.detectLeaks();
    if (has_leaked) std.debug.print("Memory leaks detected!\n", .{});
}
