const std = @import("std");
const zap = @import("zap");
const utils = @import("utils");
const pages = @import("pages.zig");

const Router = std.StringHashMap(zap.SimpleHttpRequestFn);
var routes: Router = undefined;

fn dispatch_routes(r: zap.SimpleRequest) void {
    if (r.path) |path| {
        if (routes.get(path)) |func| {
            func(r);
            return;
        }
    }

    r.sendBody(pages.not_found) catch return;
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var allocator = arena.allocator();

    const cwd = try std.fs.cwd().realpathAlloc(allocator, ".");
    std.debug.print("cwd: {s}\n", .{cwd});

    const port = 3000;
    var listener = zap.SimpleHttpListener.init(.{
        .port = port,
        .on_request = dispatch_routes,
        .log = true,
    });
    try listener.listen();

    std.debug.print("Listening on http://127.0.0.1:{d}\n", .{port});

    zap.start(.{
        .threads = 2,
        .workers = 2,
    });
}
