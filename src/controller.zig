const std = @import("std");
const Allocator = std.mem.Allocator;

const zap = @import("zap");
const Request = zap.SimpleRequest;

const HttpMethod = @import("http.zig").HttpMethod;

const Template = @import("template.zig").Template;

pub const RequestFn = *const fn (self: Controller, r: Request) anyerror!void;

pub const Controller = struct {
    const Self = @This();

    allocator: Allocator,
    endpoint: *const Endpoint,

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

    pub fn renderBody(self: Self, comptime T: type, data: T, template: Template(T), r: Request) !void {
        var buf = std.ArrayList(u8).init(self.allocator);
        defer buf.deinit();
        var writer = buf.writer();
        try template.render(data, writer);
        try r.sendBody(buf.items);
    }
};

pub const Endpoint = struct {
    path: []const u8,
    methodHandler: *const fn (method: HttpMethod) ?RequestFn,
};

fn stop(r: Request, status: zap.StatusCode) void {
    r.setStatus(status);
    r.markAsFinished(true);
}
