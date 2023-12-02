const C = @import("_common.zig");

pub const path = "/";

pub fn get(ctx: C.HttpContext) !void {
    const time_path = C.Endpoints.Time.path;
    const content = "The current time is: <div hx-get=\"" ++ time_path ++ "\" hx-trigger=\"load\" hx-swap=\"outerHTML\"></div>";

    const Layout = C.Templates.Layout;
    const data = Layout.Data{ .title = "Finally!", .content = content };
    try ctx.renderBody(Layout, data);
}
