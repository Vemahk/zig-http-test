const std = @import("std");
const Allocator = std.mem.Allocator;
const AtomicBool = std.atomic.Value(bool);

const zap = @import("zap");
const Listener = zap.HttpListener;
const ListenerSettings = zap.HttpListenerSettings;
const Err = zap.EndpointListenerError;
const Request = zap.Request;
const RequestFn = zap.HttpRequestFn;

const Endpoint = @import("endpoint.zig");

const Router = @import("path.zig").Paths(Endpoint);

//Singleton? I hardly know 'er!
var has_init: AtomicBool = AtomicBool.init(false);
var allocator: Allocator = undefined;
var router: Router = undefined;
var not_found_handler: RequestFn = defaultNotFound;

pub fn init(a: std.mem.Allocator, not_found: ?RequestFn) !void {
    if (has_init.swap(true, .acq_rel))
        return error.SingletonReinit;

    allocator = a;
    router = Router.init(a);
    if (not_found) |alt_not_found|
        not_found_handler = alt_not_found;
}

pub fn deinit() void {
    router.deinit();
}

pub fn add(path: []const u8, endpoint: Endpoint) !void {
    try router.add(path, endpoint);
}

pub fn buildStaticFileRoutes(comptime public_folder: []const u8) !void {
    const getter = Endpoint.fileGetter(public_folder);
    const cwd = std.fs.cwd();

    var dirs = std.ArrayList([]const u8).init(allocator);
    defer dirs.deinit();

    {
        const pf_copy = try allocator.dupe(u8, "/");
        errdefer allocator.free(pf_copy);
        try dirs.append(pf_copy);
    }

    while (dirs.items.len > 0) {
        const subdirpath = dirs.pop();
        defer allocator.free(subdirpath);
        const realpath = try std.fs.path.join(allocator, &.{ public_folder, subdirpath });
        defer allocator.free(realpath);
        var dir = try cwd.openDir(realpath, .{ .iterate = true });
        defer dir.close();

        var dir_iter = dir.iterate();
        while (try dir_iter.next()) |n| {
            const kind: std.fs.File.Kind = n.kind;
            switch (kind) {
                .file => {
                    const filepath = try std.fs.path.join(allocator, &.{ subdirpath, n.name });
                    defer allocator.free(filepath);
                    try add(filepath, Endpoint{
                        .get = getter,
                    });
                    std.debug.print("Added static file: {s}\n", .{filepath});
                },
                .directory => {
                    const dirpath = try std.fs.path.join(allocator, &.{ subdirpath, n.name });
                    errdefer allocator.free(dirpath);
                    try dirs.append(dirpath);
                },
                else => {}, //ignored.
            }
        }
    }

    return;
}

var listener: Listener = undefined;
pub fn listen(l: ListenerSettings) !void {
    var ls = l;
    ls.on_request = route;
    listener = Listener.init(ls);
    try listener.listen();
    std.debug.print("Listening on 0.0.0.0:{d}\n", .{listener.settings.port});
}

fn route(r: Request) void {
    if (r.path) |p| {
        if (router.find(p) catch null) |c| {
            const ctx = Endpoint.Context{
                .request = r,
                .allocator = allocator,
                .id = c[1],
            };
            return c[0].onRequest(ctx);
        }
    }

    return not_found_handler(r);
}

fn defaultNotFound(r: Request) void {
    r.setStatus(zap.StatusCode.not_found);
    r.markAsFinished(true);
}
