const C = @import("../controller.zig");
const std = @import("std");

pub const endpoint = C.Endpoint{
    .path = "/time",
    .get = get,
};

fn get(c: C.Controller, r: C.Request) !void {
    const Layout = @import("root").Templates.Time;
    const data = Layout.Data{ .timestamp = std.time.timestamp() };
    try c.renderBody(r, Layout, data);
}
