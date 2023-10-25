const std = @import("std");
const Allocator = std.mem.Allocator;

const meta = @import("meta.zig");
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

const TmplField = struct {
    range: StrRange,
    ident_range: StrRange,

    pub fn name(a: Allocator, html: []const u8) std.ArrayList(u8) {
        _ = html;
        var buf = std.ArrayList(u8).init(a);
        return buf;
    }
};

pub fn Template(comptime T: type) type {
    return struct {
        const Self = @This();

        allocator: Allocator,
        html: std.ArrayList(u8),
        markers: std.ArrayList(StrRange),

        const fields = meta.fieldNames(T);
        const max_len = blk: {
            var len = 0;
            for(fields) |f| {
                if(f.len > len)
                    len = fields.len;
            }
            break :blk len;
        };

        const FieldTags = [_]Tag{ .period, .l_brace, .identifier, .r_brace };

        pub fn init(a: Allocator, html_template: []const u8) !Self {
            const logger = std.log.scoped(.template_init);
            var marker_list = std.ArrayList(StrRange).init(a);
            defer marker_list.deinit();

            var fields_used = [_]bool{false} ** fields.len;

            //TODO: if zig ever supports comptime allocators, make this comptime-able.
            var extractor = FieldExtractor.init(html_template);
            while (extractor.next()) |tmpl_field| {
                const index: ?usize = blk: {
                    for (fields, 0..) |field, i| {
                        if (std.mem.eql(u8, field, tmpl_field.name().of(html_template)))
                            break :blk i;
                    }

                    break :blk null;
                };

                if (index) |i| {
                    fields_used[i] = true;
                    try marker_list.append();
                } else {
                    logger.warn("Detected unknown field in template ({s}): '{s}'", .{ @typeName(T), tmpl_field.name().of(html_template) });
                }
            }

            for (fields_used, 0..) |b, i| {
                if (!b) {
                    logger.warn("Field '{s}' not used in template for {s}", .{ fields[i], @typeName(T) });
                }
            }

            return Self{
                .allocator = a,
                .html = te,
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
            self.html.deinit();
            self.markers.deinit();
        }

        pub fn render(self: Self, data: T, writer: anytype, opts: RenderOptions) !void {
            const info = @typeInfo(T);
            const field = info.Struct.fields;

            var start: usize = 0;
            for (self.markers) |m| {
                const r = m.marker_range;
                try writer.writeAll(self.html[start..r.start]);
                start = r.end;

                inline for (field) |f| {
                    if (std.mem.eql(u8, f.name, m.name_range.of(self.html))) {
                        try renderField(@field(data, f.name), writer, opts);
                    }
                }
            }

            if (start < self.html.len) {
                try writer.writeAll(self.html[start..]);
            }
        }

        pub fn renderOwned(self: Self, data: T, opts: RenderOptions) !std.ArrayList(u8) {
            var buf = std.ArrayList(u8).init(self.allocator);
            errdefer buf.deinit();
            try self.render(data, buf.writer(), opts);
            return buf;
        }
    };
}

test "building template works." {
    const a = std.testing.allocator;
    const Test = struct {
        pub fn perform(data: anytype, input_html: [:0]const u8, expected: []const u8, opts: RenderOptions) !void {
            const T = @TypeOf(data);
            const Templ = Template(T);
            var tmp = try Templ.init(a, input_html);
            defer tmp.deinit();

            const buf = try tmp.renderOwned(data, opts);
            defer buf.deinit();
            try std.testing.expectEqualStrings(expected, buf.items);
        }
    };

    try Test.perform(.{ .val = 50 }, "<h1>.{val}</h1>", "<h1>50</h1>", .{});
    try Test.perform(.{ .greeting = "hello", .person = "world" }, "<html>.{greeting}, .{person}!</html>", "<html>hello, world!</html>", .{});
    try Test.perform(.{ .raw_html = "<h1>High-Class Information Below...</h1>" }, "<html>.{raw_html}</html>", "<html>&lt;h1&gt;High-Class Information Below...&lt;&#x2F;h1&gt;</html>", .{});
    try Test.perform(.{ .no_encode = "<h1>Bold!</h1>" }, "<html>.{no_encode}</html>", "<html><h1>Bold!</h1></html>", .{ .html_encode = false });
}

test "building template from file" {
    const a = std.testing.allocator;
    const cwd = std.fs.cwd();
    const Data = struct {
        num: usize,
    };
    const content = "<h1>.{num}</h1>";
    const file_path = "test.txt";

    const f = try cwd.createFile(file_path, .{});
    try f.writeAll(content);
    f.close();

    const tmpl = try Template(Data).initFromFile(a, file_path);
    defer tmpl.deinit();

    const buf = try tmpl.renderOwned(.{ .num = 50 }, .{});
    defer buf.deinit();

    const expectStr = std.testing.expectEqualStrings;
    try expectStr("<h1>50</h1>", buf.items);
    try cwd.deleteFile(file_path);
}

fn Range(comptime T: type) type {
    return struct {
        const Self = @This();
        start: usize,
        end: usize,

        pub fn len(self: Self) usize {
            return self.end - self.start;
        }

        pub fn of(self: Self, slice: []const T) []const T {
            return slice[self.start..self.end];
        }

        pub fn before(self: Self, slice: []const T) []const T {
            return slice[0..self.start];
        }

        pub fn after(self: Self, slice: []const T) []const T {
            return slice[self.end..];
        }
    };
}

const StrRange = Range(u8);

const Token = struct {
    tag: Tag,
    range: StrRange,
};

const isKeyword = std.zig.Token.keywords.has;

const Tag = enum(u8) {
    period,
    l_brace,
    identifier,
    r_brace,
    keyword,
    eof,
};

const State = enum(u8) {
    start,
    at_sign,
    string_literal,
    string_literal_escape,
    identifier,
};

const Tokenizer = struct {
    const Self = @This();

    html: []const u8,
    index: usize = 0,

    pub fn next(self: *Self) Token {
        var state = State.start;
        var tag = Tag.eof;
        var start = self.index;

        while (true) : (self.index += 1) {
            if (self.index >= self.html.len) {
                tag = Tag.eof;
                break;
            }

            const c = self.html[self.index];
            switch (state) {
                .start => {
                    switch (c) {
                        '.' => {
                            tag = .period;
                            self.index += 1;
                            break;
                        },
                        '{' => {
                            tag = .l_brace;
                            self.index += 1;
                            break;
                        },
                        '}' => {
                            tag = .r_brace;
                            self.index += 1;
                            break;
                        },
                        '@' => state = State.at_sign,
                        'a'...'z', 'A'...'Z', '_' => {
                            state = State.identifier;
                            tag = Tag.identifier;
                        },
                        else => start = self.index + 1,
                    }
                },
                .at_sign => {
                    switch (c) {
                        '"' => {
                            tag = Tag.identifier;
                            state = State.string_literal;
                        },
                        else => {
                            tag = Tag.eof;
                            state = State.start;
                            start = self.index + 1;
                        },
                    }
                },
                .identifier => {
                    switch (c) {
                        'a'...'z', 'A'...'Z', '0'...'9', '_' => {},
                        else => {
                            if (isKeyword(self.html[start..self.index])) {
                                tag = Tag.keyword;
                            }
                            break;
                        },
                    }
                },
                .string_literal => {
                    switch (c) {
                        '"' => {
                            self.index += 1;
                            break;
                        },
                        '\\' => state = State.string_literal_escape,
                        else => {},
                    }
                },
                .string_literal_escape => {
                    switch (c) {
                        '\r', '\n' => {
                            tag = Tag.eof;
                            state = State.start;
                            start = self.index + 1;
                        },
                        else => state = State.string_literal,
                    }
                },
            }
        }

        if (tag == .eof) {
            start = self.html.len;
            self.index = start;
        }

        return Token{
            .tag = tag,
            .range = .{
                .start = start,
                .end = self.index,
            },
        };
    }
};

const FieldExtractor = struct {
    const Self = @This();

    tokenizer: Tokenizer,

    pub fn init(html: []const u8) Self {
        return .{
            .tokenizer = .{
                .html = html,
            },
        };
    }

    pub fn next(self: *Self) ?StrRange {
        var tokens: [FieldTags.len]Token = undefined;
        var i: usize = 0;

        while (self.tokenizer.next()) |token| {
            if (token.tag == .eof)
                break;

            if (token.tag == FieldTags[i]) {
                tokens[i] = token;
                i += 1;
                if (i >= FieldTags.len) {
                    const marker_range = StrRange{
                        .start = tokens[0].range.start,
                        .end = token.range.end,
                    };

                    //empty identifier
                    if (std.mem.eql(u8, marker_range.of(self.html), ".{@\"\"}")) {
                        i = 0;
                        continue;
                    }

                    return marker_range;
                }
            } else if (token.tag == FieldTags[0]) {
                tokens[0] = token;
                i = 1;
            } else {
                i = 0;
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
    try expectStr(".{field_nm}", marker.of(html));
    try expectStr("<html>", marker.before(html));
    try expectStr("</html>", marker.after(html));

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
    try expectStr(".{field_nm}", marker.marker_range.of(html));
    try expectStr("field_nm", marker.name_range.of(html));
    try expectStr("", marker.marker_range.before(html));
    try expectStr("", marker.marker_range.after(html));

    try expect(tokenizer.next() == null);

    // 6 - multiple tags
    html = "<html>.{field_nm}</html>.{field_nm}";
    tokenizer = Tokenizer.init(html);
    marker = tokenizer.next() orelse unreachable;
    try expectStr(".{field_nm}", marker.marker_range.of(html));
    try expectStr("field_nm", marker.name_range.of(html));
    try expectStr("</html>.{field_nm}", marker.marker_range.after(html));
    try expectStr("<html>", marker.marker_range.before(html));

    marker = tokenizer.next() orelse unreachable;
    try expectStr(".{field_nm}", marker.marker_range.of(html));
    try expectStr("field_nm", marker.name_range.of(html));
    try expectStr("", marker.marker_range.after(html));
    try expectStr("<html>.{field_nm}</html>", marker.marker_range.before(html));

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
    try expectStr(".{field_nm}", marker.marker_range.of(html));
    try expectStr("field_nm", marker.name_range.of(html));
    try expectStr("}</html>", marker.marker_range.after(html));
    try expectStr("<html>.{", marker.marker_range.before(html));
    try expect(tokenizer.next() == null);

    // 10 - string identifiers
    html = "<html>.{@\"420\"}</html>";
    tokenizer = Tokenizer.init(html);
    marker = tokenizer.next() orelse unreachable;
    try expectStr(".{@\"420\"}", marker.marker_range.of(html));
    try expectStr("420", marker.name_range.of(html));
    try expectStr("</html>", marker.marker_range.after(html));
    try expectStr("<html>", marker.marker_range.before(html));
    try expect(tokenizer.next() == null);

    // 11 - identifiers cannot be blank
    html = "<html>.{@\"\"}</html>";
    tokenizer = Tokenizer.init(html);
    try expect(tokenizer.next() == null);

    // 12 - some bastard token from hell.
    html = "<html>.{@\".{field_nm}\"}</html>";
    tokenizer = Tokenizer.init(html);
    marker = tokenizer.next() orelse unreachable;
    try expectStr(".{@\".{field_nm}\"}", marker.marker_range.of(html));
    try expectStr(".{field_nm}", marker.name_range.of(html));
    try expectStr("</html>", marker.marker_range.after(html));
    try expectStr("<html>", marker.marker_range.before(html));
    try expect(tokenizer.next() == null);

    html = "\".{field_nm}\"";
    tokenizer = Tokenizer.init(html);
    marker = tokenizer.next() orelse unreachable;
    try expectStr(".{field_nm}", marker.marker_range.of(html));
    try expectStr("field_nm", marker.name_range.of(html));
    try expectStr("\"", marker.marker_range.after(html));
    try expectStr("\"", marker.marker_range.before(html));
}

test {
    const T = struct {
        @"\"Hello, World!\"": u8,
        @" ": u8,
        @"fn": u8,
    };

    const info = @typeInfo(T).Struct.fields;
    try std.testing.expectEqualStrings("\"Hello, World!\"", info[0].name);
    try std.testing.expectEqualStrings(" ", info[1].name);
    try std.testing.expectEqualStrings("fn", info[2].name);
}
