const std = @import("std");
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.template);

const meta = @import("meta.zig");
const renderer = @import("render.zig");
pub const RenderOptions = renderer.RenderOptions;

pub fn Template(comptime T: type) type {
    return struct {
        const info: std.builtin.Type = @typeInfo(T);
        const fields = info.Struct.fields;

        const Self = @This();

        html: DeconstructedHtml,

        pub fn init(a: Allocator, html_template: []const u8) !Self {
            var self = Self{
                .html = try DeconstructedHtml.init(a, html_template),
            };
            errdefer self.deinit();

            var fields_used = [_]bool{false} ** fields.len;
            for (self.html.marker_names) |tmpl_field_nm| {
                const index: ?usize = blk: {
                    inline for (fields, 0..) |field, i| {
                        if (std.mem.eql(u8, field.name, tmpl_field_nm))
                            break :blk i;
                    }

                    break :blk null;
                };

                if (index) |i| {
                    fields_used[i] = true;
                } else {
                    log.warn("Detected unknown field in template ({s}): '{s}'", .{ @typeName(T), tmpl_field_nm });
                }
            }

            inline for (fields_used, 0..) |b, i| {
                if (!b) {
                    log.warn("Field '{s}' not used in template for {s}", .{ fields[i].name, @typeName(T) });
                }
            }

            return self;
        }

        pub fn initFromFile(a: Allocator, file: []const u8) !Self {
            const max_size = 1 << 24; // 16MB, why not.
            var f: std.fs.File = try std.fs.cwd().openFile(file, .{});
            defer f.close();
            const file_text = try f.readToEndAlloc(a, max_size);
            defer a.free(file_text);

            return try init(a, file_text);
        }

        pub fn deinit(self: Self) void {
            self.html.deinit();
        }

        pub fn render(self: Self, data: T, writer: anytype, opts: RenderOptions) !void {
            var start: usize = 0;
            for (self.html.markers) |m| {
                try writer.writeAll(self.html.text[start..m.text_start]);
                start = m.text_start;

                inline for (fields) |field| {
                    if (std.mem.eql(u8, field.name, m.name)) {
                        try renderer.renderField(@field(data, field.name), writer, opts);
                    }
                }
            }

            if (start < self.html.text.len) {
                try writer.writeAll(self.html.text[start..]);
            }
        }

        pub fn renderOwned(self: Self, data: T, opts: RenderOptions) !std.ArrayList(u8) {
            var buf = std.ArrayList(u8).init(self.html.allocator);
            errdefer buf.deinit();
            try self.render(data, buf.writer(), opts);
            return buf;
        }
    };
}

test "building template works." {
    const a = std.testing.allocator;
    const Test = struct {
        pub fn assert(data: anytype, input_html: []const u8, expected: []const u8, opts: RenderOptions) !void {
            const T = @TypeOf(data);
            const Templ = Template(T);
            var tmp = try Templ.init(a, input_html);
            defer tmp.deinit();

            const buf = try tmp.renderOwned(data, opts);
            defer buf.deinit();
            try std.testing.expectEqualStrings(expected, buf.items);
        }
    };

    try Test.assert(.{ .val = 50 }, "<h1>.{val}</h1>", "<h1>50</h1>", .{});
    try Test.assert(.{ .greeting = "hello", .person = "world" }, "<html>.{greeting}, .{person}!</html>", "<html>hello, world!</html>", .{});
    try Test.assert(.{ .raw_html = "<h1>High-Class Information Below...</h1>" }, "<html>.{raw_html}</html>", "<html>&lt;h1&gt;High-Class Information Below...&lt;&#x2F;h1&gt;</html>", .{});
    try Test.assert(.{ .no_encode = "<h1>Bold!</h1>" }, "<html>.{no_encode}</html>", "<html><h1>Bold!</h1></html>", .{ .html_encode = false });
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

const Tokenizer = @import("tokenizer.zig");
const StringPool = @import("str_pool.zig");
const DeconstructedHtml = struct {
    const Marker = struct {
        name: []const u8,
        text_start: usize,
    };

    const Self = @This();

    allocator: Allocator,
    text: []const u8,
    marker_names: []const []const u8,
    markers: []const Marker,

    pub fn init(a: Allocator, html: []const u8) !Self {
        var token_stack = std.ArrayList(Tokenizer.Token).init(a);
        defer token_stack.deinit();

        var text_buf = std.ArrayList(u8).init(a);
        defer text_buf.deinit();
        var str_pool = StringPool.init(a);
        defer str_pool.deinit();
        var markers_buf = std.ArrayList(Marker).init(a);
        defer markers_buf.deinit();

        var tokenizer = Tokenizer{ .html = html };
        var text_start: usize = 0;
        while (true) {
            const token = tokenizer.next();
            switch (token.tag) {
                .eof => break,
                .period => {
                    token_stack.clearRetainingCapacity();
                    try token_stack.append(token);
                },
                else => |t| {
                    try token_stack.append(token);
                    if (t == .r_brace) {
                        if (extractMarker(a, token_stack.items, html)) |marker_name| {
                            const interned_name = try str_pool.intern(marker_name);

                            try text_buf.appendSlice(html[text_start..token_stack.items[0].range.start]);
                            try markers_buf.append(.{ .name = interned_name, .text_start = text_buf.items.len });
                            text_start = token.range.end;
                        }
                        token_stack.clearRetainingCapacity();
                    }
                },
            }
        }

        try text_buf.appendSlice(html[text_start..]);

        const text = try text_buf.toOwnedSlice();
        errdefer a.free(text);
        const marker_names = try str_pool.toOwnedSlice();
        errdefer freeStrArr(a, marker_names);
        const markers = try markers_buf.toOwnedSlice();
        errdefer a.free(markers);

        return .{
            .allocator = a,
            .text = text,
            .marker_names = marker_names,
            .markers = markers,
        };
    }

    pub fn deinit(self: Self) void {
        const a = self.allocator;
        a.free(self.text);
        freeStrArr(a, self.marker_names);
        a.free(self.markers);
    }

    fn freeStrArr(a: Allocator, strs: []const []const u8) void {
        for (strs) |str| a.free(str);
        a.free(strs);
    }

    fn extractMarker(a: Allocator, tokens: []const Tokenizer.Token, html: []const u8) ?[]const u8 {
        if (tokens.len < 4)
            return null;

        // This may be subject to change if I ever allow for inlining render options into the template syntax.
        if (tokens[0].tag != .period or tokens[1].tag != .l_brace or tokens[2].tag != .identifier or tokens[tokens.len - 1].tag != .r_brace)
            return null;

        const ident_txt = tokens[2].range.of(html);

        return allocIdentifierName(a, ident_txt) catch |err| blk: {
            switch (err) {
                IdentifierNameParseError.BlankIdentifier => {
                    std.log.warn("Blank marker identifier detected in template: {s}", .{ident_txt});
                },
                IdentifierNameParseError.InvalidIdentifier => {
                    std.log.warn("Invalid marker identifier detected in template: {s}", .{ident_txt});
                },
                else => {},
            }

            break :blk null;
        };
    }
};

test "html template deconstruction" {
    const a = std.testing.allocator;
    const expectStr = std.testing.expectEqualStrings;
    const expectEq = std.testing.expectEqual;

    const ExpectedMarker = struct {
        name_index: usize,
        text_start: usize,
    };

    const Test = struct {
        ttml: []const u8,

        expected_text: []const u8,
        expected_marker_names: []const []const u8,
        expected_markers: []const ExpectedMarker,

        pub fn assert(self: @This()) !void {
            var dec = try DeconstructedHtml.init(a, self.ttml);
            defer dec.deinit();
            try expectStr(self.expected_text, dec.text);

            for (self.expected_marker_names, dec.marker_names) |expected, actual| {
                try expectStr(expected, actual);
            }

            for (self.expected_markers, dec.markers) |expected, actual| {
                try expectEq(expected.text_start, actual.text_start);
                try expectStr(self.expected_marker_names[expected.name_index], actual.name);
            }
        }
    };

    try Test.assert(.{ // markers within html
        .ttml = "<html>.{field_nm}</html>",
        .expected_text = "<html></html>",
        .expected_marker_names = &[_][]const u8{"field_nm"},
        .expected_markers = &[_]ExpectedMarker{.{ .name_index = 0, .text_start = 6 }},
    });

    try Test.assert(.{ // only markers.
        .ttml = ".{field_nm}",
        .expected_text = "",
        .expected_marker_names = &[_][]const u8{"field_nm"},
        .expected_markers = &[_]ExpectedMarker{.{ .name_index = 0, .text_start = 0 }},
    });

    try Test.assert(.{ // no markers.
        .ttml = "<html></html>",
        .expected_text = "<html></html>",
        .expected_marker_names = &[_][]const u8{},
        .expected_markers = &[_]ExpectedMarker{},
    });

    try Test.assert(.{ // multiple markers.
        .ttml = "<html>.{field_nm}</html>.{field_nm}",
        .expected_text = "<html></html>",
        .expected_marker_names = &[_][]const u8{"field_nm"},
        .expected_markers = &[_]ExpectedMarker{ .{ .name_index = 0, .text_start = 6 }, .{ .name_index = 0, .text_start = 13 } },
    });
}

const IdentifierNameParseError = error{
    BlankIdentifier,
    InvalidIdentifier,
};

fn allocIdentifierName(a: Allocator, identifier: []const u8) ![]const u8 {
    if (identifier.len == 0)
        return IdentifierNameParseError.BlankIdentifier;

    if (identifier[0] != '@') {
        var name = try a.alloc(u8, identifier.len);
        std.mem.copy(u8, name, identifier);
        return name;
    }

    if (identifier.len < 3 or identifier[1] != '"' or identifier[identifier.len - 1] != '"')
        return IdentifierNameParseError.InvalidIdentifier;

    const id_part = identifier[2 .. identifier.len - 1];
    if (id_part.len == 0)
        return IdentifierNameParseError.BlankIdentifier;

    var buf = try a.alloc(u8, id_part.len);
    defer a.free(buf);

    var buffer = std.io.fixedBufferStream(buf);
    const writer = buffer.writer();

    var i: usize = 0;
    while (i < id_part.len) : (i += 1) {
        var c = id_part[i];
        if (c == '\\') {
            i += 1;
            if (i >= id_part.len)
                return IdentifierNameParseError.InvalidIdentifier;
            c = id_part[i];
        }
        try writer.writeByte(c);
    }

    var name = try a.alloc(u8, buffer.pos);
    std.mem.copy(u8, name, buf[0..buffer.pos]);
    return name;
}

test "identifier name parser" {
    const expectStr = std.testing.expectEqualStrings;
    const a = std.testing.allocator;

    const Test = struct {
        pub fn assert(expected: []const u8, identifier: []const u8) !void {
            const name = try allocIdentifierName(a, identifier);
            defer a.free(name);
            try expectStr(expected, name);
        }

        pub fn assertErr(expectedErr: anyerror, identifier: []const u8) !void {
            try std.testing.expectError(expectedErr, allocIdentifierName(a, identifier));
        }
    };

    try Test.assert("field_nm", "field_nm");
    try Test.assert("field_nm", "@\"field_nm\"");
    try Test.assert(" ", "@\" \"");
    try Test.assert("fn", "@\"fn\"");

    try Test.assertErr(IdentifierNameParseError.BlankIdentifier, "");
    try Test.assertErr(IdentifierNameParseError.BlankIdentifier, "@\"\"");
    try Test.assertErr(IdentifierNameParseError.InvalidIdentifier, "@\"field_nm");
}
