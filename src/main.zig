pub const Endpoints = @import("endpoints/_list.zig");
pub const Templates = @import("server/templates.zig");
pub const Endpoint = @import("server/endpoint.zig");

const std = @import("std");
const builtin = @import("builtin");
const std_options = std.Options{};

const log = std.log.scoped(.main);

var alloc: std.mem.Allocator = undefined;
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
    defer _ = gpa.deinit();
    alloc = gpa.allocator();

    {
        const cwd = try std.fs.cwd().realpathAlloc(alloc, ".");
        defer alloc.free(cwd);
        log.debug("cwd: {s}\n", .{cwd});
    }

    {
        var self = std.process.args();
        var i: usize = 0;
        while (self.next()) |arg| {
            log.debug("Argument {d}: {s}\n", .{ i, arg });
            i += 1;
        }
    }

    try run();
}

const zap = @import("zap");

fn run() !void {
    const Listener = @import("server/listener.zig");

    const port = 3000;

    // Not sure what this does to be honest.
    try Listener.init(alloc, notFound);
    defer Listener.deinit();

    // Register all our endpoints.
    const info: std.builtin.Type = @typeInfo(Endpoints);
    const decls = info.Struct.decls;
    inline for (decls) |decl| {
        const E = @field(Endpoints, decl.name);
        try Listener.add(E.path, Endpoint{
            .get = if (@hasDecl(E, "get")) E.get else null,
            .post = if (@hasDecl(E, "post")) E.post else null,
            .put = if (@hasDecl(E, "put")) E.put else null,
            .delete = if (@hasDecl(E, "delete")) E.delete else null,
            .patch = if (@hasDecl(E, "patch")) E.patch else null,
        });
    }

    try Listener.buildStaticFileRoutes("share/static");

    try Listener.listen(.{
        .port = port,
        .on_request = null, // required here, but overriden by Listener.
        .log = true,
    });

    zap.start(.{
        .threads = 2,
        .workers = 2,
    });
}

fn notFound(req: zap.Request) void {
    req.setStatus(zap.StatusCode.not_found);

    const Layout = Templates.Layout;
    const data = Layout.Data{ .title = "Not Found!", .content = "<h1>The requested content could not be found.</h1>" };

    const tmpl = Layout.get(alloc);
    const buf = @import("mustache").allocRender(alloc, tmpl, data) catch return;
    defer alloc.free(buf);

    req.sendBody(buf) catch return;
}

test {
    _ = Templates;
    _ = Endpoints.Story;
}
