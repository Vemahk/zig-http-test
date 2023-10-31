const std = @import("std");

pub fn encode(c: u21) ?[]const u8 {
    return switch (c) {
        '&' => "&amp;",
        '<' => "&lt;",
        '>' => "&gt;",
        '"' => "&quot;",
        '\'' => "&#x27;",
        '/' => "&#x2F;",
        else => null,
    };
}

pub fn encodeAll(str: []const u8, writer: anytype) !void {
    const view = try std.unicode.Utf8View.init(str);
    var iter = view.iterator();

    while (iter.nextCodepointSlice()) |cs| {
        const cp = try std.unicode.utf8Decode(cs);
        if (encode(cp)) |encoded| {
            try writer.writeAll(encoded);
        } else {
            try writer.writeAll(cs);
        }
    }
}

pub fn encodeAllBuf(str: []const u8, out: []u8) ![]u8 {
    var stream = std.io.fixedBufferStream(out);
    const writer = stream.writer();
    try encodeAll(str, writer);
    return out[0..stream.pos];
}

/// The caller is responsible for freeing the returned slice.
pub fn encodeToOwned(str: []const u8, a: std.mem.Allocator) ![]const u8 {
    var arr = std.ArrayList(u8).init(a);
    defer arr.deinit();
    const writer = arr.writer();
    try encodeAll(str, writer);
    return arr.toOwnedSlice();
}

test "then html encodes" {
    const a = std.testing.allocator;
    const input = [_][]const u8{
        "<h1>Hello, World!</h1>",
        "&<>\"'/",
    };
    const output = [_][]const u8{
        "&lt;h1&gt;Hello, World!&lt;&#x2F;h1&gt;",
        "&amp;&lt;&gt;&quot;&#x27;&#x2F;",
    };

    inline for (input, output) |str, expected| {
        const actual = try encodeToOwned(str, a);
        defer a.free(actual);
        try std.testing.expectEqualStrings(expected, actual);
    }
}