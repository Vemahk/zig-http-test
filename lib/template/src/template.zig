const std = @import("std");
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.template);

const meta = @import("meta.zig");
const renderer = @import("render.zig");
pub const RenderOptions = renderer.RenderOptions;

pub fn Template(comptime T: type) type {
    return struct {
        const field_names = meta.fieldNames(T);
        const Field = struct {
            text_start: usize,
            field_index: usize,
        };

        const Self = @This();

        allocator: Allocator,
        tmpl: []const u8,
        markers: []const Field,

        pub fn init(a: Allocator, template_str: []const u8) !Self {
            var str_buf = std.ArrayList(u8).init(a);
            defer str_buf.deinit();
            var marker_buf = std.ArrayList(Field).init(a);
            defer marker_buf.deinit();

            var iter = TemplateIterator.init(a, template_str);
            var fields_used = [_]bool{false} ** field_names.len;
            var text_start: usize = 0;
            while (try iter.next()) |marker| {
                defer marker.deinit();

                const index: ?usize = blk: {
                    inline for (field_names, 0..) |field_name, i| {
                        if (std.mem.eql(u8, field_name, marker.name))
                            break :blk i;
                    }

                    break :blk null;
                };

                if (index) |i| {
                    fields_used[i] = true;

                    try str_buf.appendSlice(template_str[text_start..marker.range.start]);
                    text_start = marker.range.end;
                    try marker_buf.append(.{
                        .text_start = str_buf.items.len,
                        .field_index = i,
                    });
                } else {
                    log.warn("Detected unknown field in template ({s}): '{s}'", .{ @typeName(T), marker.name });
                }
            }

            if (text_start < template_str.len) {
                try str_buf.appendSlice(template_str[text_start..]);
            }

            for (fields_used, 0..) |b, i| {
                if (!b) {
                    log.warn("Field '{s}' not used in template for {s}", .{ field_names[i], @typeName(T) });
                }
            }

            const tmpl = try str_buf.toOwnedSlice();
            errdefer a.free(tmpl);
            const markers = try marker_buf.toOwnedSlice();
            errdefer a.free(markers);

            return .{
                .allocator = a,
                .tmpl = tmpl,
                .markers = markers,
            };
        }

        pub fn initFromFile(a: Allocator, file: []const u8) !Self {
            const max_size = 1 << 24; // 16MB, why not.
            const file_text = try std.fs.cwd().readFileAlloc(a, file, max_size);
            defer a.free(file_text);

            return try init(a, file_text);
        }

        pub fn deinit(self: Self) void {
            self.allocator.free(self.tmpl);
            self.allocator.free(self.markers);
        }

        pub fn render(self: Self, data: T, writer: anytype, opts: anytype) !void {
            comptime {
                const TOpt = @TypeOf(opts);
                const info: std.builtin.Type = @typeInfo(TOpt);
                const fields: []const std.builtin.Type.StructField = info.Struct.fields;
                for (fields) |field| {
                    if (!@hasField(T, field.name))
                        @compileError("'" ++ field.name ++ "' is not defined in the data struct of this template.");
                }
            }

            var start: usize = 0;
            for (self.markers) |marker| {
                try writer.writeAll(self.tmpl[start..marker.text_start]);
                start = marker.text_start;

                inline for (field_names, 0..) |field_name, i| {
                    if (i == marker.field_index) {
                        const o: RenderOptions = if (@hasField(@TypeOf(opts), field_name)) @field(opts, field_name) else .{};
                        try renderer.renderField(@field(data, field_name), writer, o);
                    }
                }
            }

            if (start < self.tmpl.len) {
                try writer.writeAll(self.tmpl[start..]);
            }
        }

        pub fn renderOwned(self: Self, data: T, opts: anytype) !std.ArrayList(u8) {
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
        const Self = @This();

        input_tmpl: []const u8,
        expected: []const u8,

        pub fn assert(data: anytype, tmpl: []const u8, expected_out: []const u8) !void {
            return try assertOpts(data, tmpl, expected_out, .{});
        }

        pub fn assertOpts(data: anytype, tmpl: []const u8, expected_out: []const u8, opts: anytype) !void {
            const T = @TypeOf(data);
            const Templ = Template(T);
            var tmp = try Templ.init(a, tmpl);
            defer tmp.deinit();

            const buf = try tmp.renderOwned(data, opts);
            defer buf.deinit();
            try std.testing.expectEqualStrings(expected_out, buf.items);
        }
    };

    try Test.assert(.{ .val = 50 }, "<h1>.{val}</h1>", "<h1>50</h1>");
    try Test.assert(.{ .greeting = "hello", .person = "world" }, "<html>.{greeting}, .{person}!</html>", "<html>hello, world!</html>");
    try Test.assert(.{ .raw_html = "<h1>High-Class Information Below...</h1>" }, "<html>.{raw_html}</html>", "<html>&lt;h1&gt;High-Class Information Below...&lt;&#x2F;h1&gt;</html>");
    try Test.assert(.{ 9, 10, 21 }, ".{@\"0\"} + .{@\"1\"} = .{@\"2\"}", "9 + 10 = 21"); //tuple

    const no_encode_plz: RenderOptions = .{ .html_encode = false };
    try Test.assertOpts(.{ .no_encode = "<h1>Bold!</h1>" }, "<html>.{no_encode}</html>", "<html><h1>Bold!</h1></html>", .{ .no_encode = no_encode_plz });
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

const Range = @import("range.zig").Range(u8);
const Marker = struct {
    const Self = @This();

    allocator: Allocator,
    range: Range,
    name: []const u8,

    pub fn deinit(self: Self) void {
        self.allocator.free(self.name);
    }
};

const Tokenizer = @import("tokenizer.zig");
const TemplateIterator = struct {
    const Self = @This();

    allocator: Allocator,
    tokenizer: Tokenizer,

    pub fn init(a: Allocator, tmpl: []const u8) Self {
        return .{
            .allocator = a,
            .tokenizer = .{
                .tmpl = tmpl,
            },
        };
    }

    /// Returns an owned Marker.
    /// The marker is given the allocator this iterator was initialized with.
    /// The marker's name will be freed when the marker is deinited.
    pub fn next(self: *Self) Allocator.Error!?Marker {
        const a = self.allocator;
        var token_stack = std.ArrayList(Tokenizer.Token).init(a);
        defer token_stack.deinit();

        while (true) {
            const token = self.tokenizer.next();
            switch (token.tag) {
                .eof => return null,
                .period => {
                    token_stack.clearRetainingCapacity();
                    try token_stack.append(token);
                },
                else => |t| {
                    try token_stack.append(token);
                    if (t == .r_brace) {
                        if (extractMarker(a, token_stack.items, self.tokenizer.tmpl)) |marker|
                            return marker;

                        token_stack.clearRetainingCapacity();
                    }
                },
            }
        }
    }

    fn extractMarker(a: Allocator, tokens: []const Tokenizer.Token, tmpl: []const u8) ?Marker {
        if (tokens.len < 4)
            return null;

        // This may be subject to change if I ever allow for inlining render options into the template syntax.
        if (tokens[0].tag != .period or tokens[1].tag != .l_brace or tokens[2].tag != .identifier or tokens[tokens.len - 1].tag != .r_brace)
            return null;

        const ident_txt = tokens[2].range.of(tmpl);

        const name = allocIdentifierName(a, ident_txt) catch |err| {
            switch (err) {
                IdentifierNameParseError.BlankIdentifier => {
                    std.log.warn("Blank marker identifier detected in template: {s}", .{ident_txt});
                },
                IdentifierNameParseError.InvalidIdentifier => {
                    std.log.warn("Invalid marker identifier detected in template: {s}", .{ident_txt});
                },
                else => {},
            }

            return null;
        };

        return .{
            .allocator = a,
            .range = .{
                .start = tokens[0].range.start,
                .end = tokens[tokens.len - 1].range.end,
            },
            .name = name,
        };
    }
};

test "template deconstruction" {
    const a = std.testing.allocator;
    const expectStr = std.testing.expectEqualStrings;
    const expectEq = std.testing.expectEqual;

    const ExpectedMarker = struct {
        range: Range,
        name: []const u8,
    };

    const Test = struct {
        tmpl: []const u8,
        expected_markers: []const ExpectedMarker,

        pub fn assert(self: @This()) !void {
            var extractor = TemplateIterator.init(a, self.tmpl);
            var i: usize = 0;
            while (try extractor.next()) |marker| {
                defer marker.deinit();
                const expected_marker = self.expected_markers[i];
                try expectEq(expected_marker.range, marker.range);
                try expectStr(expected_marker.name, marker.name);

                i += 1;
            }
        }
    };

    try Test.assert(.{ // markers within html
        .tmpl = "<html>.{field_nm}</html>",
        .expected_markers = &[_]ExpectedMarker{
            .{
                .range = .{ .start = 6, .end = 17 },
                .name = "field_nm",
            },
        },
    });

    try Test.assert(.{ // only markers.
        .tmpl = ".{field_nm}",
        .expected_markers = &[_]ExpectedMarker{
            .{
                .range = .{ .start = 0, .end = 11 },
                .name = "field_nm",
            },
        },
    });

    try Test.assert(.{ // no markers.
        .tmpl = "<html></html>",
        .expected_markers = &[_]ExpectedMarker{},
    });

    try Test.assert(.{ // multiple markers.
        .tmpl = "<html>.{field_nm}</html>.{field_nm}",
        .expected_markers = &[_]ExpectedMarker{
            .{
                .range = .{ .start = 6, .end = 17 },
                .name = "field_nm",
            },
            .{
                .range = .{ .start = 24, .end = 35 },
                .name = "field_nm",
            },
        },
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
