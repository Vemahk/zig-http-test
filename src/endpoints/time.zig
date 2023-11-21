const C = @import("_common.zig");
const epoch_now = @import("std").time.timestamp;

pub const path = "/time";

pub fn get(ctx: C.HttpContext) !void {
    const Layout = C.Templates.Time;
    const data = Layout.Data{ .timestamp = epoch_now() };
    try ctx.renderBody(Layout, data);
}
