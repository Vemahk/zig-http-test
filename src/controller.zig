const std = @import("std");
const zap = @import("zap");
const Allocator = std.mem.Allocator;
const Request = zap.SimpleRequest;
const HttpMethod = @import("http.zig").HttpMethod;

pub const RequestFn = *const fn (self: Controller, r: Request) void;

pub const Controller = struct {
    const Self = @This();

    allocator: Allocator,
    endpoint: *const Endpoint,

    pub fn onRequest(self: Self, r: Request) void {
        if (HttpMethod.fromStr(r.method)) |m| {
            if (self.endpoint.methodHandler(m)) |f| {
                f(self, r);
            } else {
                return stop(r, .method_not_allowed);
            }
        } else {
            std.debug.print("unknown method: {?s}\n", .{r.method});
            return stop(r, .bad_request);
        }
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
