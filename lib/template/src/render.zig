const std = @import("std");
const HTML = @import("html.zig");

pub const RenderOptions = struct {
    html_encode: bool = true,
};

pub fn renderField(data: anytype, writer: anytype, opts: RenderOptions) !void {
    const T = @TypeOf(data);
    const info: std.builtin.Type = @typeInfo(T);

    switch (info) {
        .Int, .ComptimeInt => try std.fmt.formatInt(data, 10, std.fmt.Case.upper, std.fmt.FormatOptions{}, writer),
        .Float, .ComptimeFloat => @compileError("I hate floats, and so should you."),
        .Pointer => |t| {
            if (t.size == .One) {
                try renderField(data.*, writer, opts);
            } else if (t.size == .Slice and t.child == u8) {
                try renderStr(data, writer, opts.html_encode);
            } else {
                @compileError("Unsupported pointer type for template rendering: " ++ @typeName(T));
            }
        },
        .Array => |t| {
            if (t.child == u8) {
                try renderStr(&data, writer, opts.html_encode);
            } else {
                @compileError("Unsupported array type for template rendering: " ++ @typeName(t.child));
            }
        },
        .Optional => {
            if (data) |d| try renderField(d, writer, opts);
        },
        .Null, .Void => {},
        .Bool => {
            try writer.writeAll(if (data) "true" else "false");
        },
        inline else => @compileError("Unsupported type for template rendering: " ++ @typeName(T)),
    }
}

fn renderStr(str: []const u8, writer: anytype, html_encode: bool) !void {
    if (html_encode) {
        try HTML.encodeAll(str, writer);
    } else {
        try writer.writeAll(str);
    }
}

test "rendering anytype" {
    const expectStr = std.testing.expectEqualStrings;

    const Closure = struct {
        pub fn doTest(expected: []const u8, data: anytype) !void {
            var buf: [1024]u8 = undefined;
            var stream = std.io.fixedBufferStream(&buf);
            try renderField(data, stream.writer(), .{});
            try expectStr(expected, buf[0..stream.pos]);
        }
    };

    try Closure.doTest("42", 42);
    try Closure.doTest("-42", -42);
    try Closure.doTest("42", @as(i32, 42));
    try Closure.doTest("-42", @as(i32, -42));
    try Closure.doTest("42", "42");
    try Closure.doTest("42", @as([]const u8, "42"));
    try Closure.doTest("", {});
    try Closure.doTest("", null);
    try Closure.doTest("42", @as(?i32, 42));
    try Closure.doTest("", @as(?i32, null));
    try Closure.doTest("", @as(?*i32, null));
    try Closure.doTest("42", &42);
    try Closure.doTest("true", true);
    try Closure.doTest("false", false);
    // try Closure.doTest("4.2", 4.2);
    // try Closure.doTest("-4.2", -4.2);
    // try Closure.doTest("4.2", @as(f32, 4.2));
}
