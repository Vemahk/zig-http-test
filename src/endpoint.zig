const std = @import("std");
const Allocator = std.mem.Allocator;

const zap = @import("zap");
pub const Request = zap.SimpleRequest;

const mustache = @import("mustache");
const ResourceId = @import("path.zig").ResourceId;
const Templater = @import("root").Templates.Templater;

pub const HttpContext = struct {
    const Self = @This();

    allocator: Allocator,
    request: Request,
    id: ResourceId,

    pub fn renderBody(self: Self, comptime templater: Templater, data: templater.Data) !void {
        const tmpl = templater.get(self.allocator);
        const buf = try mustache.allocRender(self.allocator, tmpl, data);
        defer self.allocator.free(buf);
        try self.request.setContentType(.HTML);
        try self.request.sendBody(buf);
    }

    pub fn exit(self: Self, status: zap.StatusCode) void {
        self.request.setStatus(status);
        self.request.markAsFinished(true);
    }
};

pub const RequestFn = *const fn (ctx: HttpContext) anyerror!void;

pub const Endpoint = struct {
    const Self = @This();

    path: []const u8 = "",
    get: ?RequestFn = null,
    post: ?RequestFn = null,
    put: ?RequestFn = null,
    delete: ?RequestFn = null,
    patch: ?RequestFn = null,

    pub fn onRequest(self: Self, ctx: HttpContext) void {
        if (ctx.request.method) |method| {
            if (self.methodHandler(method)) |func| {
                return func(ctx) catch ctx.exit(.internal_server_error);
            } else std.log.warn("unknown method: {?s}\n", .{method});
        }

        return ctx.exit(.method_not_allowed);
    }

    fn methodHandler(self: Self, method: []const u8) ?RequestFn {
        if (std.mem.eql(u8, method, "GET")) return self.get;
        if (std.mem.eql(u8, method, "POST")) return self.post;
        if (std.mem.eql(u8, method, "PUT")) return self.put;
        if (std.mem.eql(u8, method, "DELETE")) return self.delete;
        if (std.mem.eql(u8, method, "PATCH")) return self.patch;
        return null;
    }
};
