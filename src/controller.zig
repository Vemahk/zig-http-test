const std = @import("std");
const Allocator = std.mem.Allocator;

const zap = @import("zap");
pub const Request = zap.SimpleRequest;

const Template = @import("template").Template;
const HttpMethod = @import("http.zig").HttpMethod;

pub const RequestFn = *const fn (self: Controller, r: Request) anyerror!void;

pub const Controller = struct {
    const Self = @This();

    allocator: Allocator,
    endpoint: Endpoint,

    pub fn onRequest(self: Self, r: Request) void {
        if (HttpMethod.fromStr(r.method)) |m| {
            if (self.endpoint.methodHandler(m)) |f| {
                return f(self, r) catch stop(r, .internal_server_error);
            } else {
                return stop(r, .method_not_allowed);
            }
        } else {
            std.log.warn("unknown method: {?s}\n", .{r.method});
            return stop(r, .bad_request);
        }
    }

    pub fn renderBody(self: Self, r: Request, Tmpl: anytype, data: anytype, opts: anytype) !void {
        const T = @TypeOf(data);
        const tmpl: *const Template(T) = try Tmpl.get(self.allocator);
        const buf = try tmpl.renderOwned(data, opts);
        defer buf.deinit();
        try r.setContentType(.HTML);
        try r.sendBody(buf.items);
    }
};

pub const Endpoint = struct {
    path: []const u8 = "",
    get: ?RequestFn = null,
    post: ?RequestFn = null,
    put: ?RequestFn = null,
    delete: ?RequestFn = null,
    patch: ?RequestFn = null,

    pub inline fn methodHandler(self: Endpoint, method: HttpMethod) ?RequestFn {
        return switch (method) {
            .Get => self.get,
            .Post => self.post,
            .Put => self.put,
            .Delete => self.delete,
            .Patch => self.patch,
        };
    }
};

fn stop(r: Request, status: zap.StatusCode) void {
    r.setStatus(status);
    r.markAsFinished(true);
}
