const std = @import("std");
const Allocator = std.mem.Allocator;

const zap = @import("zap");
const Request = zap.Request;

const mustache = @import("mustache");
const ResourceId = @import("path.zig").ResourceId;
const Templater = @import("root").Templates.Templater;

const Endpoint = @This();
pub const RequestFn = *const fn (ctx: Context) anyerror!void;

get: ?RequestFn = null,
post: ?RequestFn = null,
put: ?RequestFn = null,
delete: ?RequestFn = null,
patch: ?RequestFn = null,

pub fn onRequest(self: Endpoint, ctx: Context) void {
    if (ctx.request.method) |method| {
        if (self.methodHandler(method)) |func| {
            return func(ctx) catch ctx.exit(.internal_server_error);
        } else std.log.warn("unknown method: {?s}\n", .{method});
    }

    return ctx.exit(.method_not_allowed);
}

fn methodHandler(self: Endpoint, method: []const u8) ?RequestFn {
    if (std.mem.eql(u8, method, "GET")) return self.get;
    if (std.mem.eql(u8, method, "POST")) return self.post;
    if (std.mem.eql(u8, method, "PUT")) return self.put;
    if (std.mem.eql(u8, method, "DELETE")) return self.delete;
    if (std.mem.eql(u8, method, "PATCH")) return self.patch;
    return null;
}

pub const Context = struct {
    allocator: Allocator,
    request: Request,
    id: ResourceId,

    pub fn renderBody(self: Context, comptime templater: Templater, data: templater.Data) !void {
        const tmpl = templater.get(self.allocator);
        const buf = try mustache.allocRender(self.allocator, tmpl, data);
        defer self.allocator.free(buf);
        try self.request.setContentType(.HTML);
        try self.request.sendBody(buf);
    }

    pub fn exit(self: Context, status: zap.StatusCode) void {
        self.request.setStatus(status);
        self.request.markAsFinished(true);
    }
};

pub fn fileGetter(comptime dir: []const u8) RequestFn {
    return struct {
        pub fn get(self: Context) anyerror!void {
            const path = self.request.path orelse return error.FileNotFound;
            const file_path = try std.fs.path.join(self.allocator, &.{ dir, path });
            defer self.allocator.free(file_path);

            try self.request.sendFile(path);
        }
    }.get;
}
