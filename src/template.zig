const std = @import("std");
const Allocator = std.mem.Allocator;

const meta = @import("meta.zig");
const HTML = @import("html.zig");

pub fn renderDefaultField(data: anytype, writer: anytype) !void {
    const T = @TypeOf(data);
    const info: std.builtin.Type = @typeInfo(T);

    switch (info) {
        .Int, .ComptimeInt => try std.fmt.formatInt(data, 10, std.fmt.Case.upper, std.fmt.FormatOptions{}, writer),
        .Float, .ComptimeFloat => @compileError("I hate floats, and so should you."),
        .Pointer => |t| {
            if (t.size == .One) {
                try renderDefaultField(data.*, writer);
            } else if (t.size == .Slice and t.child == u8) {
                try renderStr(data, writer, true);
            } else {
                @compileError("Unsupported pointer type for template rendering: " ++ @typeName(T));
            }
        },
        .Array => |t| {
            if (t.child == u8) {
                try renderStr(&data, writer, true);
            } else {
                @compileError("Unsupported array type for template rendering: " ++ @typeName(t.child));
            }
        },
        .Optional => {
            if (data) |d| try renderDefaultField(d, writer);
        },
        .Struct => {
            data.template.render(data.data.writer);
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
            var writer = stream.writer();
            try renderDefaultField(data, writer);
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

fn htmlEncode(cp: u21) ?*const []const u8 {
    switch (cp) {
        '&' => return "&amp;",
        '<' => return "&lt;",
        '>' => return "&gt;",
        '"' => return "&quot;",
        '\'' => return "&#x27;",
        '/' => return "&#x2F;",
        else => return null,
    }
}

pub fn Template(comptime T: type) type {
    return struct {
        const Self = @This();

        allocator: Allocator,
        html: [:0]const u8,
        markers: []const FieldMarker,

        const fields = meta.fieldNames(T);

        pub fn init(a: Allocator, html_template: []const u8) !Self {
            var html_copy = try a.allocSentinel(u8, html_template.len, 0);
            errdefer a.free(html_copy);
            @memcpy(html_copy, html_template);

            const logger = std.log.scoped(.template_init);
            var marker_list = std.ArrayList(FieldMarker).init(a);
            defer marker_list.deinit();

            var fields_used = [_]bool{false} ** fields.len;

            var tokenizer = Tokenizer.init(html_copy);
            while (tokenizer.next()) |marker| {
                const index: ?usize = blk: {
                    for (fields, 0..) |field, i| {
                        if (std.mem.eql(u8, field, marker.name))
                            break :blk i;
                    }

                    break :blk null;
                };

                if (index) |i| {
                    fields_used[i] = true;
                    try marker_list.append(marker);
                } else {
                    logger.warn("Detected unknown field in template ({s}): '{s}'", .{ @typeName(T), marker.name });
                }
            }

            for (fields_used, 0..) |b, i| {
                if (!b) {
                    logger.warn("Field '{s}' not used in template for {s}", .{ fields[i], @typeName(T) });
                }
            }

            return Self{
                .allocator = a,
                .html = html_copy,
                .markers = try marker_list.toOwnedSlice(),
            };
        }

        pub fn initFromFile(a: Allocator, file: []const u8) !Self {
            const max_size = 1 << 20; // 1MB, why not.
            var f: std.fs.File = try std.fs.cwd().openFile(file, .{});
            defer f.close();
            const file_text = try f.readToEndAllocOptions(a, max_size, null, @alignOf(u8), 0);
            defer a.free(file_text);

            return try init(a, file_text);
        }

        pub fn deinit(self: Self) void {
            self.allocator.free(self.markers);
            self.allocator.free(self.html);
        }

        pub fn render(self: Self, data: T, writer: anytype) !void {
            const info = @typeInfo(T);
            const field = info.Struct.fields;

            var start: usize = 0;
            for (self.markers) |m| {
                try writer.writeAll(self.html[start..m.start]);
                start = m.start + m.len;

                inline for (field) |f| {
                    if (std.mem.eql(u8, f.name, m.name)) {
                        try renderDefaultField(@field(data, f.name), writer);
                    }
                }
            }

            if (start < self.html.len) {
                try writer.writeAll(self.html[start..]);
            }
        }
    };
}

test "building template works." {
    const a = std.testing.allocator;
    const Test = struct {
        pub fn perform(data: anytype, input_html: [:0]const u8, expected: []const u8) !void {
            const T = @TypeOf(data);
            const Templ = Template(T);
            var tmp = try Templ.init(a, input_html);
            defer tmp.deinit();

            var buf = std.ArrayList(u8).init(a);
            defer buf.deinit();
            var writer = buf.writer();
            try tmp.render(data, writer);
            try std.testing.expectEqualStrings(expected, buf.items);
        }
    };

    try Test.perform(.{ .val = 50 }, "<h1>.{val}</h1>", "<h1>50</h1>");
    try Test.perform(.{ .greeting = "hello", .person = "world" }, "<html>.{greeting}, .{person}!</html>", "<html>hello, world!</html>");
    try Test.perform(.{ .raw_html = "<h1>High-Class Information Below...</h1>" }, "<html>.{raw_html}</html>", "<html>&lt;h1&gt;High-Class Information Below...&lt;&#x2F;h1&gt;</html>");
}

test "building template from file" {
    const a = std.testing.allocator;
    const cwd = std.fs.cwd();
    const Data = struct {
        num: usize,
    };
    const content = "<h1>.{num}</h1>";
    const file_path = "test.txt";

    {
        const f = try cwd.createFile(file_path, .{});
        defer f.close();
        try f.writeAll(content);
    }

    const tmpl = try Template(Data).initFromFile(a, file_path);
    defer tmpl.deinit();

    var buf = std.ArrayList(u8).init(a);
    defer buf.deinit();
    const writer = buf.writer();
    try tmpl.render(.{ .num = 50 }, writer);

    const expectStr = std.testing.expectEqualStrings;
    try expectStr("<h1>50</h1>", buf.items);
}

const ZTokenizer = std.zig.Tokenizer;
const ZToken = std.zig.Token;
const FieldMarkerTags = [_]ZToken.Tag{ .period, .l_brace, .identifier, .r_brace };

const FieldMarker = struct {
    const Self = @This();

    name: []const u8,
    start: usize,
    len: usize,
};

const Tokenizer = struct {
    const Self = @This();

    html: [:0]const u8,
    index: usize = 0,

    pub fn init(html: [:0]const u8) Self {
        return Self{
            .html = html,
        };
    }

    pub fn next(self: *Self) ?FieldMarker {
        while (self.index < self.html.len) {
            const start = self.index;
            var zt = ZTokenizer.init(self.html[start..]); // I guess this does mean my template syntax is subject to the same change that zig is.

            var ztokens: [FieldMarkerTags.len]ZToken = undefined;
            var i: usize = 0;

            while (i < FieldMarkerTags.len) {
                const ztoken = zt.next();
                if (ztoken.tag == .eof) {
                    self.index = self.html.len;
                    break;
                }

                if (ztoken.tag == FieldMarkerTags[i]) {
                    ztokens[i] = ztoken;
                    i += 1;
                    if (i >= FieldMarkerTags.len) {
                        const marker_start = start + ztokens[0].loc.start;
                        const marker_end = start + ztoken.loc.end;
                        const name_ident = ztokens[2];
                        var name_start = start + name_ident.loc.start;
                        var name_end = start + name_ident.loc.end;
                        if (name_end >= name_start + 3) {
                            if (self.html[name_start] == '@' and self.html[name_start + 1] == '"' and self.html[name_end - 1] == '"') {
                                name_start += 2;
                                name_end -= 1;
                            }
                        }

                        self.index = marker_end;
                        if (name_end <= name_start) break;

                        return .{
                            .name = self.html[name_start..name_end],
                            .start = marker_start,
                            .len = marker_end - marker_start,
                        };
                    }
                } else {
                    if (i > 0 and ztoken.tag == FieldMarkerTags[0]) {
                        self.index = start + ztoken.loc.start;
                        ztokens[0] = ztoken;
                        i = 1;
                        continue;
                    } else {
                        self.index = start + ztoken.loc.end;
                        break;
                    }
                }
            }
        }

        return null;
    }
};

test "tokenzier" {
    const expect = std.testing.expect;
    const expectStr = std.testing.expectEqualStrings;

    // 1 - happy path; one tag
    var html: [:0]const u8 = "<html>.{field_nm}</html>";
    var tokenizer = Tokenizer.init(html);

    var marker = tokenizer.next() orelse unreachable;
    try expectStr(".{field_nm}", html[marker.start .. marker.start + marker.len]);
    try expectStr("field_nm", marker.name);
    try expectStr("</html>", html[marker.start + marker.len ..]);
    try expectStr("<html>", html[0..marker.start]);

    try expect(tokenizer.next() == null);

    // 2 - empty tag no worky
    html = "<html>.{}</html>";
    tokenizer = Tokenizer.init(html);
    try expect(tokenizer.next() == null);

    // 3 - tag with reserved zig keyword
    html = "<html>.{fn}</html>";
    tokenizer = Tokenizer.init(html);
    try expect(tokenizer.next() == null);

    // 4 - tag no html
    html = ".{field_nm}";
    tokenizer = Tokenizer.init(html);
    marker = tokenizer.next() orelse unreachable;
    try expectStr(".{field_nm}", html[marker.start .. marker.start + marker.len]);
    try expectStr("field_nm", marker.name);
    try expectStr("", html[marker.start + marker.len ..]);
    try expectStr("", html[0..marker.start]);

    try expect(tokenizer.next() == null);

    // 6 - multiple tags
    html = "<html>.{field_nm}</html>.{field_nm}";
    tokenizer = Tokenizer.init(html);
    marker = tokenizer.next() orelse unreachable;
    try expectStr(".{field_nm}", html[marker.start .. marker.start + marker.len]);
    try expectStr("field_nm", marker.name);
    try expectStr("</html>.{field_nm}", html[marker.start + marker.len ..]);
    try expectStr("<html>", html[0..marker.start]);

    marker = tokenizer.next() orelse unreachable;
    try expectStr(".{field_nm}", html[marker.start .. marker.start + marker.len]);
    try expectStr("field_nm", marker.name);
    try expectStr("", html[marker.start + marker.len ..]);
    try expectStr("<html>.{field_nm}</html>", html[0..marker.start]);

    try expect(tokenizer.next() == null);

    // 7 - invalid tag
    html = "<html>.{{field_nm}}</html>";
    tokenizer = Tokenizer.init(html);
    try expect(tokenizer.next() == null);

    // 8 - incomplete tag
    html = "<html>.{field_nm</html>";
    tokenizer = Tokenizer.init(html);
    try expect(tokenizer.next() == null);

    // 9 - funky nested tag
    html = "<html>.{.{field_nm}}</html>";
    tokenizer = Tokenizer.init(html);
    marker = tokenizer.next() orelse unreachable;
    try expectStr(".{field_nm}", html[marker.start .. marker.start + marker.len]);
    try expectStr("field_nm", marker.name);
    try expectStr("}</html>", html[marker.start + marker.len ..]);
    try expectStr("<html>.{", html[0..marker.start]);
    try expect(tokenizer.next() == null);

    // 10 - string identifiers
    html = "<html>.{@\"420\"}</html>";
    tokenizer = Tokenizer.init(html);
    marker = tokenizer.next() orelse unreachable;
    try expectStr(".{@\"420\"}", html[marker.start .. marker.start + marker.len]);
    try expectStr("420", marker.name);
    try expectStr("</html>", html[marker.start + marker.len ..]);
    try expectStr("<html>", html[0..marker.start]);
    try expect(tokenizer.next() == null);

    // 11 - identifiers cannot be blank
    html = "<html>.{@\"\"}</html>";
    tokenizer = Tokenizer.init(html);
    try expect(tokenizer.next() == null);

    // 12 - some bastard token from hell.
    html = "<html>.{@\".{field_nm}\"}</html>";
    tokenizer = Tokenizer.init(html);
    marker = tokenizer.next() orelse unreachable;
    try expectStr(".{@\".{field_nm}\"}", html[marker.start .. marker.start + marker.len]);
    try expectStr(".{field_nm}", marker.name);
    try expectStr("</html>", html[marker.start + marker.len ..]);
    try expectStr("<html>", html[0..marker.start]);
    try expect(tokenizer.next() == null);
}

test "odd zig field names" {
    const expectStr = std.testing.expectEqualStrings;
    const Weird = struct {
        // I like this better than Rust's approach for accessing tuple elements, honestly.
        // ... but it's still strange.
        @" ": usize,
    };
    try expectStr(@typeInfo(Weird).Struct.fields[0].name, " ");
}
