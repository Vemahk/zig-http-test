pub const Endpoints = @import("endpoints/_list.zig");
pub const Templates = @import("server/templates.zig");
pub const Endpoint = @import("server/endpoint.zig");

const std = @import("std");

var alloc: std.mem.Allocator = undefined;
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
    defer {
        const has_leaked = gpa.detectLeaks();
        if (has_leaked) std.debug.print("Memory leaks detected!\n", .{});
    }

    alloc = gpa.allocator();

    const cwd = try std.fs.cwd().realpathAlloc(alloc, ".");
    defer alloc.free(cwd);
    std.debug.print("cwd: {s}\n", .{cwd});

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
        try Listener.add(Endpoint{
            .path = E.path,
            .get = if (@hasDecl(E, "get")) E.get else null,
            .post = if (@hasDecl(E, "post")) E.post else null,
            .put = if (@hasDecl(E, "put")) E.put else null,
            .delete = if (@hasDecl(E, "delete")) E.delete else null,
            .patch = if (@hasDecl(E, "patch")) E.patch else null,
        });
    }

    // TLS D:
    //const tls = try zap.Tls.init(.{
    //    .public_certificate_file = "~/.local/certs/vemahk.me.crt",
    //    .private_key_file = "~/.local/certs/vemahk.me.key",
    //});
    //defer tls.deinit();

    try Listener.listen(.{
        .port = port,
        .on_request = null, // required here, but overriden by Listener.
        .log = true,
        .public_folder = "share/static",
        //.tls = tls,
    });

    zap.start(.{
        .threads = 2,
        .workers = 2,
    });
}

fn notFound(req: zap.SimpleRequest) void {
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
}
