const Server = @import("server.zig");
pub fn main() !void {
    var instance = try Server.init();
    defer instance.deinit();
    try instance.run();
}

pub const Controllers = @import("controllers.zig");
pub const Templates = @import("templates.zig");
