const std = @import("std");
const Allocator = std.mem.Allocator;

const zap = @import("zap");
const Request = zap.SimpleRequest;

const TemplateNS = @import("template.zig");
const Template = TemplateNS.Template;
const RenderOptions = TemplateNS.RenderOptions;

const HttpMethod = @import("http.zig").HttpMethod;

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

    pub fn renderBody(self: Self, r: Request, Tmpl: anytype, data: anytype, opts: RenderOptions) !void {
        const T = @TypeOf(data);
        const tmpl: *const Template(T) = try Tmpl.get(self.allocator);
        const buf = try tmpl.renderOwned(data, opts);
        defer buf.deinit();
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
