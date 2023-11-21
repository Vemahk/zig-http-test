const std = @import("std");
const Allocator = std.mem.Allocator;

const zap = @import("zap");
pub const Request = zap.SimpleRequest;

const mustache = @import("mustache");
const HttpMethod = @import("http.zig").HttpMethod;
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
        const r = ctx.request;
        if (HttpMethod.fromStr(r.method)) |m| {
            if (self.methodHandler(m)) |f| {
                return f(ctx) catch ctx.exit(.internal_server_error);
            } else {
                return ctx.exit(.method_not_allowed);
            }
        } else {
            std.log.warn("unknown method: {?s}\n", .{r.method});
            return ctx.exit(.bad_request);
        }
    }

    inline fn methodHandler(self: Self, method: HttpMethod) ?RequestFn {
        return switch (method) {
            .Get => self.get,
            .Post => self.post,
            .Put => self.put,
            .Delete => self.delete,
            .Patch => self.patch,
        };
    }
};
