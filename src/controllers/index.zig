const C = @import("../controller.zig");

pub const endpoint = C.Endpoint{
    .path = "/",
    .get = get,
};

fn get(c: C.Controller, r: C.Request) !void {
    const time_path = @import("root").Controllers.Time.endpoint.path;
    const content = "The current time is: <div hx-get=\"" ++ time_path ++ "\" hx-trigger=\"load\" hx-swap=\"outerHTML\"></div>";
    const Layout = @import("root").Templates.Layout;
    const data = Layout.Data{ .title = "Finally!", .content = content };
    try c.renderBody(r, Layout, data, .{ .html_encode = false });
}
