const std = @import("std");
const Allocator = std.mem.Allocator;

const zap = @import("zap");
const Request = zap.SimpleRequest;

const HttpMethod = @import("../http.zig").HttpMethod;
const Controllers = @import("../controller.zig");
const Endpoint = Controllers.Endpoint;
const Controller = Controllers.Controller;
const RequestFn = Controllers.RequestFn;

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

fn get(c: Controller, r: Request) !void {
    const Layout = @import("../templates/layout.zig");
    const tmpl = try Layout.Template.get(c.allocator);
    try c.renderBody(Layout.Data{ .title = "Finally!", .content = "<h1>Progress!</h1>" }, tmpl, r);
}
