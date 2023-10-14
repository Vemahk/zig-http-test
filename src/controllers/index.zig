const std = @import("std");
const Allocator = std.mem.Allocator;

const zap = @import("zap");
const Request = zap.SimpleRequest;

const HttpMethod = @import("../http.zig").HttpMethod;
const Controllers = @import("../controller.zig");
const Endpoint = Controllers.Endpoint;
const Controller = Controllers.Controller;
const RequestFn = Controllers.RequestFn;

const Template = @import("../template.zig").Template;

const endpoint = Endpoint{
    .path = "/",
    .methodHandler = methodHandler,
};

pub fn getEndpoint() *const Endpoint {
    return &endpoint;
}

fn methodHandler(method: HttpMethod) ?RequestFn {
    return switch (method) {
        .Get => get,
        else => null,
    };
}

const Page = struct {
    title: []const u8,
    content: []const u8,
};
var tmpl: ?Template(Page) = null;
fn get(c: Controller, r: Request) void {
    if (tmpl == null) {
        tmpl = Template(Page).init(c.allocator, @embedFile("../templates/layout.html")) catch {
            r.setStatus(zap.StatusCode.internal_server_error);
            std.log.err("Failed to generate Template({s})\n", .{@typeName(Page)});
            return;
        };
    }
    c.renderBody(Page, Page{ .title = "Finally!", .content = "<h1>Progress!</h1>" }, tmpl.?, r);
}
