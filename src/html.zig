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
        var cp = try std.unicode.utf8Decode(cs);
        if (encode(cp)) |encoded| {
            try writer.writeAll(encoded);
        } else {
            try writer.writeAll(cs);
        }
    }
}

pub fn encodeAllBuf(str: []const u8, out: []u8) ![]u8 {
    var stream = std.io.fixedBufferStream(out);
    var writer = stream.writer();
    try encodeAll(str, writer);
    return out[0..stream.pos];
}

test "then html encodes" {
    var buffer: [1024]u8 = undefined;
    const input = [_][]const u8{
        "<h1>Hello, World!</h1>",
        "&<>\"'/",
    };
    const output = [_][]const u8{
        "&lt;h1&gt;Hello, World!&lt;&#x2F;h1&gt;",
        "&amp;&lt;&gt;&quot;&#x27;&#x2F;",
    };

    inline for (input, output) |str, expected| {
        const actual = try encodeAllBuf(str, &buffer);
        try std.testing.expectEqualStrings(expected, actual);
    }
}
