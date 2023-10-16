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
    
    const tmpl = try @import("../templates/layout.zig").get(c.allocator);
    c.renderBody(Page, Page{ .title = "Finally!", .content = "<h1>Progress!</h1>" }, tmpl.?, r);
}
