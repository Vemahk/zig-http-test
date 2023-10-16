pub const Data = struct {
    title: []const u8,
    content: []const u8,
};

pub const Template = @import("templater.zig").init(Data, "private/templates/layout.html");
