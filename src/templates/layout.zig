const std = @import("std");

const Template = @import("../template.zig").Template;

const Path = "private/templates/layout.html";
const Layout = struct {
    title: []const u8,
    content: []const u8,
};

var tmpl: ?Template(Layout) = null;
pub fn get (allocator: std.mem.Allocator) !*const Template(Layout) {
    if (tmpl == null) {
        tmpl = Template(Layout).init(allocator, @embedFile("../templates/layout.html")) catch {
            r.setStatus(zap.StatusCode.internal_server_error);
            std.log.err("Failed to generate Template({s})\n", .{@typeName(Page)});
            return;
        };
    }
}
