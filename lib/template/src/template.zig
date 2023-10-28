const std = @import("std");
const Allocator = std.mem.Allocator;

const meta = @import("meta.zig");
const renderer = @import("render.zig");
const RenderOptions = renderer.RenderOptions;

pub fn Template(comptime T: type) type {

    const type_fields = comptime meta.fieldNames(T);
    const max_field_nm_len = comptime blk: {
        var len = 0;
        for (type_fields) |f| {
            if (f.len > len)
                len = type_fields.len;
        }
        break :blk len;
    };
        
    return struct {
        const Self = @This();

        allocator: Allocator,
        html: std.ArrayList(u8),
        markers: std.ArrayList(StrRange),

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
                .html = html_template, //todo rong.
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
                        try renderer.renderField(@field(data, f.name), writer, opts);
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

const DeconstructedHtml = struct {
    const Marker = struct {
        name: []const u8,
        index: usize,
    };
    
    text: std.ArrayList(u8),
    markers: std.ArrayList(Marker),

};

test "building template works." {
    const a = std.testing.allocator;
    const Test = struct {
        pub fn assert(data: anytype, input_html: [:0]const u8, expected: []const u8, opts: RenderOptions) !void {
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
